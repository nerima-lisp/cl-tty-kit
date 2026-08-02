(in-package #:cl-tty-kit)

(define-tty-kit-condition tty-kit-error (error)
  ()
  "Base condition for all cl-tty-kit errors.")

(define-formatted-tty-kit-condition unsupported-feature (tty-kit-error)
  ((feature :initarg :feature :reader unsupported-feature-feature))
  "Raised when an operation is not available in the current implementation."
  "Unsupported feature: ~A"
  (unsupported-feature-feature condition))

(define-formatted-tty-kit-condition invalid-utf8-sequence (tty-kit-error)
  ((position :initarg :position :reader invalid-utf8-sequence-position)
   (octet :initarg :octet :reader invalid-utf8-sequence-octet)
   (reason :initarg :reason :reader invalid-utf8-sequence-reason))
  "Raised when terminal input cannot be decoded as UTF-8."
  :report (lambda (condition stream)
            (let ((octet (invalid-utf8-sequence-octet condition)))
              (format stream "Invalid UTF-8 sequence at position ~D (~A~@[; octet ~2,'0X~])."
                      (invalid-utf8-sequence-position condition)
                      (invalid-utf8-sequence-reason condition)
                      (and (integerp octet) octet)))))

(define-formatted-tty-kit-condition screen-index-out-of-bounds (tty-kit-error)
  ((screen :initarg :screen :reader screen-index-out-of-bounds-screen)
   (x :initarg :x :reader screen-index-out-of-bounds-x)
   (y :initarg :y :reader screen-index-out-of-bounds-y)
   (width :initarg :width :reader screen-index-out-of-bounds-width)
   (height :initarg :height :reader screen-index-out-of-bounds-height))
  "Raised when a screen coordinate lies outside the screen bounds."
  "Cell position (~D, ~D) is outside the screen ~Dx~D."
  (screen-index-out-of-bounds-x condition)
  (screen-index-out-of-bounds-y condition)
  (screen-index-out-of-bounds-width condition)
  (screen-index-out-of-bounds-height condition))

(define-formatted-tty-kit-condition screen-dimensions-invalid (tty-kit-error)
  ((width :initarg :width :reader screen-dimensions-invalid-width)
   (height :initarg :height :reader screen-dimensions-invalid-height))
  "Raised when screen dimensions are not non-negative integers."
  "Invalid screen dimensions ~Sx~S."
  (screen-dimensions-invalid-width condition)
  (screen-dimensions-invalid-height condition))

(define-formatted-tty-kit-condition cursor-parameter-invalid (tty-kit-error)
  ((parameter :initarg :parameter :reader cursor-parameter-invalid-parameter)
   (value :initarg :value :reader cursor-parameter-invalid-value)
   (expected :initarg :expected :reader cursor-parameter-invalid-expected))
  "Raised when a cursor coordinate, bound, or visibility value is invalid."
  "Invalid cursor parameter ~A: ~S (expected ~A)."
  (cursor-parameter-invalid-parameter condition)
  (cursor-parameter-invalid-value condition)
  (cursor-parameter-invalid-expected condition))

(define-formatted-tty-kit-condition unsupported-code-point (tty-kit-error)
  ((code-point :initarg :code-point :reader unsupported-code-point-code-point))
  "Raised when a character cannot be represented in the current terminal."
  "Unsupported Unicode code point ~D."
  (unsupported-code-point-code-point condition))

(define-formatted-tty-kit-condition raw-mode-operation-failed (tty-kit-error)
  ((operation :initarg :operation :reader raw-mode-operation-failed-operation)
   (fd :initarg :fd :reader raw-mode-operation-failed-fd)
   (reason :initarg :reason :reader raw-mode-operation-failed-reason))
  "Raised when switching a terminal file descriptor into raw mode fails."
  "Raw mode operation ~A failed for FD ~D: ~A."
  (raw-mode-operation-failed-operation condition)
  (raw-mode-operation-failed-fd condition)
  (raw-mode-operation-failed-reason condition))

(define-formatted-tty-kit-condition terminal-size-set-failed (tty-kit-error)
  ((fd :initarg :fd :reader terminal-size-set-failed-fd)
   (columns :initarg :columns :reader terminal-size-set-failed-columns)
   (rows :initarg :rows :reader terminal-size-set-failed-rows)
   (reason :initarg :reason :reader terminal-size-set-failed-reason))
  "Raised when a terminal's window size cannot be set via ioctl TIOCSWINSZ."
  "Could not set the window size on FD ~D to ~D columns by ~D rows: ~A."
  (terminal-size-set-failed-fd condition)
  (terminal-size-set-failed-columns condition)
  (terminal-size-set-failed-rows condition)
  (terminal-size-set-failed-reason condition))

(define-formatted-tty-kit-condition pty-operation-failed (tty-kit-error)
  ((operation :initarg :operation :reader pty-operation-failed-operation)
   (pty :initarg :pty :reader pty-operation-failed-pty)
   (reason :initarg :reason :reader pty-operation-failed-reason))
  "Raised when a PTY operation fails."
  "PTY operation ~A failed: ~A."
  (pty-operation-failed-operation condition)
  (pty-operation-failed-reason condition))

;; Internal (unexported) guard condition: it inherits from the exported
;; TTY-KIT-ERROR so callers can catch it by base type, but it is not part of the
;; documented public symbol set.
(define-formatted-tty-kit-condition input-buffer-exceeded (tty-kit-error)
  ((limit :initarg :limit :reader input-buffer-exceeded-limit)
   (size :initarg :size :reader input-buffer-exceeded-size))
  "Raised when an input decoder's buffered, still-undecoded tail grows past its
configured limit, which bounds memory use when decoding untrusted input."
  "Input decoder buffer of ~D units exceeds the ~D unit limit."
  (input-buffer-exceeded-size condition)
  (input-buffer-exceeded-limit condition))

(dolist (documentation-entry
         '((unsupported-feature-feature
            "Return the feature keyword that is unavailable in this implementation.")
           (invalid-utf8-sequence-position
            "Return the octet position within the input where UTF-8 decoding failed.")
           (invalid-utf8-sequence-octet
            "Return the offending octet, or NIL when the failure has no single octet.")
           (invalid-utf8-sequence-reason
            "Return the keyword describing why the UTF-8 sequence was rejected.")
           (screen-index-out-of-bounds-screen
            "Return the screen whose bounds the offending coordinate exceeded.")
           (screen-index-out-of-bounds-x
            "Return the X coordinate that fell outside the screen bounds.")
           (screen-index-out-of-bounds-y
            "Return the Y coordinate that fell outside the screen bounds.")
           (screen-index-out-of-bounds-width
            "Return the width of the screen that reported the out-of-bounds access.")
           (screen-index-out-of-bounds-height
            "Return the height of the screen that reported the out-of-bounds access.")
           (screen-dimensions-invalid-width
            "Return the width value that failed screen-dimension validation.")
           (screen-dimensions-invalid-height
            "Return the height value that failed screen-dimension validation.")
           (cursor-parameter-invalid-parameter
            "Return the name of the cursor parameter that was rejected.")
           (cursor-parameter-invalid-value
            "Return the rejected value supplied for the cursor parameter.")
           (cursor-parameter-invalid-expected
            "Return a description of the contract the cursor parameter must satisfy.")
           (unsupported-code-point-code-point
            "Return the Unicode code point that cannot be represented.")
           (raw-mode-operation-failed-operation
            "Return the raw-mode operation keyword that failed.")
           (raw-mode-operation-failed-fd
            "Return the file descriptor whose raw-mode operation failed.")
           (raw-mode-operation-failed-reason
            "Return the underlying condition that caused the raw-mode failure.")
           (terminal-size-set-failed-fd
            "Return the file descriptor whose window size could not be set.")
           (terminal-size-set-failed-columns
            "Return the column count that was requested but not applied.")
           (terminal-size-set-failed-rows
            "Return the row count that was requested but not applied.")
           (terminal-size-set-failed-reason
            "Return why the window size could not be set: the keyword
:UNSUPPORTED-PLATFORM when the host's TIOCSWINSZ constant is unknown, a string
describing the failed ioctl, or the condition signaled at the alien-call
boundary.")
           (pty-operation-failed-operation
            "Return the PTY operation keyword that failed.")
           (pty-operation-failed-pty
            "Return the PTY object involved in the failure, or NIL for spawn failures.")
           (pty-operation-failed-reason
            "Return the underlying condition that caused the PTY failure.")))
  (destructuring-bind (reader documentation) documentation-entry
    (setf (documentation reader 'function) documentation)))

(defmacro %signal-invalid-utf8-sequence (position octet reason)
  `(error 'invalid-utf8-sequence
          :position ,position
          :octet ,octet
          :reason ,reason))

(defmacro unsupported (feature)
  `(error 'unsupported-feature :feature ,feature))
