(in-package #:cl-tty-kit)

(defstruct (cursor
    (:constructor %make-cursor (&key (x 0) (y 0) (visible t)))
    (:conc-name %cursor-)) "The cursor state for a rendered screen."
  (x 0 :type fixnum)
  (y 0 :type fixnum)
  (visible t :type boolean))

(defun %assert-cursor-coordinate (parameter value)
  (unless (typep value '(integer 0 *))
    (error
      'cursor-parameter-invalid
      :parameter
      parameter
      :value
      value
      :expected
      "a non-negative integer")))

(defun %assert-cursor-visibility (value)
  (unless (typep value 'boolean)
    (error
      'cursor-parameter-invalid
      :parameter
      :visible
      :value
      value
      :expected
      "a boolean")))

(defun %validated-cursor-coordinate (parameter value)
  (%assert-cursor-coordinate parameter value)
  value)

(defun %set-cursor-x (cursor value)
  (setf (%cursor-x cursor) (%validated-cursor-coordinate :x value)))

(defun %set-cursor-y (cursor value)
  (setf (%cursor-y cursor) (%validated-cursor-coordinate :y value)))

(defun %set-cursor-visible (cursor value)
  (%assert-cursor-visibility value)
  (setf (%cursor-visible cursor) value))

(setf (documentation 'cursor-x 'function) "Return the X coordinate of CURSOR.")

(setf (documentation 'cursor-y 'function) "Return the Y coordinate of CURSOR.")

(defun cursor-x (cursor)
  "Return the X coordinate of CURSOR."
  (%cursor-x cursor))

(defun cursor-y (cursor)
  "Return the Y coordinate of CURSOR."
  (%cursor-y cursor))

(progn
  (defmacro define-cursor-setters (&rest specs)
    `(progn
      ,@(mapcar
        (lambda (spec)
          `(defsetf ,(first spec) (cursor)
            (value)
            ,(second spec)))
        specs)))
  (define-cursor-setters
    (cursor-x `(%set-cursor-x ,cursor ,value))
    (cursor-y `(%set-cursor-y ,cursor ,value))
    (cursor-visible-p `(%set-cursor-visible ,cursor ,value))))

