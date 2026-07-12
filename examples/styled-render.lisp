(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun styled-render-example ()
  (let ((previous (cl-tty-kit:make-screen 12 2))
        (current (cl-tty-kit:make-screen 12 2)))
    (cl-tty-kit:screen-put-cell current 0 0 #\H
                                :style (cl-tty-kit:make-style :bold
                                                              (cl-tty-kit:style-fg 196)))
    (cl-tty-kit:screen-put-cell current 1 0 #\i
                                :style (cl-tty-kit:make-style
                                        (cl-tty-kit:style-fg 33)))
    (cl-tty-kit:screen-put-cell current 0 1 #\!
                                :style (cl-tty-kit:make-style :underline
                                                              (cl-tty-kit:style-bg 17)))
    (cl-tty-kit:render-diff current previous)))

(defun run-styled-render-example ()
  (format t "~A~%" (styled-render-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-styled-render-example))
