(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun boxed-panel-example ()
  "Compose a rounded panel: a titled border framing padded, colored fields."
  (let ((screen (cl-tty-kit:make-screen 24 5)))
    (cl-tty-kit:screen-draw-box screen 0 0 24 5 :border :rounded)
    ;; A title punched into the top border.
    (cl-tty-kit:screen-write-string screen 2 0 " Status "
                                    :style (cl-tty-kit:make-style :bold))
    ;; A left label and a right-aligned, colored value on the same row.
    (cl-tty-kit:screen-write-string screen 2 2
                                    (cl-tty-kit:pad-string "state:" 8))
    (cl-tty-kit:screen-write-string
     screen 10 2
     (cl-tty-kit:pad-string "ready" 12 :align :right)
     :style (cl-tty-kit:make-style
             :bold
             (cl-tty-kit:style-fg (cl-tty-kit:named-color :bright-green))))
    ;; A note clipped to the interior width with an ellipsis.
    (cl-tty-kit:screen-write-string
     screen 2 3
     (cl-tty-kit:truncate-string "note: streaming decode is live and buffered"
                                 20 :ellipsis "..."))
    (cl-tty-kit:render-screen screen)))

(defun run-boxed-panel-example ()
  (format t "~A~%" (boxed-panel-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-boxed-panel-example))
