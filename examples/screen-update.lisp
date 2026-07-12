(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun screen-update-example ()
  (let ((previous (cl-tty-kit:make-screen 10 2))
        (current (cl-tty-kit:make-screen 10 2)))
    (cl-tty-kit:screen-put-cell current 0 0 #\H)
    (cl-tty-kit:screen-put-cell current 1 0 #\i)
    (cl-tty-kit:screen-put-cell current 0 1 #\!)
    (cl-tty-kit:render-diff current previous)))

(defun run-screen-update-example ()
  (format t "~A~%" (screen-update-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-screen-update-example))
