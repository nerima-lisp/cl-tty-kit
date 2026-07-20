(in-package #:cl-tty-kit/test)

#+sbcl
(defun read-pty-until (pty predicate &key (attempts 50) (sleep-seconds 0.01))
  (let ((chunks '()))
    (loop repeat attempts
          for chunk = (pty-read pty)
          do (when chunk
               (push chunk chunks)
               (let ((output (apply #'concatenate 'string (nreverse chunks))))
                 (when (funcall predicate output)
                   (return output))))
             (sleep sleep-seconds)
          finally (return (and chunks
                               (apply #'concatenate 'string (nreverse chunks)))))))

#+sbcl
(defmacro with-function-overrides ((&rest bindings) &body body)
  (let ((saved-bindings
          (loop for (name replacement) in bindings
                collect (list (gensym "FUNCTION-")
                              name
                              replacement))))
    `(let ,(loop for (saved name replacement) in saved-bindings
                 collect `(,saved (symbol-function ',name)))
       (unwind-protect
            (progn
              (sb-ext:without-package-locks
                ,@(loop for (_ name replacement) in saved-bindings
                        collect `(setf (symbol-function ',name) ,replacement)))
              ,@body)
         (sb-ext:without-package-locks
           ,@(loop for (saved name ignore) in saved-bindings
                   collect `(setf (symbol-function ',name) ,saved)))))))

#+sbcl
(defun %assert-pty-operation-failed (condition operation pty message)
  (is (eq operation (pty-operation-failed-operation condition)))
  (is (eq pty (pty-operation-failed-pty condition)))
  (is (search message (format nil "~A" condition))))

#+sbcl
(defmacro signals-pty-operation-failed ((operation pty message) &body body)
  `(signals (pty-operation-failed condition)
     (progn ,@body)
     (%assert-pty-operation-failed condition ,operation ,pty ,message)))

#+sbcl
(defmacro signals-simple-error-containing (message &body body)
  `(signals (simple-error condition)
     (progn ,@body)
     (is (search ,message (format nil "~A" condition)))))

#+sbcl
(defun test-pty ()
  (is (null (cl-tty-kit::%transient-spawn-failure-p
             (make-condition 'simple-error
                             :format-control "permanent failure"
                             :format-arguments nil))))
  (is (cl-tty-kit::%transient-spawn-failure-p
       (make-condition 'simple-error
                       :format-control "Resource temporarily unavailable"
                       :format-arguments nil)))
  (let ((attempt-count 0))
    (with-function-overrides
        ((sb-ext:run-program
           (lambda (&rest args)
             (declare (ignore args))
             (incf attempt-count)
             (error "Resource temporarily unavailable")))
         (sleep
           (lambda (&rest args)
             (declare (ignore args))
             nil)))
      (signals-simple-error-containing
          "Resource temporarily unavailable"
        (cl-tty-kit::%run-program-with-pty-retry "/bin/sh" nil nil nil
                                                 :attempts 3
                                                 :sleep-seconds 0))
      (is (= 3 attempt-count))))
  (let ((attempt-count 0))
    (with-function-overrides
        ((sb-ext:run-program
           (lambda (&rest args)
             (declare (ignore args))
             (incf attempt-count)
             :process))
         (sleep
           (lambda (&rest args)
             (declare (ignore args))
             nil)))
      (is (eq :process
              (cl-tty-kit::%run-program-with-pty-retry "/bin/sh" nil nil nil
                                                       :attempts 3
                                                       :sleep-seconds 0)))
      (is (= 1 attempt-count))))
  (signals-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
      (make-pty :program :not-a-program))
  (signals-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
      (make-pty :program "/bin/sh" :args '("-c" :not-a-string)))
  (signals-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
      (make-pty :program "/bin/sh" :environment '(:not-a-string)))
  (signals-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
      (make-pty :program "/bin/sh" :directory :not-a-directory))
  (let ((alive-count 0))
    (with-function-overrides
        ((sb-ext:process-alive-p
           (lambda (process)
             (declare (ignore process))
             (incf alive-count)
             t))
         (sleep
           (lambda (&rest args)
             (declare (ignore args))
             nil)))
      (is (null (cl-tty-kit::%wait-for-process-exit :process
                                                    :attempts 2
                                                    :sleep-seconds 0)))
      (is (= 3 alive-count))))
  (let ((kill-signals '())
        (closed nil))
    (with-function-overrides
        ((close
           (lambda (stream &key abort)
             (declare (ignore stream abort))
             (setf closed t)))
         (cl-tty-kit::%wait-for-process-exit
           (lambda (process &key attempts sleep-seconds)
             (declare (ignore process attempts sleep-seconds))
             nil))
         (sb-ext:process-kill
           (lambda (process signal mode)
             (declare (ignore process mode))
             (push signal kill-signals)))
         (sb-ext:process-close
           (lambda (process)
             (declare (ignore process))
             :closed)))
      (signals-simple-error-containing
          "did not exit during shutdown"
        (cl-tty-kit::%close-pty-process :process :stream)))
    (is closed)
    (is (equal '(9 15) kill-signals)))
  (signals-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
      (make-pty :program "/definitely/missing"))
  (let* ((input (make-string-input-stream "abc"))
         (read-pty (cl-tty-kit::%make-pty :process nil :stream input)))
    (is (null (pty-process read-pty)))
    (is (eq input (pty-stream read-pty)))
    (is (string= "abc" (pty-read read-pty)))
    (is (null (pty-read read-pty)))
    (signals-pty-operation-failed (:read read-pty "PTY operation READ failed")
      (pty-read read-pty -1))
    (signals-pty-operation-failed (:read read-pty "PTY operation READ failed")
      (pty-read read-pty 1.5))
    (close-pty read-pty))
  (let* ((closed-input (make-string-input-stream "abc"))
         (read-pty (cl-tty-kit::%make-pty :process nil :stream closed-input)))
    (close closed-input)
    (signals-pty-operation-failed (:read read-pty "PTY operation READ failed")
      (pty-read read-pty)))
  (let ((pty (cl-tty-kit::%make-pty :process t :stream (make-string-input-stream ""))))
    (with-function-overrides
        ((cl-tty-kit::%close-pty-process
           (lambda (&rest args)
             (declare (ignore args))
             (error "close failed"))))
      (signals-pty-operation-failed (:close pty "PTY operation CLOSE failed")
        (close-pty pty))))
  (let* ((pty (make-pty :program "/bin/sh"))
         (process (pty-process pty)))
    (is (pty-process pty))
    (is (streamp (pty-stream pty)))
    (is (eq pty (close-pty pty)))
    (is (not (sb-ext:process-alive-p process)))
    (is (null (pty-process pty)))
    (is (null (pty-stream pty)))
    (is (eq pty (close-pty pty)))
    (is (null (pty-process pty)))
    (is (null (pty-stream pty))))
  (let* ((stream (make-string-input-stream "abc"))
         (pty (cl-tty-kit::%make-pty :process nil :stream stream)))
    (is (eq pty (close-pty pty)))
    (is (null (pty-process pty)))
    (is (null (pty-stream pty))))
  (let* ((output (make-string-output-stream))
         (write-pty (cl-tty-kit::%make-pty :process nil :stream output)))
    (is (null (pty-process write-pty)))
    (is (eq output (pty-stream write-pty)))
    (is (eq write-pty (pty-write write-pty "hi")))
    (is (string= "hi" (get-output-stream-string output)))
    (signals-pty-operation-failed (:write write-pty "PTY operation WRITE failed")
      (pty-write write-pty :bad))
    (signals-pty-operation-failed (:write write-pty "PTY operation WRITE failed")
      (pty-write write-pty #(104 :bad)))
    (let* ((vector-output (make-string-output-stream))
           (vector-pty (cl-tty-kit::%make-pty :process nil
                                              :stream vector-output)))
      (is (null (pty-process vector-pty)))
      (is (eq vector-output (pty-stream vector-pty)))
      (is (eq vector-pty (pty-write vector-pty #(104 105))))
      (is (string= "hi" (get-output-stream-string vector-output)))
      (let* ((utf8-output (make-string-output-stream))
             (utf8-pty (cl-tty-kit::%make-pty :process nil
                                              :stream utf8-output)))
        (is (eq utf8-pty (pty-write utf8-pty #(227 129 130))))
        (is (string= "あ" (get-output-stream-string utf8-output)))
        (close-pty utf8-pty))
      (let* ((invalid-output (make-string-output-stream))
             (invalid-pty (cl-tty-kit::%make-pty :process nil
                                                 :stream invalid-output)))
        (signals (pty-operation-failed condition)
            (pty-write invalid-pty #(255))
          (is (eq :write (pty-operation-failed-operation condition)))
          (is (eq invalid-pty (pty-operation-failed-pty condition)))
          (let ((reason (pty-operation-failed-reason condition)))
            (is (typep reason 'invalid-utf8-sequence))
            (is (= 0 (invalid-utf8-sequence-position reason)))
            (is (eq :invalid-leading-byte
                    (invalid-utf8-sequence-reason reason)))))
        (close-pty invalid-pty))
      (let* ((closed-output (make-string-output-stream))
             (closed-pty (cl-tty-kit::%make-pty :process nil
                                                :stream closed-output)))
        (close closed-output)
        (signals-pty-operation-failed (:write closed-pty "PTY operation WRITE failed")
          (pty-write closed-pty "x")))
      (close-pty vector-pty))
    (close-pty write-pty))
  (let ((pty (make-pty :program "/bin/sh"
                       :args '("-c" "printf hello; sleep 0.05"))))
    (is (pty-process pty))
    (is (streamp (pty-stream pty)))
    (let ((output (read-pty-until pty
                                  (lambda (output)
                                    (search "hello" output)))))
      (is (search "hello" output)))
    (close-pty pty))
  ;; PTY-RESIZE sets the window size, verifiable by reading it back via ioctl.
  (let ((pty (make-pty :program "/bin/sh")))
    (is (eq pty (pty-resize pty 111 37)))
    (let ((fd (cl-tty-kit::%stream-fd (pty-stream pty))))
      (when fd
        (multiple-value-bind (columns rows) (terminal-size fd)
          (is (eql 111 columns))
          (is (eql 37 rows)))))
    (close-pty pty))
  ;; A stream without a file descriptor signals a structured resize failure.
  (let ((pty (cl-tty-kit::%make-pty :process nil
                                    :stream (make-string-output-stream))))
    (signals-pty-operation-failed (:resize pty "PTY operation RESIZE failed")
      (pty-resize pty 80 24)))
  ;; PTY-ALIVE-P tracks the child's lifetime.
  (let ((pty (make-pty :program "/bin/sh")))
    (is (pty-alive-p pty))
    (close-pty pty)
    (is (not (pty-alive-p pty))))
  ;; A stream-only PTY (no process) is never alive.
  (is (not (pty-alive-p (cl-tty-kit::%make-pty :process nil
                                              :stream (make-string-input-stream "")))))
  ;; PTY-EXIT-CODE reports the child's status once it has finished.
  (let ((pty (make-pty :program "/bin/sh" :args '("-c" "exit 3"))))
    (loop repeat 200 while (pty-alive-p pty) do (sleep 0.01))
    (is (eql 3 (pty-exit-code pty)))
    (close-pty pty))
  (let ((pty (make-pty :program "/bin/sh" :args '("-c" "exit 0"))))
    (loop repeat 200 while (pty-alive-p pty) do (sleep 0.01))
    (is (eql 0 (pty-exit-code pty)))
    (close-pty pty))
  ;; No process -> no exit code.
  (is (null (pty-exit-code (cl-tty-kit::%make-pty :process nil
                                                 :stream (make-string-input-stream "")))))
  t)

#-sbcl
(defun test-pty ()
  (handler-case
      (progn
        (make-pty)
        (is nil))
    (unsupported-feature (condition)
      (is (eq :pty (unsupported-feature-feature condition)))))
  (handler-case
      (progn
        (close-pty (cl-tty-kit::%make-pty :process nil :stream (make-string-input-stream "")))
        (is nil))
    (unsupported-feature (condition)
      (is (eq :pty (unsupported-feature-feature condition)))))
  t)
