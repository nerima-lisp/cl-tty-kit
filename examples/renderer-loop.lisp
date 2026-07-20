(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun %draw-frame (renderer label ratio)
  "Redraw the renderer's back buffer for one frame of the loop."
  (let ((screen (cl-tty-kit:renderer-screen renderer))
        (bounds (cl-tty-kit:make-rect :width (cl-tty-kit:renderer-width renderer)
                                      :height (cl-tty-kit:renderer-height renderer))))
    (cl-tty-kit:screen-clear screen)
    (cl-tty-kit:screen-draw-box screen 0 0
                                (cl-tty-kit:renderer-width renderer)
                                (cl-tty-kit:renderer-height renderer)
                                :border :rounded)
    (let ((inner (cl-tty-kit:rect-inset bounds :all 1)))
      (cl-tty-kit:screen-write-aligned screen inner label
                                       :align :center :vertical :top
                                       :style (cl-tty-kit:make-style :bold))
      (cl-tty-kit:screen-write-string
       screen (cl-tty-kit:rect-x inner) (+ 1 (cl-tty-kit:rect-y inner))
       (cl-tty-kit:format-progress-bar ratio (cl-tty-kit:rect-width inner))
       :style (cl-tty-kit:make-style
               (cl-tty-kit:style-fg (cl-tty-kit:named-color :bright-green)))))))

(defun renderer-loop-example ()
  "Drive a double-buffered renderer over two frames, returning the full first
paint concatenated with the diff-only second update."
  (let ((renderer (cl-tty-kit:make-renderer 24 4)))
    (with-output-to-string (out)
      ;; Frame 1: nothing on screen yet, so this is a full paint.
      (%draw-frame renderer "loading" 0.25)
      (cl-tty-kit:renderer-render renderer :stream out)
      ;; Frame 2: only the label and the grown bar differ, so the renderer
      ;; emits just those cells.
      (%draw-frame renderer "ready" 0.80)
      (cl-tty-kit:renderer-render renderer :stream out))))

(defun run-renderer-loop-example ()
  (format t "~A~%" (renderer-loop-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-renderer-loop-example))
