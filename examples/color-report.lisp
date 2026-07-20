(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun %color-report-gradient (screen)
  "Paint a blue-to-red gradient bar across the panel's second interior row."
  (loop for rgb in (cl-tty-kit:color-gradient '(0 0 255) '(255 0 0) 36)
        for x from 2
        do (cl-tty-kit:screen-put-cell
            screen x 2 (code-char #x2588)
            :style (cl-tty-kit:make-style
                    (cl-tty-kit:style-fg (apply #'cl-tty-kit:rgb-to-256 rgb))))))

(defun %color-report-table (screen)
  "Write a name / 256-index / luminance table for the named colors."
  (let* ((rows (loop for name in '(:red :green :blue :yellow :cyan :magenta)
                     for index = (cl-tty-kit:named-color name)
                     for rgb = (multiple-value-list
                                (cl-tty-kit:color-256-to-rgb index))
                     collect (list (string-downcase (symbol-name name))
                                   (princ-to-string index)
                                   (princ-to-string
                                    (apply #'cl-tty-kit:color-luminance rgb)))))
         (lines (cl-tty-kit:format-table (cons '("name" "idx" "lum") rows)
                                         :aligns '(:left :right :right))))
    (cl-tty-kit:screen-write-lines screen 2 4 lines)))

(defun color-report-example ()
  "Render a color panel: a gradient bar plus a named-color/index/luminance table."
  (let ((screen (cl-tty-kit:make-screen 40 12)))
    (cl-tty-kit:screen-draw-box screen 0 0 40 12 :border :rounded
                                :title " Colors "
                                :title-style (cl-tty-kit:make-style :bold))
    (%color-report-gradient screen)
    (%color-report-table screen)
    (cl-tty-kit:render-screen screen)))

(defun run-color-report-example ()
  (format t "~A~%" (color-report-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-color-report-example))
