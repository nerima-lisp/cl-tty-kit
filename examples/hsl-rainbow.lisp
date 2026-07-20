(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun hsl-rainbow-example ()
  "Sweep the HSL hue circle across a panel, one colored cell per hue step."
  (let ((screen (cl-tty-kit:make-screen 40 3)))
    (cl-tty-kit:screen-draw-box screen 0 0 40 3 :border :rounded
                                :title " HSL hue "
                                :title-style (cl-tty-kit:make-style :bold))
    ;; 38 interior columns walk hue 0..360 at full saturation, mid lightness.
    (loop for x from 1 below 39
          for hue = (round (* 360 (/ (- x 1) 37)))
          do (multiple-value-bind (r g b) (cl-tty-kit:hsl-to-rgb hue 100 50)
               (cl-tty-kit:screen-put-cell
                screen x 1 (code-char #x2588)
                :style (cl-tty-kit:make-style
                        (cl-tty-kit:style-fg (cl-tty-kit:rgb-to-256 r g b))))))
    (cl-tty-kit:render-screen screen)))

(defun run-hsl-rainbow-example ()
  (format t "~A~%" (hsl-rainbow-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-hsl-rainbow-example))
