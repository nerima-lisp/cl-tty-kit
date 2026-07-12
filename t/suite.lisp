(require :asdf)

(load (merge-pathnames #P"../scripts/bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))
(cl-tty-kit/bootstrap:load-support-files)

(in-package #:cl-tty-kit/test)

(defvar *test-failures* nil)

(defun load-example-symbol (file)
  (progv '(cl-user::*cl-tty-kit-run-example-on-load*) '(nil)
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
       (is (equal ,expected-value ,actual-value)
           ,(or description
                `(format nil "Expected ~S but got ~S from ~S"
                         ,expected-value
                         ,actual-value
                         ',form))))))

(defmacro signals ((condition variable) form &body body)
  `(handler-case
       (progn
         ,form
         (is nil ,(format nil "Expected ~A from ~S"
                          condition
                          form)))
     (,condition (,variable)
       ,@body
       t)))

(defmacro cell-is ((screen x y) char &optional style)
  (let ((cell (gensym "CELL-")))
    `(let ((,cell (screen-cell ,screen ,x ,y)))
       (is (char= ,char (cell-char ,cell)))
       ,@(when style
           `((is-equal ,style (cell-style ,cell)))))))

(defmacro screen-cells-is (screen &rest cells)
  `(progn
     ,@(mapcar (lambda (cell)
                 (destructuring-bind (x y char &key style) cell
                   `(cell-is (,screen ,x ,y) ,char ,style)))
               cells)))

(defmacro do-test-case-bind ((case cases lambda-list) &body body)
  `(dolist (,case ,cases)
     (destructuring-bind ,lambda-list ,case
       ,@body)))

(defmacro %assert-render-stream-output ((stream render-form) expected-output)
  `(let ((,stream (make-string-output-stream)))
     (is (eq ,stream ,render-form))
     (is (string= ,expected-output
                  (get-output-stream-string ,stream)))))

(defmacro is-fail (form &optional description)
  `(is (eq tty-prolog:+fail+ ,form)
       ,(or description
            `(format nil "~S should fail" ',form))))

(defun run-test (name thunk)
  (format t "~&[RUN] ~A~%" name)
  (finish-output)
  (funcall thunk)
  (format t "[OK]  ~A~%" name)
  (finish-output))

(defun run-tests ()
  (setf *test-failures* nil)
  (let ((tests '(("ansi" . cl-tty-kit/test::test-ansi)
                  ("package" . cl-tty-kit/test::test-package)
                  ("conditions" . cl-tty-kit/test::test-conditions)
                  ("prolog-unification" . cl-tty-kit/test::test-prolog-unification)
                  ("prolog-queries" . cl-tty-kit/test::test-prolog-queries)
                  ("prolog-primitives" . cl-tty-kit/test::test-prolog-primitives)
                  ("prolog-db" . cl-tty-kit/test::test-prolog-db-invariants)
                  ("keys" . cl-tty-kit/test::test-keys)
                 ("input" . cl-tty-kit/test::test-input)
                 ("utf8" . cl-tty-kit/test::test-utf8)
                 ("raw-mode" . cl-tty-kit/test::test-raw-mode)
                 ("session" . cl-tty-kit/test::test-terminal-session)
                 ("pty" . cl-tty-kit/test::test-pty)
                 ("screen" . cl-tty-kit/test::test-screen)
                 ("render" . cl-tty-kit/test::test-render)
                 ("cursor" . cl-tty-kit/test::test-cursor))))
    (dolist (test tests)
      (run-test (car test) (symbol-function (cdr test)))))
  (finish-output)
  (when *test-failures*
    (error "Some tests failed: ~S" (nreverse *test-failures*)))
  t)
