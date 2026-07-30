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

(defun %list-of-strings-p (value)
  (and (listp value)
       (every #'stringp value)))

(defun %validate-pty-spawn-arguments (program args environment directory)
  (unless (stringp program)
    (error "PTY program must be a string, got ~S." program))
  (unless (%list-of-strings-p args)
    (error "PTY args must be a list of strings, got ~S." args))
  (unless (or (null environment)
              (%list-of-strings-p environment))
    (error "PTY environment must be NIL or a list of strings, got ~S."
           environment))
  (unless (or (null directory)
              (stringp directory)
              (pathnamep directory))
    (error "PTY directory must be NIL, a string, or a pathname, got ~S."
           directory)))

(defun %validate-pty-read-limit (limit)
  (unless (and (integerp limit) (<= 0 limit))
    (error "PTY read limit must be a non-negative integer, got ~S." limit)))

(defun %validate-pty-size (columns rows)
  (unless (and (integerp columns) (plusp columns))
    (error "PTY columns must be a positive integer, got ~S." columns))
  (unless (and (integerp rows) (plusp rows))
    (error "PTY rows must be a positive integer, got ~S." rows)))

(defun %valid-pty-write-octets-p (data)
  (and (vectorp data)
       (every (lambda (octet)
                (typep octet '(unsigned-byte 8)))
              data)))

(defun %validate-pty-write-data (data)
  (unless (or (stringp data)
              (%valid-pty-write-octets-p data))
    (error "PTY write data must be a string or a vector of octets, got ~S."
           data)))

#+sbcl
(defun make-pty (&key (program "/bin/sh") args environment directory)
  "Spawn PROGRAM under a PTY on SBCL, returning a PTY object."
  (handler-case
      (progn
        (%validate-pty-spawn-arguments program args environment directory)
        (let* ((process (%run-program-with-pty-retry program args
                                                   environment
                                                   directory))
               (stream (sb-ext:process-pty process)))
          (%make-pty :process process :stream stream)))
    (error (condition)
      (%signal-pty-operation-failed :spawn nil condition))))

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
    (%validate-pty-write-data data)
    (let ((stream (%pty-stream-or-error pty)))
      (typecase data
        (string (write-string data stream))
        (vector (write-string (%utf8-octets-to-string data) stream)))
      (finish-output stream)
      pty)))

(defun pty-read (pty &optional (limit 4096))
  "Read up to LIMIT characters from PTY, returning a string when data is available or NIL."
  (%with-pty-operation (:read pty)
    (%validate-pty-read-limit limit)
    (let ((stream (%pty-stream-or-error pty)))
      (let ((output (with-output-to-string (out)
                      (loop repeat limit
                            for ch = (read-char-no-hang stream nil nil)
                            while ch do (write-char ch out)))))
        (unless (string-empty-p output)
          output)))))

#+sbcl
(defun pty-resize (pty columns rows)
  "Set PTY's window size to COLUMNS by ROWS, returning PTY.
Sends TIOCSWINSZ on the PTY's file descriptor, which is how a terminal tells a
child process its window changed (the child normally receives SIGWINCH). Signals
PTY-OPERATION-FAILED when the size cannot be set -- for example on a platform
  whose ioctl constant is unknown or a stream without an accessible descriptor."
  (%with-pty-operation (:resize pty)
    (%validate-pty-size columns rows)
    (let* ((stream (%pty-stream-or-error pty))
           (fd (%stream-fd stream)))
      (unless (and fd (%set-terminal-size fd columns rows))
        (error "Could not set the PTY window size."))
      pty)))

#+sbcl
(defun pty-alive-p (pty)
  "Return true when PTY's child process is still running.
Returns NIL once the child has exited, or when PTY has no process (for example a
stream-only PTY, or after CLOSE-PTY has cleared it). Use this in a read loop to
tell \"no data yet\" from \"the child exited\"."
  (let ((process (pty-process pty)))
    (and process (sb-ext:process-alive-p process) t)))

#+sbcl
(defun pty-exit-code (pty)
  "Return the integer exit code of PTY's child, or NIL while it is still running
(or when PTY has no process). Read it after PTY-ALIVE-P turns NIL and before
CLOSE-PTY clears the process slot: 0 means the child succeeded, non-zero is its
failure status. This completes the lifecycle -- MAKE-PTY, PTY-ALIVE-P,
PTY-EXIT-CODE, CLOSE-PTY."
  (let ((process (pty-process pty)))
    (and process (sb-ext:process-exit-code process))))

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
