(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun frame-render-example ()
  (let ((previous (cl-tty-kit:make-screen 12 2))
        (current (cl-tty-kit:make-screen 12 2))
        (cursor (cl-tty-kit:make-cursor :x 2 :y 1)))
    (cl-tty-kit:screen-write-string current 0 0 "Hi")
    (cl-tty-kit:screen-write-string current 0 1 "!")
    (cl-tty-kit:render-frame-diff current previous cursor)))

(defun run-frame-render-example ()
  (format t "~A~%" (frame-render-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-frame-render-example))
