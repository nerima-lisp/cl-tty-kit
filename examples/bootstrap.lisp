(load (merge-pathnames #P"../scripts/bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(unless (find-package :cl-tty-kit)
  (cl-tty-kit/bootstrap:load-core-system))
