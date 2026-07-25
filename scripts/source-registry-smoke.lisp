(require :asdf)

(defparameter *smoke-timeout-seconds* 120)

(defmacro with-smoke-timeout ((label) &body body)
  `(handler-case
       (sb-ext:with-timeout *smoke-timeout-seconds*
         ,@body)
     (sb-ext:timeout ()
       (error "~A timed out after ~D seconds"
              ,label
              *smoke-timeout-seconds*))))

(defun call-exported-function (package-name symbol-name)
  (let* ((package (or (find-package package-name)
                      (error "Package ~A is not available." package-name)))
         (symbol (multiple-value-bind (symbol status)
                     (find-symbol symbol-name package)
                   (unless (eq status :external)
                     (error "Symbol ~A is not exported from ~A." symbol-name package-name))
                   symbol)))
    (funcall (symbol-function symbol))))

(let* ((root (uiop:ensure-directory-pathname (uiop:getcwd)))
       (system-file (merge-pathnames #P"cl-tty-kit.asd" root)))
  (unless (probe-file system-file)
    (error "Run this script from the project root so cl-tty-kit.asd is visible."))
  (asdf/source-registry:initialize-source-registry
   `(:source-registry (:tree ,(namestring root)) :ignore-inherited-configuration))
  (unless (asdf:find-system :cl-tty-kit)
    (error "Fresh source registry did not discover cl-tty-kit."))
  (unless (asdf:find-system :cl-tty-kit/test)
    (error "Fresh source registry did not discover cl-tty-kit/test."))
  (format t "~&[LOAD] cl-tty-kit via project bootstrap~%")
  (load (merge-pathnames #P"scripts/bootstrap.lisp" root))
  (with-smoke-timeout ("source-registry smoke test")
    (call-exported-function "CL-TTY-KIT/BOOTSTRAP" "LOAD-TEST-SYSTEM")
    (format t "~&[TEST] cl-tty-kit via project bootstrap~%")
    (call-exported-function "CL-TTY-KIT/TEST" "RUN-TESTS")))
