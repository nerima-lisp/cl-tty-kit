(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun terminal-session-example (&optional (stream *standard-output*))
  (let ((screen (cl-tty-kit:make-screen 18 3)))
    (cl-tty-kit:screen-write-string screen 0 0 "TTY" :style '(:bold))
    (cl-tty-kit:screen-write-string screen 4 0 "demo")
    (cl-tty-kit:screen-write-string screen 0 1 "Press")
    (cl-tty-kit:screen-write-string screen 6 1 "q to")
    (cl-tty-kit:screen-write-string screen 11 1 "exit")
    (cl-tty-kit:with-terminal-session (session :stream stream
                                               :bracketed-paste t
                                               :keyboard-enhancements 1)
      (write-string (cl-tty-kit:render-screen screen) session))
    stream))

(defun run-terminal-session-example ()
  (terminal-session-example))

(when *cl-tty-kit-run-example-on-load*
  (run-terminal-session-example))
