(in-package #:cl-tty-kit/test)

#+sb-thread
(defun monitor-test-read-race-trace (payload delay)
  (let ((read-original (fdefinition 'fd-read-octets))
        (join-original (fdefinition 'cl-concurrent-kit:join-thread))
        (read-held (sb-thread:make-semaphore))
        (return-gate (sb-thread:make-semaphore))
        (phase nil)
        (race-observed nil))
    (unwind-protect
         (progn
           (sb-sys:without-interrupts
             (setf (fdefinition 'fd-read-octets)
                   (lambda (&rest arguments)
                     (let ((count (apply read-original arguments)))
                       (when (and (null phase) count (plusp count)
                                  (equal (sb-thread:thread-name sb-thread:*current-thread*)
                                         "cl-tty-kit input monitor"))
                         ;; The real read has consumed bytes, but the monitor
                         ;; has not received its result or captured the chunk.
                         (setf phase :awaiting-return)
                         (sb-thread:signal-semaphore read-held)
                         (unwind-protect
                              (progn
                                (unless (sb-thread:wait-on-semaphore return-gate :timeout 1)
                                  (error "Read result was not released."))
                                (setf phase :returned))
                           (when (eq phase :awaiting-return)
                             (setf phase :aborted))))
                       count))
                   (fdefinition 'cl-concurrent-kit:join-thread)
                   (lambda (thread &rest options)
                     (when (equal (cl-concurrent-kit:thread-name thread)
                                  "cl-tty-kit input monitor")
                       ;; The production cleanup publishes stop before joining.
                       (when (eq phase :awaiting-return)
                         (setf race-observed t))
                       (sb-thread:signal-semaphore return-gate))
                     (apply join-original thread options))))
           (multiple-value-bind (captured remaining body-values diagnostics)
               (monitor-test-streaming-trace
                 payload delay
                 :read-ack (lambda ()
                             (unless (sb-thread:wait-on-semaphore read-held :timeout 1)
                               (error "No in-flight read result was observed."))))
             (values captured remaining body-values diagnostics race-observed)))
      (sb-thread:signal-semaphore return-gate)
      (sb-sys:without-interrupts
        (setf (fdefinition 'fd-read-octets) read-original
              (fdefinition 'cl-concurrent-kit:join-thread) join-original)))))

#+sb-thread
(describe "input monitor v190 contracts"
  (it "retains the completed read when stop arrives before read-result return"
    (let ((payload (make-array 8193 :element-type '(unsigned-byte 8) :initial-element 97)))
      (multiple-value-bind (captured remaining body-values diagnostics race-observed)
          (monitor-test-read-race-trace payload 0.003)
        (format t "~&controlled read race observed=~S captured=~D remaining=~D payload=~D~%"
                race-observed (length captured) (length remaining) (length payload))
        (expect race-observed)
        (expect (concatenate '(vector (unsigned-byte 8)) captured remaining)
                :to-equalp payload)
        (expect body-values :to-equal '(:body-complete))
        (expect (<= (length diagnostics) 1)))))
  (it "requests no more than 20ms for each real helper fd-wait"
    (let ((original (fdefinition 'fd-wait))
          (entered (sb-thread:make-semaphore))
          (timeouts nil))
      (unwind-protect
           (progn
             (sb-sys:without-interrupts
               (setf (fdefinition 'fd-wait)
                     (lambda (fd direction &optional timeout)
                       (when (equal (sb-thread:thread-name sb-thread:*current-thread*)
                                    "cl-tty-kit input monitor")
                         (push timeout timeouts)
                         (sb-thread:signal-semaphore entered))
                       (funcall original fd direction timeout))))
             (with-monitor-pipe (reader writer)
               (call-with-input-monitor
                 reader
                 (lambda ()
                   (unless (sb-thread:wait-on-semaphore entered :timeout 1)
                     (error "The helper did not enter fd-wait.")))
                 (lambda (event) (declare (ignore event)) nil))))
        (sb-sys:without-interrupts
          (setf (fdefinition 'fd-wait) original)))
      (expect (plusp (length timeouts)))
      (expect (every (lambda (timeout) (and (realp timeout) (<= timeout 0.020))) timeouts))))
  (it "consumes parameterized paste using its complete source framing"
    (with-monitor-pipe (reader writer)
      (let* ((done (sb-thread:make-semaphore))
             (source (concatenate 'string "a" (%esc "[200;5~hello")
                                  (%esc "[201~") "z"))
             (octets (cl-codec-kit:string-to-octets source :encoding :utf-8)))
        (multiple-value-bind (captured values diagnostics)
            (call-with-input-monitor
              reader
              (lambda ()
                (fd-write-octets writer octets)
                (unless (sb-thread:wait-on-semaphore done :timeout 1)
                  (error "Trailing key was not observed.")))
              (lambda (event)
                (cond ((eq (key-event-type event) :paste) :consume)
                      ((eql (key-event-code event) #\z)
                       (sb-thread:signal-semaphore done)
                       nil))))
          (declare (ignore values))
          (expect captured :to-equalp #(97 122))
          (expect diagnostics :to-be nil)))))
  (it "returns the exact inherited parameterized paste prefix for one replay"
    (with-monitor-pipe (reader writer)
      (let* ((decoder (make-input-decoder :collect-bracketed-paste t))
             (prefix (%esc "[200;5~a")))
        (decode-input-chunk decoder prefix)
        (multiple-value-bind (captured values diagnostics)
            (call-with-input-monitor reader (lambda () nil)
                                     (lambda (event) (declare (ignore event)) nil)
                                     :decoder decoder)
          (declare (ignore values))
          (expect captured :to-equalp (cl-codec-kit:string-to-octets prefix :encoding :utf-8))
          (expect diagnostics :to-be nil)
          (expect (decode-input-chunk decoder captured) :to-be nil)
          (expect (mapcar #'%key-event-signature (decode-input-chunk decoder (%esc "[201~")))
                  :to-equal '((:paste "a" nil)))))))
  (it "keeps parameterized paste source when EOF uses ordinary fallback"
    (let* ((decoder (make-input-decoder :collect-bracketed-paste t))
           (source (%esc "[200;5~a")))
      (decode-input-chunk decoder source)
      (let ((lengths nil)
            (expected (mapcar #'%key-event-signature (decode-input source))))
        (let ((cl-tty-kit::*input-decoder-source-length-sink*
                (lambda (length) (push length lengths))))
          (expect (mapcar #'%key-event-signature (flush-input-decoder decoder))
                  :to-equal expected))
        (expect (reduce #'+ lengths) :to-be
                (length (cl-codec-kit:string-to-octets source :encoding :utf-8)))))))
