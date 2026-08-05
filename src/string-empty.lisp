(in-package #:cl-tty-kit)

(defmacro string-empty-p (value)
  `(let ((value ,value))
     (or (null value)
         (and (stringp value) (zerop (length value))))))
