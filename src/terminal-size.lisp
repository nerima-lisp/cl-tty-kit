#+sbcl
(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Runtime terminal window size (SBCL, Linux/Darwin)
;;;
;;; Queries ioctl(TIOCGWINSZ) via SB-UNIX:UNIX-IOCTL. The request constant differs
;;; by platform; on anything else, or off a real terminal, TERMINAL-SIZE reports
;;; the size as unavailable (NIL) rather than signaling, so callers can fall back
;;; to a default (e.g. 80x24) or a cursor-position probe.
;;;
;;; SET-TERMINAL-SIZE is the write direction, ioctl(TIOCSWINSZ). It signals
;;; TERMINAL-SIZE-SET-FAILED instead of reporting NIL, because the two directions
;;; are asymmetric: a missing size has a sensible fallback, whereas a size that
;;; was never applied leaves the child process believing a window it does not
;;; have, and no fallback repairs that.
;;;
;;; SB-UNIX:UNIX-IOCTL (rather than a hand-rolled DEFINE-ALIEN-ROUTINE) is used
;;; deliberately: ioctl is variadic, and on the arm64 ABI variadic arguments pass
;;; on the stack while a fixed-prototype alien call passes them in registers,
;;; producing EFAULT. SBCL's own ioctl wrapper marshals the pointer correctly.
;;; --------------------------------------------------------------------------

#+sbcl
(sb-alien:define-alien-type nil
  (sb-alien:struct %winsize
                   (rows sb-alien:unsigned-short)
                   (columns sb-alien:unsigned-short)
                   (x-pixels sb-alien:unsigned-short)
                   (y-pixels sb-alien:unsigned-short)))

#+sbcl
(defparameter +tiocgwinsz+
  #+darwin #x40087468
  #+linux #x5413
  #-(or darwin linux) nil
  "The ioctl request number for TIOCGWINSZ on the host platform, or NIL when the
platform is not one this file knows the constant for.")

#+sbcl
(defparameter +tiocswinsz+
  #+darwin #x80087467
  #+linux #x5414
  #-(or darwin linux) nil
  "The ioctl request number for TIOCSWINSZ (set window size) on the host
platform, or NIL when unknown.")

#+sbcl
(define-validating-assert %assert-terminal-fd (fd)
  (and (integerp fd) (not (minusp fd)))
  "Terminal FD must be a non-negative integer, got ~S." fd)

#+sbcl
(defun terminal-size (&optional (fd 0))
  "Return the terminal window size on FD as (VALUES COLUMNS ROWS).
Returns (VALUES NIL NIL) when FD is not a terminal, the ioctl fails, the report
is zero-sized, or the platform's TIOCGWINSZ constant is unknown -- so a caller
should treat NIL as \"size unavailable\" and fall back to a default. FD defaults
to standard input (0)."
  (setf fd (%assert-terminal-fd fd))
  (if (null +tiocgwinsz+)
      (values nil nil)
      (handler-case
          (sb-alien:with-alien ((winsize (sb-alien:struct %winsize)))
            (if (and (sb-unix:unix-ioctl fd +tiocgwinsz+
                                         (sb-alien:alien-sap (sb-alien:addr winsize)))
                     (plusp (sb-alien:slot winsize 'columns))
                     (plusp (sb-alien:slot winsize 'rows)))
                (values (sb-alien:slot winsize 'columns)
                        (sb-alien:slot winsize 'rows))
                (values nil nil)))
        (error () (values nil nil)))))

#+sbcl
(define-simple-assert %assert-terminal-dimension (name value)
  (and (integerp value) (plusp value))
  "Terminal ~A must be a positive integer, got ~S." name value)

#+sbcl
(defmacro %set-terminal-size (fd columns rows)
  "Set the window size on FD to COLUMNS by ROWS via ioctl TIOCSWINSZ.
Returns (VALUES T NIL) on success and (VALUES NIL REASON) on failure, where
REASON is :UNSUPPORTED-PLATFORM when the host's TIOCSWINSZ constant is unknown,
a string naming the errno when the ioctl itself failed, or the condition raised
at the alien-call boundary. The pixel dimensions are set to zero, which is what
a terminal reports when it measures its window in cells only.

Callers wanting the failure to be an error should use SET-TERMINAL-SIZE, which
turns REASON into a TERMINAL-SIZE-SET-FAILED condition."
  `(let ((fd ,fd) (columns ,columns) (rows ,rows))
     (setf fd (%assert-terminal-fd fd))
     (if (null +tiocswinsz+)
         (values nil :unsupported-platform)
         (handler-case
             (sb-alien:with-alien ((winsize (sb-alien:struct %winsize)))
               (setf (sb-alien:slot winsize 'rows) rows
                     (sb-alien:slot winsize 'columns) columns
                     (sb-alien:slot winsize 'x-pixels) 0
                     (sb-alien:slot winsize 'y-pixels) 0)
               (multiple-value-bind (successp errno)
                   (sb-unix:unix-ioctl fd +tiocswinsz+
                                       (sb-alien:alien-sap (sb-alien:addr winsize)))
                 (if successp
                     (values t nil)
                     (values nil (format nil "ioctl TIOCSWINSZ failed (errno ~A)"
                                         errno)))))
           (error (condition) (values nil condition))))))

#+sbcl
(defun set-terminal-size (columns rows &optional (fd 0))
  "Set the terminal window size on FD to COLUMNS by ROWS, returning
(VALUES COLUMNS ROWS) so the result reads back like TERMINAL-SIZE's.
FD defaults to standard input (0), and COLUMNS precedes ROWS, both matching
TERMINAL-SIZE. COLUMNS and ROWS must be positive integers and FD a non-negative
integer; anything else is a programmer error and is rejected before any ioctl is
attempted.

This is the write direction of TERMINAL-SIZE: it issues ioctl TIOCSWINSZ, which
is how a terminal -- or a multiplexer owning the master side of a PTY -- tells a
child process that its window changed. The child normally receives SIGWINCH.
Unlike TERMINAL-SIZE, a failure signals TERMINAL-SIZE-SET-FAILED (carrying FD,
COLUMNS, ROWS, and a REASON) rather than returning NIL: an unset size cannot be
substituted for the way an unknown size can."
  (%assert-terminal-dimension "columns" columns)
  (%assert-terminal-dimension "rows" rows)
  (setf fd (%assert-terminal-fd fd))
  (multiple-value-bind (successp reason) (%set-terminal-size fd columns rows)
    (unless successp
      (error 'terminal-size-set-failed
             :fd fd :columns columns :rows rows :reason reason))
    (values columns rows)))

#+sbcl
(defun %stream-fd (stream)
  "Return the underlying file descriptor of STREAM, unwrapping two-way and
synonym streams, or NIL when STREAM has no fd."
  (cond
    ((sb-sys:fd-stream-p stream) (sb-sys:fd-stream-fd stream))
    ((typep stream 'two-way-stream)
     (%stream-fd (two-way-stream-output-stream stream)))
    ((typep stream 'synonym-stream)
     (%stream-fd (symbol-value (synonym-stream-symbol stream))))
    (t nil)))

#+sbcl
(defun stream-fd (stream)
  "Return STREAM's underlying file descriptor, or NIL when it has none.

Unwraps two-way and synonym streams so callers can connect ordinary terminal
streams to the fd-centric input and wait APIs without using private helpers."
  (%stream-fd stream))
