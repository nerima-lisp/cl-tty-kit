(in-package #:cl-tty-kit)

(defparameter +style-sgr-keywords+
  '((:bold . "1")
    (:dim . "2")
    (:italic . "3")
    (:underline . "4")
    (:reverse . "7")))

(defun %keyword-style-sgr-codes (style)
  (let ((code (cdr (assoc style +style-sgr-keywords+))))
    (and code (list code))))

(defun %color-style-sgr-codes (style)
  (destructuring-bind (channel &rest values) style
    (let ((prefix (case channel
                    (:fg "38")
                    (:bg "48")
                    (otherwise nil))))
      (when prefix
        (case (length values)
          (1 (list prefix "5" (write-to-string (first values))))
          (3 (list prefix "2"
                   (write-to-string (first values))
                   (write-to-string (second values))
                   (write-to-string (third values))))
          (otherwise nil))))))

(defun %style-sgr-codes (style)
  (cond
    ((keywordp style)
     (%keyword-style-sgr-codes style))
    ((consp style)
     (%color-style-sgr-codes style))
    (t nil)))

(defun %supported-cell-style-codes (cell)
  (loop for style in (cell-style cell)
        append (%style-sgr-codes style)))

(defun %cell-style-sequence (cell)
  (let ((codes (%supported-cell-style-codes cell)))
    (when codes
      (format nil "~C[~{~A~^;~}m" +escape+ codes))))

(defun %cell-render-parts (cell)
  (let ((prefix (%cell-style-sequence cell))
        (char (string (cell-char cell))))
    (if prefix
        (list prefix char (ansi-reset-style))
        (list char))))

(defun %write-cell (cell stream)
  (dolist (part (%cell-render-parts cell) stream)
    (write-string part stream)))

