(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun %dashboard-screen (status jobs)
  (let ((screen (cl-tty-kit:make-screen 28 5)))
    (cl-tty-kit:screen-write-string screen 0 0 "TTY monitor" :style '(:bold))
    (cl-tty-kit:screen-write-string screen 0 2 "status:")
    (cl-tty-kit:screen-write-string screen 8 2 status :style '(:bold))
    (cl-tty-kit:screen-write-string screen 0 3 "jobs:")
    (cl-tty-kit:screen-write-string screen 6 3 jobs)
    screen))

(defun status-dashboard-example ()
  (let* ((frame-1 (%dashboard-screen "warming" "parse, render"))
         (frame-2 (%dashboard-screen "ready" "parse, render, io"))
         (frame-3 (%dashboard-screen "ready" "parse, render, io"))
         (cursor-1 (cl-tty-kit:make-cursor :x 14 :y 2 :visible nil))
         (cursor-2 (cl-tty-kit:make-cursor :x 22 :y 3))
         (cursor-3 (cl-tty-kit:make-cursor :x 15 :y 4)))
    (cl-tty-kit:screen-write-string frame-3 0 4 "press q to quit")
    (cl-tty-kit:with-terminal-session-output (stream :stream stream)
      (write-string (cl-tty-kit:render-frame frame-1 cursor-1) stream)
      (write-string (cl-tty-kit:render-frame-diff frame-2 frame-1 cursor-2) stream)
      (write-string (cl-tty-kit:render-frame-diff frame-3 frame-2 cursor-3) stream))))

(defun run-status-dashboard-example ()
  (format t "~A~%" (status-dashboard-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-status-dashboard-example))
