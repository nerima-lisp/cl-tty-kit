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

(defvar *test-failures* nil)

(defun load-example-symbol (file)
  (progv
    '(cl-user::*cl-tty-kit-run-example-on-load*)
    '(nil)
    (cl-tty-kit/bootstrap:load-example-file file))
  (let ((symbol (cl-user::example-function-symbol file)))
    (unless symbol
      (error "No example function found for ~A" file))
    symbol))

(defmacro is (form &optional (description (prin1-to-string form)))
  `(unless ,form
    (push ,description *test-failures*)
    (error "Test failed: ~A" ,description)))

(defmacro is-equal (expected form &optional description)
  (let ((expected-value (gensym "EXPECTED-"))
        (actual-value (gensym "ACTUAL-")))
    `(let ((,expected-value ,expected)
          (,actual-value ,form))
      (is
        (equal ,expected-value ,actual-value)
        ,(or
          description
          `(format
            nil
            "Expected ~S but got ~S from ~S"
            ,expected-value
            ,actual-value
            ',form))))))

(defmacro signals ((condition variable) form &body body)
  `(handler-case (progn
      ,form
      (is nil ,(format nil "Expected ~A from ~S" condition form)))
    (,condition (,variable)
      ,@body
      t)))

(defmacro signals-non-type-error (form)
  "Assert FORM signals an ERROR that is not a TYPE-ERROR.

Every public entry point in this codebase validates its arguments and
signals a domain condition (never a bare TYPE-ERROR) on bad input; this
macro is the shared assertion for that contract across the test suite."
  `(handler-case (progn
      ,form
      (is nil))
    (type-error (condition)
      (declare (ignore condition))
      (is nil))
    (error (condition)
      (declare (ignore condition))
      (is t))))

(defmacro expect-non-type-error (form)
  "The cl-weave counterpart to SIGNALS-NON-TYPE-ERROR, for files already
migrated onto EXPECT. Once every SIGNALS-NON-TYPE-ERROR caller migrates,
delete SIGNALS-NON-TYPE-ERROR and rename this to it."
  `(expect (lambda () ,form) :to-throw (lambda (c) (not (typep c 'type-error)))))

(defmacro cell-is ((screen x y) char &optional style)
  (let ((cell (gensym "CELL-")))
    `(let ((,cell (screen-cell ,screen ,x ,y)))
      (is (char= ,char (cell-char ,cell)))
      ,@(when style
        `((is-equal ,style (cell-style ,cell)))))))

(defmacro screen-cells-is (screen &rest cells)
  `(progn
    ,@(mapcar
      (lambda (cell)
        (destructuring-bind (x y char &key style) cell
          `(cell-is (,screen ,x ,y) ,char ,style)))
      cells)))

(defmacro expect-cell ((screen x y) char &optional style)
  "The cl-weave counterpart to CELL-IS, for files already migrated onto
EXPECT. Once every CELL-IS caller (t/screen-test.lisp, t/screen-mutation-test.lisp)
migrates, delete CELL-IS/SCREEN-CELLS-IS and rename this to CELL-IS."
  (let ((cell (gensym "CELL-")))
    `(let ((,cell (screen-cell ,screen ,x ,y)))
      (expect (cell-char ,cell) :to-be ,char)
      ,@(when style
        `((expect (cell-style ,cell) :to-equal ,style))))))

(defmacro do-test-case-bind ((case cases
      lambda-list)
    &body
    body)
  `(dolist (,case ,cases)
    (destructuring-bind ,lambda-list ,case
      ,@body)))

(defmacro %assert-render-stream-output ((stream render-form) expected-output)
  `(let ((,stream (make-string-output-stream)))
    (is (eq ,stream ,render-form))
    (is (string= ,expected-output (get-output-stream-string ,stream)))))

(defmacro expect-render-stream-output ((stream render-form) expected-output)
  "The cl-weave counterpart to %ASSERT-RENDER-STREAM-OUTPUT, for files already
migrated onto EXPECT. Once every %ASSERT-RENDER-STREAM-OUTPUT caller
(t/render-core-test.lisp, t/render-diff-test.lisp) migrates, delete it."
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
  (setf *test-failures* nil)
  (let ((tests (quote (("package" . cl-tty-kit/test::test-package)
                       ("keys" . cl-tty-kit/test::test-keys)
                       ("input" . cl-tty-kit/test::test-input)
                       ("session" . cl-tty-kit/test::test-terminal-session)
                       ("pty" . cl-tty-kit/test::test-pty)
                       ("pty-fd" . cl-tty-kit/test::test-pty-fd)
                       ("screen" . cl-tty-kit/test::test-screen)
                       ("renderer" . cl-tty-kit/test::test-renderer)))))
    (dolist (test tests)
      (run-test (car test) (symbol-function (cdr test)))))
  (finish-output)
  (when *test-failures*
    (error "Some tests failed: ~S" (nreverse *test-failures*)))
  ;; Every cl-weave-migrated file (t/conditions-test.lisp, t/properties-test.lisp,
  ;; ...) registers its DESCRIBE/IT suites into cl-weave's global registry as it
  ;; loads; RUN-ALL then runs the whole union in one pass. Calling it once here
  ;; -- rather than once per migrated file -- is what keeps that union a single
  ;; run instead of re-running every already-migrated suite again per file.
  (run-test "cl-weave"
            (lambda ()
              (unless (uiop:symbol-call (quote #:cl-weave) (quote #:run-all) :reporter :spec)
                (error "A cl-weave-migrated suite reported a failing case."))))
  (dolist (test (quote (("render-core" . test-render-core)
                        ("render-diff" . test-render-diff)
                        ("render-examples" . test-render-examples))))
    (run-test (car test) (symbol-function (cdr test))))
  t)
