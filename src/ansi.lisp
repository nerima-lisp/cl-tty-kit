(in-package #:cl-tty-kit)

(defconstant +escape+ #\Esc)

(defmacro define-ansi-function (name lambda-list docstring format-string &rest format-args)
  `(defun ,name ,lambda-list
     ,docstring
     (format nil ,format-string +escape+ ,@format-args)))

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

(define-ansi-function ansi-bold ()
    "Return the ANSI sequence that enables bold text."
  "~C[1m")

(define-ansi-function ansi-reset-style ()
    "Return the ANSI sequence that resets all styles."
  "~C[0m")
