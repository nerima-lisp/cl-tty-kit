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

(defun %validate-csi-numeric-parameter (value)
  (unless (typep value '(integer 0 *))
    (error "CSI numeric parameter must be a non-negative integer: ~S." value))
  value)

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

(define-ansi-function ansi-bold ()
    "Return the ANSI sequence that enables bold text."
  "~C[1m")

(define-ansi-function ansi-dim ()
    "Return the ANSI sequence that enables dim (faint) text."
  "~C[2m")

(define-ansi-function ansi-italic ()
    "Return the ANSI sequence that enables italic text."
  "~C[3m")

(define-ansi-function ansi-underline ()
    "Return the ANSI sequence that enables underlined text."
  "~C[4m")

(define-ansi-function ansi-blink ()
    "Return the ANSI sequence that enables blinking text."
  "~C[5m")

(define-ansi-function ansi-reverse ()
    "Return the ANSI sequence that enables reverse-video text."
  "~C[7m")

(define-ansi-function ansi-hidden ()
    "Return the ANSI sequence that enables hidden (concealed) text."
  "~C[8m")

(define-ansi-function ansi-strikethrough ()
    "Return the ANSI sequence that enables strikethrough text."
  "~C[9m")

(define-ansi-function ansi-default-foreground ()
    "Return the SGR sequence that resets the foreground to the default color."
  "~C[39m")

(define-ansi-function ansi-default-background ()
    "Return the SGR sequence that resets the background to the default color."
  "~C[49m")

(define-ansi-function ansi-reset-style ()
    "Return the ANSI sequence that resets all styles."
  "~C[0m")

(defun %validate-repeat-count (count)
  (unless (typep count '(integer 0 *))
    (error "Repeat count ~S must be a non-negative integer." count))
  count)

(defun ansi-bell (&optional (count 1))
  "Return a string of COUNT BEL (^G) characters that ring the terminal bell."
  (make-string (%validate-repeat-count count) :initial-element (code-char 7)))

(define-ansi-function ansi-reset-terminal ()
    "Return the RIS sequence that resets the terminal to its initial state."
  "~Cc")

(define-ansi-function ansi-begin-synchronized-update ()
    "Return the sequence that begins a synchronized (atomic) screen update.
Terminals supporting DEC private mode 2026 buffer output until the matching
ANSI-END-SYNCHRONIZED-UPDATE, so a full repaint or a RENDERER-RENDER shows without
tearing."
  "~C[?2026h")

(define-ansi-function ansi-end-synchronized-update ()
    "Return the sequence that ends a synchronized screen update and presents it."
  "~C[?2026l")

(defun %sgr-parameter-character-p (character)
  (or (digit-char-p character)
      (char= character #\:)))

(defun %validate-sgr-parameter (code)
  (typecase code
    ((integer 0 *)
     code)
    (string
     (unless (and (plusp (length code))
                  (every #'%sgr-parameter-character-p code)
                  (some #'digit-char-p code))
       (error "Invalid SGR parameter ~S; expected a non-negative integer or a digit/colon string."
              code))
     code)
    (t
     (error "Invalid SGR parameter ~S; expected a non-negative integer or a digit/colon string."
            code))))

(defun ansi-sgr (&rest codes)
  "Return an SGR escape sequence combining CODES into a single `ESC[...m'.
Each element of CODES is a non-negative integer or a digit/colon string SGR
sub-parameter such as \"4:3\"; they are joined with semicolons in order. With no
CODES the result is the bare `ESC[m' reset. This is the general builder the
named emitters like ANSI-BOLD and ANSI-UNDERLINE specialize."
  (format nil "~C[~{~A~^;~}m" +escape+ (mapcar #'%validate-sgr-parameter codes)))
