(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun simple-render-example ()
  (let ((screen (cl-tty-kit:make-screen 20 3)))
    (cl-tty-kit:screen-write-string screen 0 0 "Hi")
    (cl-tty-kit:screen-write-string screen 0 1 "!")
    (cl-tty-kit:render-screen screen)))

(defun run-simple-render-example ()
  (format t "~A~%" (simple-render-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-simple-render-example))
