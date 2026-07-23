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

#-sbcl
(defun pty-resize (pty columns rows)
  (declare (ignore pty columns rows))
  (unsupported :pty))

#+sbcl
(defun pty-alive-p (pty)
  "Return true when PTY's child process is still running.
Returns NIL once the child has exited, or when PTY has no process (for example a
stream-only PTY, or after CLOSE-PTY has cleared it). Use this in a read loop to
tell \"no data yet\" from \"the child exited\"."
  (let ((process (pty-process pty)))
    (and process (sb-ext:process-alive-p process) t)))

#-sbcl
(defun pty-alive-p (pty)
  (declare (ignore pty))
  (unsupported :pty))

#+sbcl
(defun pty-exit-code (pty)
  "Return the integer exit code of PTY's child, or NIL while it is still running
(or when PTY has no process). Read it after PTY-ALIVE-P turns NIL and before
CLOSE-PTY clears the process slot: 0 means the child succeeded, non-zero is its
failure status. This completes the lifecycle -- MAKE-PTY, PTY-ALIVE-P,
PTY-EXIT-CODE, CLOSE-PTY."
  (let ((process (pty-process pty)))
    (and process (sb-ext:process-exit-code process))))

#-sbcl
(defun pty-exit-code (pty)
  (declare (ignore pty))
  (unsupported :pty))

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

;;; --------------------------------------------------------------------------
;;; fd-centric layer
;;;
;;; The accessors and octet I/O below expose the PTY master file descriptor and
;;; byte-transparent read/write on a bare integer fd, so an fd-multiplexing
;;; caller -- for example a terminal multiplexer running its own select(2) loop
;;; over many PTY fds and sockets -- can reuse this PTY layer without going
;;; through the struct/stream character API. They coexist with, and do not
;;; replace, the stream-based PTY-READ / PTY-WRITE above.
;;; --------------------------------------------------------------------------

#+sbcl
(defun pty-fd (pty)
  "Return the integer master-side file descriptor backing PTY's stream.
Signals PTY-OPERATION-FAILED when PTY's stream is closed or exposes no
descriptor. Hand the returned fd to an external select(2)/poll(2) loop or to
FD-READ-OCTETS / FD-WRITE-OCTETS."
  (%with-pty-operation (:fd pty)
    (let* ((stream (%pty-stream-or-error pty))
           (fd (%stream-fd stream)))
      (unless (and (integerp fd) (not (minusp fd)))
        (error "PTY stream has no accessible file descriptor."))
      fd)))

#-sbcl
(defun pty-fd (pty)
  (declare (ignore pty))
  (unsupported :pty))

#+sbcl
(defun pty-pid (pty)
  "Return the integer process id of PTY's child, or NIL when PTY has no process
(for example a stream-only PTY, or after CLOSE-PTY has cleared it)."
  (let ((process (pty-process pty)))
    (and process (sb-ext:process-pid process))))

#-sbcl
(defun pty-pid (pty)
  (declare (ignore pty))
  (unsupported :pty))

#+sbcl
(deftype octet-vector ()
  "A simple, unboxed vector of octets, as required by the bare-fd octet I/O."
  '(simple-array (unsigned-byte 8) (*)))

#+sbcl
(defun %assert-fd (fd)
  (unless (and (integerp fd) (not (minusp fd)))
    (error "File descriptor must be a non-negative integer, got ~S." fd))
  fd)

#+sbcl
(defun %assert-octet-vector (value name)
  (unless (typep value 'octet-vector)
    (error "~A must be a (SIMPLE-ARRAY (UNSIGNED-BYTE 8) (*)), got ~S."
           name value))
  value)

#+sbcl
(defun %fd-would-block-errno-p (errno)
  (and errno
       (or (eql errno sb-unix:eagain)
           (eql errno sb-unix:ewouldblock)
           (eql errno sb-unix:eintr))))

#+sbcl
(defun fd-read-octets (fd buffer &optional limit)
  "Read available bytes from FD into BUFFER, a (SIMPLE-ARRAY (UNSIGNED-BYTE 8)).
Reads at most LIMIT bytes -- defaulting to, and capped at, BUFFER's length --
storing them at the front of BUFFER. Byte-transparent: no character decoding, so
the exact octets are preserved. Returns a positive integer count of bytes read,
0 at end of file (FD's peer closed the other end), or NIL when no data is ready
(a non-blocking FD returned EAGAIN/EWOULDBLOCK, or the call was interrupted by a
signal). A hard OS error is wrapped in PTY-OPERATION-FAILED. This never blocks a
non-blocking FD; on a blocking FD it blocks until data, EOF, or error, so gate
it with select(2)/poll(2)."
  (%with-pty-operation (:fd-read nil)
    (%assert-fd fd)
    (%assert-octet-vector buffer "FD read buffer")
    (let ((count (if (null limit) (length buffer) (min limit (length buffer)))))
      (unless (and (integerp count) (not (minusp count)))
        (error "FD read limit must be a non-negative integer, got ~S." limit))
      (if (zerop count)
          0
          (sb-sys:with-pinned-objects (buffer)
            (multiple-value-bind (result errno)
                (sb-unix:unix-read fd (sb-sys:vector-sap buffer) count)
              (cond
                (result result)
                ((%fd-would-block-errno-p errno) nil)
                (t (error "unix-read on fd ~D failed (errno ~A)." fd errno)))))))))

#-sbcl
(defun fd-read-octets (fd buffer &optional limit)
  (declare (ignore fd buffer limit))
  (unsupported :pty))

#+sbcl
(defun fd-write-octets (fd octets)
  "Write OCTETS, a (SIMPLE-ARRAY (UNSIGNED-BYTE 8)), verbatim to FD.
Byte-transparent: the exact bytes are written with no character encoding.
Returns the integer number of bytes written (0..(LENGTH OCTETS)). Retries EINTR
internally and loops over short writes, so on a blocking FD it writes every byte
and returns (LENGTH OCTETS). On a non-blocking FD it stops as soon as the kernel
buffer is full (EAGAIN/EWOULDBLOCK) and returns a short count; the caller should
send the remaining OCTETS once FD is writable again. A hard OS error is wrapped
in PTY-OPERATION-FAILED."
  (%with-pty-operation (:fd-write nil)
    (%assert-fd fd)
    (%assert-octet-vector octets "FD write octets")
    (let ((len (length octets))
          (offset 0))
      (loop while (< offset len) do
        (multiple-value-bind (result errno)
            (sb-unix:unix-write fd octets offset (- len offset))
          (cond
            (result (incf offset result))
            ((eql errno sb-unix:eintr) nil)
            ((or (eql errno sb-unix:eagain)
                 (eql errno sb-unix:ewouldblock))
             (return))
            (t (error "unix-write on fd ~D failed (errno ~A)." fd errno)))))
      offset)))

#-sbcl
(defun fd-write-octets (fd octets)
  (declare (ignore fd octets))
  (unsupported :pty))
