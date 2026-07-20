(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun progress-dashboard-example ()
  "Compose a boxed dashboard: colored fractional progress bars and a columns row."
  (let ((screen (cl-tty-kit:make-screen 34 7)))
    (cl-tty-kit:screen-draw-box screen 0 0 34 7 :border :rounded)
    (cl-tty-kit:screen-write-string screen 2 0 " Build "
                                    :style (cl-tty-kit:make-style :bold))
    ;; Two labeled progress bars, each colored and sub-cell accurate.
    (cl-tty-kit:screen-write-string screen 2 2 "cpu")
    (cl-tty-kit:screen-write-string
     screen 6 2 (cl-tty-kit:format-progress-bar 0.62 24)
     :style (cl-tty-kit:make-style
             (cl-tty-kit:style-fg (cl-tty-kit:named-color :bright-green))))
    (cl-tty-kit:screen-write-string screen 2 3 "mem")
    (cl-tty-kit:screen-write-string
     screen 6 3 (cl-tty-kit:format-progress-bar 0.30 24)
     :style (cl-tty-kit:make-style
             (cl-tty-kit:style-fg (cl-tty-kit:named-color :bright-yellow))))
    ;; A right-aligned status column beneath a left-aligned label.
    (cl-tty-kit:screen-write-string
     screen 2 5
     (cl-tty-kit:format-columns '("task" "status") '(10 12)
                                :aligns '(:left :right)))
    (cl-tty-kit:render-screen screen)))

(defun run-progress-dashboard-example ()
  (format t "~A~%" (progress-dashboard-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-progress-dashboard-example))
