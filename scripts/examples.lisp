(require :asdf)

(load
  (merge-pathnames
    #P"bootstrap.lisp"
    (uiop:pathname-directory-pathname *load-truename*)))

(cl-tty-kit/bootstrap:load-core-system)

(cl-tty-kit/bootstrap:load-support-files)

(defparameter *examples-timeout-seconds* 30)

(defmacro with-examples-timeout (() &body body)
  `(handler-case (sb-ext:with-timeout *examples-timeout-seconds* ,@body)
    (sb-ext:timeout ()
      (error "examples timed out after ~D seconds" *examples-timeout-seconds*))))

(progn
  (with-examples-timeout
    ()
    (dolist (file (cl-user::example-script-files))
      (format t "~&[RUN] ~A~%" file)
      (finish-output)
      (cl-tty-kit/bootstrap:run-example-file file)))
  (uiop:quit 0))
