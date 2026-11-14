(in-package #:cl-tty-kit/test)

#+sb-thread
(defmacro with-monitor-pipe ((reader writer) &body body)
  `(multiple-value-bind (,reader ,writer) (sb-unix:unix-pipe)
     (unwind-protect (progn ,@body)
       (when ,writer (sb-unix:unix-close ,writer))
       (sb-unix:unix-close ,reader))))

#+sb-thread
(defun monitor-test-octets (contents)
  (make-array (length contents) :element-type '(unsigned-byte 8)
              :initial-contents contents))

#+sb-thread
(defun monitor-test-partitioned-input (payload widths)
  (with-monitor-pipe (reader writer)
    (let* ((expected (decode-input-chunk
                      (make-input-decoder :collect-bracketed-paste t) payload))
           (arrived (sb-thread:make-semaphore))
           (events nil))
      (multiple-value-bind (captured values)
          (uiop:symbol-call
            :cl-tty-kit :call-with-input-monitor reader
            (lambda ()
              (flet ((write-chunk (chunk)
                       (fd-write-octets writer chunk)
                       ;; The monitor is the only reader. An empty pipe
                       ;; acknowledges a read boundary before the next write.
                       (loop repeat 1000
                             while (fd-wait reader :input 0)
                             do (sleep 0.001))
                       (when (fd-wait reader :input 0)
                         (error "Input monitor did not read a partition."))))
                (loop with start = 0
                    for width in widths
                    for end = (min (length payload) (+ start width))
                    while (< start (length payload))
                    do (write-chunk (subseq payload start end))
                       (setf start end)
                    finally (when (< start (length payload))
                              (write-chunk (subseq payload start)))))
              (dotimes (i (length expected))
                (unless (sb-thread:wait-on-semaphore arrived :timeout 1)
                  (error "Input monitor did not deliver all events.")))
              :finished)
            (lambda (event)
              (push event events)
              (sb-thread:signal-semaphore arrived)))
        (expect captured :to-equalp payload)
        (expect values :to-equal '(:finished))
        (expect (mapcar #'%key-event-signature (nreverse events))
                :to-equal (mapcar #'%key-event-signature expected))))))

#+sb-thread
(describe "input monitoring"
  (it "runs the body on the caller and returns its multiple values separately"
    (with-monitor-pipe (reader writer)
      (let ((owner sb-thread:*current-thread*)
            (finished nil))
        (multiple-value-bind (octets body-values)
            (uiop:symbol-call
              :cl-tty-kit :call-with-input-monitor reader
              (lambda ()
                (expect sb-thread:*current-thread* :to-be owner)
                (values 42 :answer))
              (lambda (event) (declare (ignore event)))
              :on-finish (lambda (captured)
                           (setf finished captured)))
          (expect octets :to-equalp #())
          (expect finished :to-be octets)
          (expect body-values :to-equal '(42 :answer))))))
  (it "decodes legacy and CSI-u C-g while keeping paste contents together"
    (monitor-test-partitioned-input
      (monitor-test-octets
        '(7 27 91 49 48 51 59 53 117 27 91 50 48 48 126
          97 7 98 27 91 50 48 49 126 226 156 147))
      (make-list 30 :initial-element 1)))
  (it "joins before cleanup on a normal return and preserves every read byte"
    (with-monitor-pipe (reader writer)
      (let ((arrived (sb-thread:make-semaphore))
            (worker nil)
            (finished nil))
        (fd-write-octets writer (monitor-test-octets '(97 98 99)))
        (let ((octets
                (uiop:symbol-call
                  :cl-tty-kit :call-with-input-monitor reader
                  (lambda ()
                    (expect (sb-thread:wait-on-semaphore arrived :n 3 :timeout 1)))
                  (lambda (event)
                    (declare (ignore event))
                    (setf worker sb-thread:*current-thread*)
                    (sb-thread:signal-semaphore arrived))
                  :on-finish (lambda (captured)
                               (expect (sb-thread:thread-alive-p worker) :to-be nil)
                               (setf finished captured)))))
          (expect octets :to-equalp #(97 98 99))
          (expect finished :to-be octets)))))
  (it "joins and delivers raw input during a nonlocal exit from the body"
    (with-monitor-pipe (reader writer)
      (let ((arrived (sb-thread:make-semaphore))
            (worker nil)
            (finished nil))
        (fd-write-octets writer (monitor-test-octets '(7)))
        (expect
          (catch 'monitor-exit
            (uiop:symbol-call
              :cl-tty-kit :call-with-input-monitor reader
              (lambda ()
                (expect (sb-thread:wait-on-semaphore arrived :timeout 1))
                (throw 'monitor-exit :interrupted))
              (lambda (event)
                (declare (ignore event))
                (setf worker sb-thread:*current-thread*)
                (sb-thread:signal-semaphore arrived))
              :on-finish (lambda (captured)
                           (expect (sb-thread:thread-alive-p worker) :to-be nil)
                           (setf finished captured))))
          :to-be :interrupted)
        (expect finished :to-equalp #(7)))))
  (it "does not turn an unfinished paste into an interrupt during cleanup"
    (with-monitor-pipe (reader writer)
      (let ((events nil)
            (payload (monitor-test-octets '(27 91 50 48 48 126 7))))
        (fd-write-octets writer payload)
        (let ((captured
                (uiop:symbol-call
                  :cl-tty-kit :call-with-input-monitor reader
                  (lambda ()
                    (loop repeat 1000
                          while (fd-wait reader :input 0)
                          do (sleep 0.001))
                    (expect (fd-wait reader :input 0) :to-be nil))
                  (lambda (event) (push event events)))))
          (expect captured :to-equalp payload)
          (expect events :to-be nil)))))
  (it "reports a callback diagnostic without replacing successful body values"
    (with-monitor-pipe (reader writer)
      (let ((arrived (sb-thread:make-semaphore))
            (finished nil))
        (fd-write-octets writer (monitor-test-octets '(97)))
        (multiple-value-bind (captured body-values diagnostics)
            (uiop:symbol-call
              :cl-tty-kit :call-with-input-monitor reader
              (lambda ()
                (sb-thread:wait-on-semaphore arrived :timeout 1)
                (values 42 :answer))
              (lambda (event)
                (declare (ignore event))
                (sb-thread:signal-semaphore arrived)
                (error "Monitor callback failed."))
              :on-finish (lambda (bytes) (setf finished bytes)))
          (expect captured :to-equalp #(97))
          (expect finished :to-be captured)
          (expect body-values :to-equal '(42 :answer))
          (expect (mapcar #'first diagnostics) :to-equal '(:on-event))
          (expect (typep (second (first diagnostics)) 'simple-error))))))
  (it "keeps a body nonlocal exit when the helper also fails"
    (with-monitor-pipe (reader writer)
      (let ((arrived (sb-thread:make-semaphore)))
        (fd-write-octets writer (monitor-test-octets '(97)))
        (expect
          (catch 'monitor-exit
            (uiop:symbol-call
              :cl-tty-kit :call-with-input-monitor reader
              (lambda ()
                (sb-thread:wait-on-semaphore arrived :timeout 1)
                (throw 'monitor-exit :body-exit))
              (lambda (event)
                (declare (ignore event))
                (sb-thread:signal-semaphore arrived)
                (error "Monitor callback failed."))))
          :to-be :body-exit))))
  (it "joins after an asynchronous body exit requested by the helper"
    (with-monitor-pipe (reader writer)
      (let ((owner sb-thread:*current-thread*)
            (worker nil)
            (finished nil))
        (fd-write-octets writer (monitor-test-octets '(7)))
        (expect
          (catch 'monitor-async-exit
            (uiop:symbol-call
              :cl-tty-kit :call-with-input-monitor reader
              (lambda ()
                (loop (ignore-errors (sleep 0.001))))
              (lambda (event)
                (declare (ignore event))
                (setf worker sb-thread:*current-thread*)
                (sb-thread:interrupt-thread
                  owner (lambda () (throw 'monitor-async-exit :interrupted))))
              :on-finish (lambda (captured) (setf finished captured))))
          :to-be :interrupted)
        (expect finished :to-equalp #(7))
        (expect (sb-thread:thread-alive-p worker) :to-be nil))))
  (it "stops and joins every idle and streaming sample within 50ms"
    (dolist (streaming '(nil t))
      (dolist (nonlocal '(nil t))
        (let ((samples (monitor-test-cleanup-samples streaming nonlocal)))
          (expect (length samples) :to-be 20)
          (expect (< (reduce #'max samples) 0.05)))))))
