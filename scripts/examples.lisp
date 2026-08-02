(require :asdf)

(load
  (merge-pathnames
    #P"bootstrap.lisp"
    (uiop:pathname-directory-pathname *load-truename*)))

(cl-tty-kit/bootstrap:load-core-system)

(cl-tty-kit/bootstrap:load-support-files)

(progn
  (cl-tty-kit/bootstrap:with-script-timeout
    ("examples" 30)
    (dolist (file (cl-user::example-script-files))
      (format t "~&[RUN] ~A~%" file)
      (finish-output)
      (cl-tty-kit/bootstrap:run-example-file file)))
  (uiop:quit 0))
