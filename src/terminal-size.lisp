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
(defun %assert-terminal-fd (fd)
  (unless (and (integerp fd) (not (minusp fd)))
    (error "Terminal FD must be a non-negative integer, got ~S." fd))
  fd)

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
            (if (and (sb-unix:unix-ioctl fd +tiocgwinsz+ (sb-alien:alien-sap (sb-alien:addr winsize)))
                     (plusp (sb-alien:slot winsize 'columns))
                     (plusp (sb-alien:slot winsize 'rows)))
                (values (sb-alien:slot winsize 'columns)
                        (sb-alien:slot winsize 'rows))
                (values nil nil)))
        (error () (values nil nil)))))

#+sbcl
(defun %set-terminal-size (fd columns rows)
  "Set the window size on FD to COLUMNS by ROWS via ioctl TIOCSWINSZ.
Returns true on success, NIL when the platform constant is unknown or the ioctl
fails."
  (setf fd (%assert-terminal-fd fd))
  (if (null +tiocswinsz+)
      nil
      (handler-case
          (sb-alien:with-alien ((winsize (sb-alien:struct %winsize)))
            (setf (sb-alien:slot winsize 'rows) rows
                  (sb-alien:slot winsize 'columns) columns
                  (sb-alien:slot winsize 'x-pixels) 0
                  (sb-alien:slot winsize 'y-pixels) 0)
            (and (sb-unix:unix-ioctl fd +tiocswinsz+ (sb-alien:alien-sap (sb-alien:addr winsize))) t))
        (error () nil))))

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
