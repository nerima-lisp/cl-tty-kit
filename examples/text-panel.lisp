(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun text-panel-example ()
  "Frame a word-wrapped paragraph under an ellipsized title, all by display width."
  (let* ((screen (cl-tty-kit:make-screen 30 9))
         ;; A too-long title clipped to the border with a real ellipsis glyph.
         (title (cl-tty-kit:truncate-string " A rather long panel title here "
                                            22 :ellipsis (string (code-char #x2026))))
         (inner (cl-tty-kit:rect-inset (cl-tty-kit:make-rect :width 30 :height 9)
                                       :all 1)))
    (cl-tty-kit:screen-draw-box screen 0 0 30 9 :border :single
                                :title title
                                :title-style (cl-tty-kit:make-style :bold))
    ;; SCREEN-WRITE-WRAPPED word-wraps to the interior width via display columns.
    (cl-tty-kit:screen-write-wrapped
     screen (cl-tty-kit:rect-x inner) (cl-tty-kit:rect-y inner)
     (cl-tty-kit:rect-width inner)
     "cl-tty-kit wraps text by display width, so mixed ASCII and wide glyphs stay aligned.")
    (cl-tty-kit:render-screen screen)))

(defun run-text-panel-example ()
  (format t "~A~%" (text-panel-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-text-panel-example))
