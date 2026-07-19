(in-package #:cl-tty-kit)

(defstruct (pty (:constructor %make-pty))
  "A spawned PTY process and its connected stream."
  process
  stream)

(setf (documentation 'pty-process 'function)
      "Return the process object associated with PTY.")

(setf (documentation 'pty-stream 'function)
      "Return the stream connected to PTY.")

#+sbcl
(defun %transient-spawn-failure-p (condition)
  (search "resource temporarily unavailable"
          (string-downcase (format nil "~A" condition))))

#+sbcl
(defun %run-program-with-pty-retry (program args environment directory
                                    &key (attempts 5) (sleep-seconds 0.05))
  (loop repeat attempts
        for condition = nil
        do (handler-case
               (return (sb-ext:run-program program args
                                           :search t
                                           :wait nil
                                           :pty t
                                           :environment environment
                                           :directory directory))
             (error (caught)
               (setf condition caught)
               (unless (%transient-spawn-failure-p caught)
                 (error caught))))
           (sleep sleep-seconds)
        finally (error condition)))

#+sbcl
(defun make-pty (&key (program "/bin/sh") args environment directory)
  "Spawn PROGRAM under a PTY on SBCL, returning a PTY object."
  (handler-case
      (let* ((process (%run-program-with-pty-retry program args
                                                   environment
                                                   directory))
             (stream (sb-ext:process-pty process)))
        (%make-pty :process process :stream stream))
    (error (condition)
      (%signal-pty-operation-failed :spawn nil condition))))

#-sbcl
(defun make-pty (&key (program "/bin/sh") args environment directory)
  (declare (ignore program args environment directory))
  (unsupported :pty))

(defmacro %with-pty-operation ((operation pty) &body body)
  `(handler-case
       (progn ,@body)
     (error (condition)
       (%signal-pty-operation-failed ,operation ,pty condition))))

(defun %pty-stream-or-error (pty)
  (or (pty-stream pty)
      (error "PTY stream is closed.")))

(defun pty-write (pty data)
  "Write DATA to PTY and return PTY."
  (%with-pty-operation (:write pty)
    (let ((stream (%pty-stream-or-error pty)))
      (etypecase data
        (string (write-string data stream))
        (vector (write-string (%utf8-octets-to-string data) stream)))
      (finish-output stream)
      pty)))

(defun pty-read (pty &optional (limit 4096))
  "Read up to LIMIT characters from PTY, returning a string when data is available or NIL."
  (%with-pty-operation (:read pty)
    (let ((stream (%pty-stream-or-error pty)))
      (let ((output (with-output-to-string (out)
                      (loop repeat limit
                            for ch = (read-char-no-hang stream nil nil)
                            while ch do (write-char ch out)))))
        (unless (string-empty-p output)
          output)))))

#+sbcl
(defun %wait-for-process-exit (process &key (attempts 20) (sleep-seconds 0.01))
  (loop repeat attempts
        until (not (sb-ext:process-alive-p process))
        do (sleep sleep-seconds)
        finally (return (not (sb-ext:process-alive-p process)))))

#+sbcl
(defun %terminate-pty-process (process signals)
  (dolist (signal signals nil)
    (sb-ext:process-kill process signal :pid)
    (when (%wait-for-process-exit process)
      (return t))))

#+sbcl
(defun %close-pty-process (process stream)
  (when stream
    (close stream :abort t))
  (unless (%wait-for-process-exit process)
    (unless (%terminate-pty-process process '(15 9))
      (error "PTY process did not exit during shutdown")))
  (sb-ext:process-close process))

(defun %signal-pty-operation-failed (operation pty condition)
  (error 'pty-operation-failed
         :operation operation
         :pty pty
         :reason condition))

#+sbcl
(defun close-pty (pty)
  "Attempt PTY shutdown and signal structured failures.
Signals `unsupported-feature` for :PTY on non-SBCL implementations.
PTY's process and stream slots are cleared even when shutdown signals
PTY-OPERATION-FAILED, since by that point the stream is already closed at
the OS level; leaving the slots populated would let a caller re-close an
already-closed stream or retry against a process shutdown already gave up
on."
  (let ((process (pty-process pty))
        (stream (pty-stream pty)))
    (when (or process stream)
      (unwind-protect
          (%with-pty-operation (:close pty)
            (if process
                (%close-pty-process process stream)
                (close stream :abort t)))
        (setf (pty-process pty) nil
              (pty-stream pty) nil))))
  pty)

#-sbcl
(defun close-pty (pty)
  (declare (ignore pty))
  (unsupported :pty))
