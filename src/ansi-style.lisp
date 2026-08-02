(in-package #:cl-tty-kit)

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

(defmacro %validate-repeat-count (count)
  `(let ((count ,count))
     (unless (typep count '(integer 0 *))
       (error "Repeat count ~S must be a non-negative integer." count))
     count))

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
