(in-package #:cl-tty-kit)

(defmacro %assert (predicate format-string &rest format-args)
  "Signal an ERROR via FORMAT-STRING/FORMAT-ARGS unless PREDICATE holds.

Every argument-validating %ASSERT-* helper in this codebase reduces to this one
control-flow shape (check a predicate, signal a formatted error on failure);
centralizing it here removes dozens of duplicated UNLESS/ERROR bodies."
  `(unless ,predicate
     (error ,format-string ,@format-args)))

(defmacro define-simple-assert (name lambda-list predicate format-string &rest format-args)
  "Define NAME as a function of LAMBDA-LIST that signals an error via
FORMAT-STRING/FORMAT-ARGS unless PREDICATE holds.

Every %ASSERT-* validation helper in this codebase is a DEFUN whose entire
body is one %ASSERT call; this macro is that shape's single declarative
spelling, so a validation helper is one form instead of a DEFUN wrapping one
%ASSERT wrapping one UNLESS."
  `(defun ,name ,lambda-list
     (%assert ,predicate ,format-string ,@format-args)))

(defmacro define-validating-assert (name lambda-list predicate format-string &rest format-args)
  "Define NAME as a function of LAMBDA-LIST that signals an error via
FORMAT-STRING/FORMAT-ARGS unless PREDICATE holds, then returns its final
argument.

Distinct from DEFINE-SIMPLE-ASSERT: some %ASSERT-* helpers validate purely
as a side effect (their caller already holds the value), while others
validate and hand the now-checked value back so the caller can use the
validation call itself as an expression. This macro is that second shape's
single declarative spelling."
  `(defun ,name ,lambda-list
     (%assert ,predicate ,format-string ,@format-args)
     ,(car (last lambda-list))))

(defmacro document-function (name docstring)
  "Set the FUNCTION documentation of NAME -- a quoted symbol, e.g. 'RECT-X --
to DOCSTRING.

A DEFSTRUCT accessor, and a few other functions defined by a form with no
docstring slot of its own, are documented this way instead of wrapping each
in a DEFUN merely to hold a string. Every call across SRC/ reduces to this
one SETF; centralizing it here removes dozens of duplicated
`(setf (documentation 'name 'function) ...)` bodies and gives them one name
to grep for."
  `(setf (documentation ,name 'function) ,docstring))

(defmacro define-tty-kit-condition (name superclasses slots documentation &body options)
  `(define-condition ,name ,superclasses
     ,slots
     (:documentation ,documentation)
     ,@options))

(defmacro define-formatted-tty-kit-condition
    (name superclasses slots documentation &rest report-spec)
  (if (and report-spec (keywordp (first report-spec)) (eql (first report-spec) :report))
      `(define-tty-kit-condition ,name ,superclasses
         ,slots
         ,documentation
         (:report ,(second report-spec)))
      (destructuring-bind (format-string &rest format-args) report-spec
        `(define-tty-kit-condition ,name ,superclasses
           ,slots
           ,documentation
           (:report (lambda (condition stream)
                      (format stream ,format-string
                              ,@format-args)))))))
