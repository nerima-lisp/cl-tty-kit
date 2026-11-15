(in-package #:cl-tty-kit)

(defun %input-monitor-prefix (decoder)
  (let ((paste (input-decoder-pending-paste decoder)))
    (concatenate
      '(vector (unsigned-byte 8))
      (cl-codec-kit:string-to-octets
        (if paste
            (concatenate 'string (input-decoder-pending-paste-start-source decoder)
                         paste (input-decoder-pending-string decoder))
            (input-decoder-pending-string decoder))
        :encoding :utf-8)
      (input-decoder-pending-octets decoder))))

(defun %empty-input-monitor-decoder (decoder)
  (setf (input-decoder-pending-string decoder) ""
        (input-decoder-pending-octets decoder) +empty-octet-vector+
        (input-decoder-pending-paste decoder) nil
        (input-decoder-pending-paste-start-source decoder) nil))

(defun %fresh-input-monitor-decoder (decoder)
  (make-input-decoder
    :collect-bracketed-paste t
    :normalize-paste-line-endings
    (input-decoder-normalize-paste-line-endings-p decoder)
    :max-pending (input-decoder-max-pending decoder)))

(defun %copy-input-monitor-decoder (decoder)
  (let ((copy (%fresh-input-monitor-decoder decoder))
        (paste (input-decoder-pending-paste decoder)))
    (setf (input-decoder-pending-string copy)
          (copy-seq (input-decoder-pending-string decoder))
          (input-decoder-pending-octets copy)
          (copy-seq (input-decoder-pending-octets decoder))
          (input-decoder-pending-paste-start-source copy)
          (when paste (copy-seq (input-decoder-pending-paste-start-source decoder)))
          (input-decoder-pending-paste copy)
          (when paste
            (make-array (length paste) :element-type 'character
                                      :adjustable t :fill-pointer (length paste)
                                      :initial-contents paste)))
    copy))

(defun %input-monitor-retained-octets (chunks size consumed)
  (let ((source (make-array size :element-type '(unsigned-byte 8))))
    (loop with offset = 0
          for chunk in (nreverse chunks)
          do (replace source chunk :start1 offset)
             (incf offset (length chunk)))
    (if (null consumed)
        source
        (let* ((removed (loop for (start . end) in consumed sum (- end start)))
               (result (make-array (- size removed) :element-type '(unsigned-byte 8)))
               (source-offset 0)
               (target-offset 0))
          (dolist (range (nreverse consumed))
            (replace result source :start1 target-offset :start2 source-offset
                                   :end2 (car range))
            (incf target-offset (- (car range) source-offset))
            (setf source-offset (cdr range)))
          (replace result source :start1 target-offset :start2 source-offset)
          result))))

(declaim (notinline %input-monitor-stopped-p))

#+sb-thread
(defun %input-monitor-stopped-p (lock stop-state)
  (cl-concurrent-kit:with-lock-held (lock) (car stop-state)))

#+sb-thread
(defun call-with-input-monitor (fd function on-event &key on-finish decoder)
  "Run FUNCTION on the caller while a helper observes terminal FD.
Return retained octets, FUNCTION's multiple values as a list, and diagnostics.
Only a normal ON-EVENT return of :CONSUME removes that event's original byte
range. Other values and callback failures retain its bytes. Shutdown may leave
read bytes without event notifications; they remain in the retained result.

DECODER transfers ownership of its pending UTF-8, escape, and paste input to
this scope. It is emptied while preserving its settings. The helper uses an
independent copy with paste collection enabled. The result includes the initial
pending prefix followed by bytes read, excluding consumed events. Replay it once
through the now-empty DECODER. ON-FINISH receives the same array after joining,
also during nonlocal exit; use one reference for replay, never both.

Decoder failures reset the private decoder and retry the current byte once;
callback failures retain the event and monitoring continues. Diagnostics are
two-element (PHASE CONDITION) lists, recording only the first serious condition
per phase (:DECODE, :ON-EVENT, :IO, :WORKER), in first-occurrence order. Helper
failures never replace FUNCTION's values. A caller nonlocal exit takes priority
and receives bytes through ON-FINISH, without normal diagnostic return values.

The caller owns reads from FD exclusively and keeps it open. Cleanup requests
stop and joins cooperatively, without returning on timeout with a live helper.
ON-EVENT's execution counts against the 50ms stop-and-join requirement, so it
must return promptly and never block or wait for the caller. This cannot force
arbitrary callback code or an OS-descheduled thread to finish. ON-FINISH runs
with interrupts inhibited and must only save its bytes. The helper polls with
a 5ms timeout and checks stop between bytes. It does not flush unfinished input
or change FD's mode. Requires SBCL
thread support; otherwise signals UNSUPPORTED-FEATURE."
  (%assert-fd fd)
  (dolist (callback (list function on-event))
    (unless (or (functionp callback) (and (symbolp callback) (fboundp callback)))
      (error "Input monitor callback must be a function designator, got ~S." callback)))
  (when (and on-finish
             (not (or (functionp on-finish)
                      (and (symbolp on-finish) (fboundp on-finish)))))
    (error "Input monitor finish callback must be a function designator, got ~S."
           on-finish))
  (when (and decoder (not (typep decoder 'input-decoder)))
    (error "Input monitor decoder must be an INPUT-DECODER, got ~S." decoder))
  (let ((lock (cl-concurrent-kit:make-lock :name "cl-tty-kit input monitor"))
        (stop-state (list nil))
        (thread nil)
        (private-decoder nil)
        (chunks nil)
        (size 0)
        (source-position 0)
        (consumed nil)
        (diagnostics nil)
        (octets nil)
        (body-values nil)
        (byte-buffer (make-array 1 :element-type '(unsigned-byte 8))))
    (labels ((stopped-p ()
               (%input-monitor-stopped-p lock stop-state))
             (note-condition (phase condition)
               (unless (assoc phase diagnostics)
                 (push (list phase condition) diagnostics)))
             (decode-byte ()
               (let ((lengths nil)
                     (events nil))
                 (handler-case
                     (let ((*input-decoder-source-length-sink*
                             (lambda (length) (push length lengths))))
                       (setf events (decode-input-chunk private-decoder byte-buffer)))
                   (serious-condition (condition)
                     (note-condition :decode condition)
                     (return-from decode-byte nil)))
                 (loop for event in events
                       for length in (nreverse lengths)
                       for end = (+ source-position length)
                       do (unless (stopped-p)
                            (let ((decision
                                    (handler-case (funcall on-event event)
                                      (serious-condition (condition)
                                        (note-condition :on-event condition)
                                        nil))))
                              (when (eq decision :consume)
                                (push (cons source-position end) consumed))))
                          (setf source-position end))
                 t))
             (observe-byte (byte position)
               (setf (aref byte-buffer 0) byte)
               (unless (decode-byte)
                 ;; Failed pending input stays in the raw result as a gap.
                 ;; The current byte can still be an independent key (C-g).
                 (setf private-decoder (%fresh-input-monitor-decoder private-decoder)
                       source-position position)
                 (unless (decode-byte)
                   (setf private-decoder (%fresh-input-monitor-decoder private-decoder)
                         source-position (1+ position)))))
             (monitor ()
               (handler-case
                   (let ((buffer (make-array 4096 :element-type '(unsigned-byte 8))))
                     (block reading
                       (loop until (stopped-p)
                             do (let ((count
                                        (handler-case
                                            (when (fd-wait fd :input 0.005)
                                              (unless (stopped-p)
                                                (fd-read-octets fd buffer)))
                                          (serious-condition (condition)
                                            (note-condition :io condition)
                                            (return-from reading nil)))))
                                  (when count
                                    (when (zerop count) (return))
                                    (let ((chunk (subseq buffer 0 count))
                                          (start size))
                                      (push chunk chunks)
                                      (incf size count)
                                      (loop for index below count
                                            until (stopped-p)
                                            do (observe-byte (aref chunk index)
                                                             (+ start index)))))))))
                 (serious-condition (condition)
                   (note-condition :worker condition)))))
      ;; Install cleanup before transferring state or publishing a helper.
      (sb-sys:without-interrupts
        (unwind-protect
             (progn
               (if decoder
                   (let ((prefix (%input-monitor-prefix decoder))
                         (copy (%copy-input-monitor-decoder decoder)))
                     (setf chunks (list prefix)
                           size (length prefix)
                           private-decoder copy)
                     (%empty-input-monitor-decoder decoder))
                   (setf private-decoder
                         (make-input-decoder :collect-bracketed-paste t)))
               (setf thread (cl-concurrent-kit:make-thread
                              #'monitor :name "cl-tty-kit input monitor"))
               (setf body-values
                     (multiple-value-list
                       (sb-sys:with-local-interrupts (funcall function)))))
          (cl-concurrent-kit:with-lock-held (lock) (setf (car stop-state) t))
          (when thread (cl-concurrent-kit:join-thread thread :default nil))
          (setf octets (%input-monitor-retained-octets chunks size consumed))
          (when on-finish (funcall on-finish octets))))
      (values octets body-values (nreverse diagnostics)))))

#-sb-thread
(defun call-with-input-monitor (fd function on-event &key on-finish decoder)
  "Monitor terminal input while FUNCTION runs; requires SBCL thread support."
  (declare (ignore fd function on-event on-finish decoder))
  (unsupported :input-monitor))
