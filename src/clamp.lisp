(in-package #:cl-tty-kit)

(defun clamp (value min max)
  (if (> min max)
      min
      (min max (max min value))))

(defmacro ensure-list* (value)
  `(let ((value ,value))
     (if (listp value) value (list value))))

(defun %proper-list-p (value)
  "Return true when VALUE is a proper (non-dotted, finite) list."
  (loop for rest = value then (cdr rest)
        while (consp rest)
        finally (return (null rest))))
