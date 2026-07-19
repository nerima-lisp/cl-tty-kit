(in-package #:cl-tty-kit)

(defstruct (cursor
    (:constructor %make-cursor (&key (x 0) (y 0) (visible t)))
    (:conc-name %cursor-)) "The cursor state for a rendered screen."
  (x 0 :type (integer 0))
  (y 0 :type (integer 0))
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

(defun cursor-visible-p (cursor)
  "Return true when CURSOR is currently visible."
  (%cursor-visible cursor))

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

(defun make-cursor (&key (x 0) (y 0) (visible t))
  "Create a CURSOR at X and Y with the given VISIBLE flag.
X and Y must be non-negative integers and VISIBLE must be a boolean;
otherwise CURSOR-PARAMETER-INVALID is signaled."
  (%assert-cursor-coordinate :x x)
  (%assert-cursor-coordinate :y y)
  (%assert-cursor-visibility visible)
  (%make-cursor :x x :y y :visible visible))

(defun move-cursor (cursor x y &key width height)
  "Move CURSOR to X and Y, returning CURSOR.
X and Y must be non-negative integers. When WIDTH or HEIGHT is supplied it
must also be a non-negative integer and the matching coordinate is clamped
into [0, WIDTH-1] / [0, HEIGHT-1], collapsing to 0 for a zero extent."
  (%assert-cursor-coordinate :x x)
  (%assert-cursor-coordinate :y y)
  (when width (%assert-cursor-coordinate :width width))
  (when height (%assert-cursor-coordinate :height height))
  (setf (%cursor-x cursor) (if width (clamp x 0 (1- width)) x))
  (setf (%cursor-y cursor) (if height (clamp y 0 (1- height)) y))
  cursor)

