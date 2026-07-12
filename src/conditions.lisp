(in-package #:cl-tty-kit)

(defmacro define-tty-kit-condition (name superclasses slots documentation &body options)
  `(define-condition ,name ,superclasses
     ,slots
     (:documentation ,documentation)
     ,@options))

(defmacro define-formatted-tty-kit-condition (name superclasses slots documentation &rest report-spec)
  (if (and report-spec (keywordp (first report-spec)) (eql (first report-spec) :report))
      `(define-tty-kit-condition ,name ,superclasses
         ,slots
         ,documentation
         ,@report-spec)
      (destructuring-bind (format-string &rest format-args) report-spec
        `(define-tty-kit-condition ,name ,superclasses
           ,slots
           ,documentation
           (:report (lambda (condition stream)
                      (format stream ,format-string
                              ,@format-args)))))))

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

(define-formatted-tty-kit-condition pty-operation-failed (tty-kit-error)
  ((operation :initarg :operation :reader pty-operation-failed-operation)
   (pty :initarg :pty :reader pty-operation-failed-pty)
   (reason :initarg :reason :reader pty-operation-failed-reason))
  "Raised when a PTY operation fails."
  "PTY operation ~A failed: ~A."
  (pty-operation-failed-operation condition)
  (pty-operation-failed-reason condition))

(defun %signal-invalid-utf8-sequence (position octet reason)
  (error 'invalid-utf8-sequence
         :position position
         :octet octet
         :reason reason))

(defun unsupported (feature)
  (error 'unsupported-feature :feature feature))
