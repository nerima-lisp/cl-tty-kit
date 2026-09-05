(in-package #:cl-tty-kit)

(defconstant +max-incomplete-escape-length+ 1024
  "Maximum bytes retained for an escape sequence that has not reached a final byte.")

(defun %incomplete-escape-sequence-p (string index)
  (when (char= (aref string index) #\Esc)
    (let ((limit (length string)))
      (and (<= (- limit index) +max-incomplete-escape-length+)
           (cond
             ((>= (1+ index) limit) t)
             ((char= (aref string (1+ index)) #\[)
              (let ((body-start (+ index 2)))
                (if (>= body-start limit)
                    t
                    ;; A CSI runs until its final byte (0x40-0x7E); every earlier
                    ;; byte is a parameter or intermediate. Treating anything before
                    ;; that byte as still-incomplete keeps a split parameter list --
                    ;; including an SGR mouse report's `<Cb;Cx;Cy' -- buffered
                    ;; instead of being decoded as a bare ESC.
                    (loop for final-index from body-start below limit
                          when (<= #x40 (char-code (aref string final-index)) #x7E)
                            do (return nil)
                          finally (return t)))))
             ((char= (aref string (1+ index)) #\O)
              (>= (+ index 2) limit))
             (t nil))))))

(defun %paste-marker-event-p (event marker)
  (and (eq :special (key-event-type event)) (eq marker (key-event-code event))))

(defun %make-paste-event (payload)
  (make-key-event :type :paste :code payload :modifiers nil))

(defun %make-paste-buffer ()
  (make-array 0 :element-type 'character :fill-pointer 0 :adjustable t))

(defun %copy-paste-buffer-string (pending-paste)
  (copy-seq pending-paste))

(defun %normalize-paste-line-endings (string)
  "Convert CRLF and lone CR line endings in STRING to LF.
A terminal that sends CR-terminated (or CRLF-terminated) lines inside a
bracketed paste would otherwise leave a raw CR in a collected :PASTE event
payload. When STRING has no CR, return it directly to avoid allocating a
second copy for the usual LF-only paste."
  (let ((first-return (position #\Return string)))
    (if (null first-return)
        string
        (with-output-to-string (out)
          (write-string string out :end first-return)
          (loop with limit = (length string)
                with index = first-return
                while (< index limit)
                for ch = (char string index)
                do (cond
                     ((char= ch #\Return)
                      (write-char #\Newline out)
                      (incf index)
                      (when (and (< index limit)
                                 (char= (char string index) #\Newline))
                        (incf index)))
                     (t
                      (write-char ch out)
                      (incf index))))))))

(defun %assert-decoder-buffer-size (decoder size)
  "Signal when SIZE would exceed DECODER's retained-state bound."
  (when (> size (input-decoder-max-pending decoder))
    (error
      'input-buffer-exceeded
      :limit
      (input-decoder-max-pending decoder)
      :size
      size))
  size)

(defun %decode-next-event (string index)
  (multiple-value-bind (event consumed) (decode-key-sequence string :start index)
    (declare (type (integer 0 *) consumed))
    (values event (if (plusp consumed) consumed 1))))

(declaim (notinline
    %collect-plain-events
    %collect-paste-events
    %decode-string-events-with-paste))

(defun %pending-escape-fragment (string index eof)
  (and
    (not eof)
    (%incomplete-escape-sequence-p string index)
    (subseq string index)))

(defun %decode-plain-events (string eof continuation)
  "Call CONTINUATION with each event STRING decodes, in order.
Returns the still-undecoded pending tail: an incomplete escape fragment held
for a later chunk, or \"\" once STRING is fully consumed. Streaming events to
CONTINUATION rather than building a list here keeps this the one place that
walks STRING; %COLLECT-PLAIN-EVENTS is the list-collecting policy built on
top of it."
  (loop with index = 0
        with limit = (length string)
        do (when (>= index limit)
             (return ""))
           (let ((pending (%pending-escape-fragment string index eof)))
             (when pending
               (return pending)))
           (multiple-value-bind (event consumed) (%decode-next-event string index)
             (funcall continuation event)
             (setf index (+ index consumed)))))

(defun %collect-plain-events (string eof)
  (let* ((events '())
         (pending (%decode-plain-events string eof
                    (lambda (event) (push event events)))))
    (values (nreverse events) pending)))

(defun %append-paste-string (decoder pending-paste chunk &optional (start 0) (end (length chunk)))
  (let* ((old-length (length pending-paste))
         (chunk-length (- end start))
         (new-length (+ old-length chunk-length))
         (capacity (array-dimension pending-paste 0)))
    (%assert-decoder-buffer-size decoder new-length)
    (when (> new-length capacity)
      (let ((new-capacity (if (zerop capacity)
                              new-length
                              (* 2 capacity))))
        (when (< new-capacity new-length)
          (setf new-capacity new-length))
        (setf pending-paste (adjust-array
            pending-paste
            new-capacity
            :fill-pointer
            old-length))))
    (setf (fill-pointer pending-paste) new-length)
    (replace pending-paste chunk :start1 old-length :start2 start :end2 end))
  pending-paste)

(defun %fallback-paste-source (pending-paste suffix)
  (concatenate 'string +bracketed-paste-start-sequence+ pending-paste suffix))

(defun %bracketed-paste-suffix-length (string start eof)
  (if eof
      0
      (let* ((limit (length string))
             (end-sequence-length (length +bracketed-paste-end-sequence+))
             (remaining (- limit start))
             (max-size (if (< remaining (1- end-sequence-length))
                           remaining
                           (1- end-sequence-length))))
        (loop for size fixnum from max-size downto 1
              when (string=
                    string
                    +bracketed-paste-end-sequence+
                    :start1 (- limit size)
                    :start2 0
                    :end2 size)
                do (return size)
              finally (return 0)))))

(defun %flush-pending-paste-events (decoder suffix)
  "Fall back to ordinary decoding of an unterminated paste, clearing the buffer.
Events are returned in input order; callers maintain their own accumulation
order."
  (multiple-value-bind (flushed-events pending-string) (%collect-plain-events
      (%fallback-paste-source (input-decoder-pending-paste decoder) suffix)
      t)
    (declare (ignore pending-string))
    (setf (input-decoder-pending-paste decoder) nil)
    flushed-events))

(defun %decode-paste-events (decoder string eof continuation)
  "Call CONTINUATION with each event STRING decodes while DECODER's paste
buffer may be open, in order. Returns the still-undecoded pending tail, the
same contract %DECODE-PLAIN-EVENTS documents -- %COLLECT-PASTE-EVENTS is the
list-collecting policy built on top of it, the paste-aware sibling of
%COLLECT-PLAIN-EVENTS/%DECODE-PLAIN-EVENTS."
  (let ((index 0)
        (limit (length string))
        (end-sequence-length (length +bracketed-paste-end-sequence+)))
    (declare (type fixnum index limit end-sequence-length))
    (flet ((finish-paste ()
             (let ((text (%copy-paste-buffer-string (input-decoder-pending-paste decoder))))
               (setf (input-decoder-pending-paste decoder) nil)
               (%make-paste-event
                 (if (input-decoder-normalize-paste-line-endings-p decoder)
                     (%normalize-paste-line-endings text)
                     text))))
           (flush-pending-paste (suffix)
             (dolist (event (%flush-pending-paste-events decoder suffix))
               (funcall continuation event))))
      (loop
        (when (>= index limit)
          (when (and eof (input-decoder-pending-paste decoder))
            (flush-pending-paste ""))
          (return ""))
        (if (input-decoder-pending-paste decoder)
            (let ((end-index (search +bracketed-paste-end-sequence+ string :start2 index)))
              (if end-index
                  (progn
                    (when (< index end-index)
                      (setf (input-decoder-pending-paste decoder)
                            (%append-paste-string decoder (input-decoder-pending-paste decoder)
                                                   string index end-index)))
                    (funcall continuation (finish-paste))
                    (setf index (+ end-index end-sequence-length)))
                  (let* ((suffix-length (%bracketed-paste-suffix-length string index eof))
                         (payload-end (- limit suffix-length)))
                    (if eof
                        (progn
                          (flush-pending-paste (subseq string index))
                          (return ""))
                        (progn
                          (when (< index payload-end)
                            (setf (input-decoder-pending-paste decoder)
                                  (%append-paste-string decoder (input-decoder-pending-paste decoder)
                                                         string index payload-end)))
                          (return (subseq string payload-end)))))))
            (let ((pending (%pending-escape-fragment string index eof)))
              (if pending
                  (return pending)
                (multiple-value-bind (event consumed) (%decode-next-event string index)
                  (if (%paste-marker-event-p event :paste-start)
                      (setf (input-decoder-pending-paste decoder) (%make-paste-buffer))
                      (funcall continuation event))
                  (incf index consumed)))))))))

(defun %collect-paste-events (decoder string eof)
  (let* ((events '())
         (pending (%decode-paste-events decoder string eof
                    (lambda (event) (push event events)))))
    (values (nreverse events) pending)))

(defun %decode-string-events-with-paste (decoder string &key eof)
  (%collect-paste-events decoder string eof))
