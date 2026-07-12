(in-package #:cl-tty-kit)

(defun clamp (value min max)
  (if (> min max)
      min
      (min max (max min value))))

(defun ensure-list* (value)
  (if (listp value) value (list value)))
