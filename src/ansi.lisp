(in-package #:cl-tty-kit)

(progn
  (defconstant +escape+ #\Esc)

  (defconstant +ansi-reset-style-length+ 4)

  (declaim
    (inline
      %write-ansi-clear-screen
      %write-ansi-clear-line
      %write-ansi-move-cursor
      %write-ansi-cursor-visibility
      %write-ansi-reset-style))

  (defun %write-ansi-clear-screen (stream)
    (write-char +escape+ stream)
    (write-string "[2J" stream)
    stream)

  (defun %write-ansi-clear-line (stream)
    (write-char +escape+ stream)
    (write-string "[0K" stream)
    stream)

  (defun %write-ansi-move-cursor (row column stream)
    (declare (type (integer 1 *) row column))
    (write-char +escape+ stream)
    (write-char #\[ stream)
    (write row :stream stream :escape nil :base 10 :radix nil)
    (write-char #\; stream)
    (write column :stream stream :escape nil :base 10 :radix nil)
    (write-char #\H stream)
    stream)

  (defun %write-ansi-cursor-visibility (visible-p stream)
    (write-char +escape+ stream)
    (write-string (if visible-p "[?25h" "[?25l") stream)
    stream)

  (defun %write-ansi-reset-style (stream)
    (write-char +escape+ stream)
    (write-string "[0m" stream)
    stream))

(defmacro %validate-csi-numeric-parameter (value)
  `(let ((value ,value))
     (unless (typep value '(integer 0 *))
       (error "CSI numeric parameter must be a non-negative integer: ~S." value))
     value))

(defmacro define-ansi-function (name lambda-list docstring format-string &rest format-args)
  `(defun ,name ,lambda-list
     ,docstring
     (format nil ,format-string +escape+
             ,@(mapcar (lambda (arg)
                         `(%validate-csi-numeric-parameter ,arg))
                       format-args))))

(define-ansi-function ansi-clear-screen (&optional (mode 2))
    "Return the ANSI sequence that clears the screen."
  "~C[~DJ"
  mode)

(define-ansi-function ansi-clear-line (&optional (mode 2))
    "Return the ANSI sequence that clears a line."
  "~C[~DK"
  mode)

(define-ansi-function ansi-move-cursor (row col)
    "Return the ANSI sequence that moves the cursor to ROW and COL."
  "~C[~D;~DH"
  row
  col)

(define-ansi-function ansi-hide-cursor ()
    "Return the ANSI sequence that hides the cursor."
  "~C[?25l")

(define-ansi-function ansi-show-cursor ()
    "Return the ANSI sequence that shows the cursor."
  "~C[?25h")

(define-ansi-function ansi-enter-alternate-screen ()
    "Return the ANSI sequence that enters the alternate screen buffer."
  "~C[?1049h")

(define-ansi-function ansi-exit-alternate-screen ()
    "Return the ANSI sequence that exits the alternate screen buffer."
  "~C[?1049l")

(define-ansi-function ansi-enable-bracketed-paste ()
    "Return the ANSI sequence that enables bracketed paste mode."
  "~C[?2004h")

(define-ansi-function ansi-disable-bracketed-paste ()
    "Return the ANSI sequence that disables bracketed paste mode."
  "~C[?2004l")

(define-ansi-function ansi-request-device-attributes ()
    "Return the Primary Device Attributes (DA1) query `ESC [ c'.
The terminal replies with `ESC [ ? ... c' listing the features it supports, which
DECODE-DEVICE-ATTRIBUTES parses."
  "~C[c")

(define-ansi-function ansi-request-cursor-position ()
    "Return the DSR sequence that asks the terminal for the cursor position.
The terminal replies with `ESC [ row ; col R', which DECODE-CURSOR-POSITION-REPORT
parses. (That reply is not folded into DECODE-INPUT because it is ambiguous with a
modified F3 key, so decode it explicitly after issuing this request.)"
  "~C[6n")

(define-ansi-function ansi-enable-focus-reporting ()
    "Return the ANSI sequence that enables focus-in/focus-out reporting.
The terminal then emits `ESC [ I' on focus and `ESC [ O' on blur, which
DECODE-INPUT surfaces as :FOCUS-IN and :FOCUS-OUT special key events."
  "~C[?1004h")

(define-ansi-function ansi-disable-focus-reporting ()
    "Return the ANSI sequence that disables focus-in/focus-out reporting."
  "~C[?1004l")

(define-ansi-function ansi-set-keyboard-enhancements (flags &optional (mode 1))
    "Return the CSI u sequence that sets keyboard enhancement FLAGS.

MODE follows the kitty keyboard progressive enhancement protocol:
1 replaces the current flags, 2 sets bits, and 3 resets bits."
  "~C[=~D;~Du"
  flags
  mode)

(define-ansi-function ansi-push-keyboard-enhancements (flags)
    "Return the CSI u sequence that pushes keyboard enhancement FLAGS."
  "~C[>~Du"
  flags)

(define-ansi-function ansi-pop-keyboard-enhancements (&optional (count 1))
    "Return the CSI u sequence that pops COUNT keyboard enhancement scopes."
  "~C[<~Du"
  count)
