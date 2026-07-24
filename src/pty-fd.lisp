(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; fd-centric layer
;;;
;;; The accessors and octet I/O below expose the PTY master file descriptor and
;;; byte-transparent read/write on a bare integer fd, so an fd-multiplexing
;;; caller -- for example a terminal multiplexer running its own select(2) loop
;;; over many PTY fds and sockets -- can reuse this PTY layer without going
;;; through the struct/stream character API. They coexist with, and do not
;;; replace, the stream-based PTY-READ / PTY-WRITE in pty.lisp.
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
