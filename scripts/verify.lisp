(require :asdf)

(load
  (merge-pathnames
    #P"bootstrap.lisp"
    (uiop:pathname-directory-pathname *load-truename*)))

(defun call-exported-function (package-name symbol-name &rest arguments)
  (let* ((package
        (or
          (find-package package-name)
          (error "Package ~A is not available." package-name)))
         (symbol
        (multiple-value-bind (symbol status) (find-symbol symbol-name package)
          (unless (eq status :external)
            (error "Symbol ~A is not exported from ~A." symbol-name package-name))
          symbol)))
    (apply (symbol-function symbol) arguments)))

(call-exported-function "CL-TTY-KIT/BOOTSTRAP" "LOAD-SUPPORT-FILES")

(defparameter *verify-timeout-seconds* 60)

(defmacro with-step-timeout ((label) &body body)
  `(cl-tty-kit/bootstrap:with-script-timeout (,label *verify-timeout-seconds*) ,@body))

(defun run-source-registry-smoke ()
  (let* ((scripts-dir (uiop:pathname-directory-pathname *load-truename*))
         (project-root (merge-pathnames #P"../" scripts-dir))
         (smoke-script (merge-pathnames #P"source-registry-smoke.lisp" scripts-dir)))
    (format t "~&[SOURCE-REGISTRY] cl-tty-kit~%")
    (finish-output)
    (with-step-timeout
      ("source-registry smoke")
      (uiop:run-program
        (list "sbcl" "--script" (namestring smoke-script))
        :directory
        project-root
        :output
        *standard-output*
        :error-output
        *error-output*))))

(format t "~&[TEST] cl-tty-kit~%")

(finish-output)

(with-step-timeout
  ("test suite")
  (call-exported-function "CL-TTY-KIT/BOOTSTRAP" "LOAD-TEST-SYSTEM")
  (call-exported-function "CL-TTY-KIT/TEST" "RUN-TESTS"))

(format t "~&[EXAMPLES] cl-tty-kit~%")

(finish-output)

(with-step-timeout
  ("examples")
  (dolist (file (cl-user::example-script-files))
    (format t "~&[RUN] ~A~%" file)
    (finish-output)
    (call-exported-function "CL-TTY-KIT/BOOTSTRAP" "RUN-EXAMPLE-FILE" file)))

(progn
  (run-source-registry-smoke)
  (uiop:quit 0))
