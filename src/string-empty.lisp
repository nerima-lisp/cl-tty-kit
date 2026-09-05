(in-package #:cl-tty-kit)

(defun string-empty-p (value)
  (or (null value)
      (and (stringp value) (zerop (length value)))))
