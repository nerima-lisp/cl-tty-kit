(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun layout-panels-example ()
  "Split a frame into two bordered panels: a sparkline and a columns table."
  (let* ((screen (cl-tty-kit:make-screen 40 8))
         (root (cl-tty-kit:make-rect :width 40 :height 8)))
    (multiple-value-bind (left right)
        (cl-tty-kit:rect-split-horizontal root 20)
      (flet ((box (rect)
               (cl-tty-kit:screen-draw-box screen
                                           (cl-tty-kit:rect-x rect)
                                           (cl-tty-kit:rect-y rect)
                                           (cl-tty-kit:rect-width rect)
                                           (cl-tty-kit:rect-height rect)
                                           :border :single)))
        (box left)
        (box right)
        (let ((inner-left (cl-tty-kit:rect-inset left :all 1))
              (inner-right (cl-tty-kit:rect-inset right :all 1)))
          ;; Left panel: a labeled sparkline.
          (cl-tty-kit:screen-write-string screen
                                          (cl-tty-kit:rect-x inner-left)
                                          (cl-tty-kit:rect-y inner-left)
                                          "load"
                                          :style (cl-tty-kit:make-style :bold))
          (cl-tty-kit:screen-write-string
           screen
           (cl-tty-kit:rect-x inner-left)
           (+ 1 (cl-tty-kit:rect-y inner-left))
           (cl-tty-kit:format-sparkline '(1 3 2 5 4 7 6 8 5 3))
           :style (cl-tty-kit:make-style
                   (cl-tty-kit:style-fg (cl-tty-kit:named-color :bright-cyan))))
          ;; Right panel: an aligned columns row.
          (cl-tty-kit:screen-write-string screen
                                          (cl-tty-kit:rect-x inner-right)
                                          (cl-tty-kit:rect-y inner-right)
                                          "tasks"
                                          :style (cl-tty-kit:make-style :bold))
          (cl-tty-kit:screen-write-string
           screen
           (cl-tty-kit:rect-x inner-right)
           (+ 1 (cl-tty-kit:rect-y inner-right))
           (cl-tty-kit:format-columns '("build" "ok") '(10 6)
                                      :aligns '(:left :right))))))
    (cl-tty-kit:render-screen screen)))

(defun run-layout-panels-example ()
  (format t "~A~%" (layout-panels-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-layout-panels-example))
