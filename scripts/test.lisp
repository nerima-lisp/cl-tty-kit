(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(defparameter *test-timeout-seconds* 120)

(defmacro with-test-timeout ((label) &body body)
  `(handler-case
       (sb-ext:with-timeout *test-timeout-seconds*
         ,@body)
     (sb-ext:timeout ()
       (error "~A timed out after ~D seconds"
              ,label
              *test-timeout-seconds*))))

(defun call-exported-function (package-name symbol-name)
  (let* ((package (or (find-package package-name)
                      (error "Package ~A is not available." package-name)))
         (symbol (multiple-value-bind (symbol status)
                     (find-symbol symbol-name package)
                   (unless (eq status :external)
                     (error "Symbol ~A is not exported from ~A." symbol-name package-name))
                   symbol)))
    (funcall (symbol-function symbol))))

(with-test-timeout ("test suite")
  (call-exported-function "CL-TTY-KIT/BOOTSTRAP" "LOAD-TEST-SYSTEM")
  (call-exported-function "CL-TTY-KIT/TEST" "RUN-TESTS"))
