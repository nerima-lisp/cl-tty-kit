(require :asdf)

;; The project bootstrap is normally loaded by the invoking script (test.lisp,
;; verify.lisp, ...) before this system. Only fall back to loading it directly
;; when it is missing, and resolve it from the source file rather than a possibly
;; cached fasl location so the reload works regardless of ASDF output
;; translations.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package '#:cl-tty-kit/bootstrap)
    (load
      (merge-pathnames
        #P"../scripts/bootstrap.lisp"
        (uiop:pathname-directory-pathname (or *compile-file-truename* *load-truename*))))))

(cl-tty-kit/bootstrap:load-support-files)

(in-package #:cl-tty-kit/test)

(defun load-example-symbol (file)
  (progv
    '(cl-user::*cl-tty-kit-run-example-on-load*)
    '(nil)
    (cl-tty-kit/bootstrap:load-example-file file))
  (let ((symbol (cl-user::example-function-symbol file)))
    (unless symbol
      (error "No example function found for ~A" file))
    symbol))

(defmacro expect-non-type-error (form)
  "Assert FORM signals an ERROR that is not a TYPE-ERROR.

Every public entry point in this codebase validates its arguments and
signals a domain condition (never a bare TYPE-ERROR) on bad input; this
macro is the shared assertion for that contract across the test suite."
  `(expect (lambda () ,form) :to-throw (lambda (c) (not (typep c 'type-error)))))

(defmacro expect-cell ((screen x y) char &optional style)
  "Assert the cell at (X, Y) in SCREEN has CHAR and, when given, STYLE."
  (let ((cell (gensym "CELL-")))
    `(let ((,cell (screen-cell ,screen ,x ,y)))
      (expect (cell-char ,cell) :to-be ,char)
      ,@(when style
        `((expect (cell-style ,cell) :to-equal ,style))))))

(defmacro expect-render-stream-output ((stream render-form) expected-output)
  "Assert RENDER-FORM writes to STREAM, returns it, and its accumulated
output equals EXPECTED-OUTPUT."
  `(let ((,stream (make-string-output-stream)))
    (expect ,render-form :to-be ,stream)
    (expect (get-output-stream-string ,stream) :to-equal ,expected-output)))

(defun run-test (name thunk)
  (format t "~&[RUN] ~A~%" name)
  (finish-output)
  (funcall thunk)
  (format t "[OK]  ~A~%" name)
  (finish-output))

(defun run-tests ()
  (unless (uiop:symbol-call (quote #:cl-weave) (quote #:run-all) :reporter :spec)
    (error "The test suite reported a failing case."))
  t)
