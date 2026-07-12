(in-package #:cl-tty-kit)

(defstruct (cell (:constructor %make-cell (&key (char #\Space) style))
                 (:copier nil))
  "A single screen cell with a character and optional style list."
  (char #\Space :type character)
  (style nil :type list))

(setf (documentation 'cell-char 'function)
      "Return the character stored in CELL.")

(setf (documentation 'cell-style 'function)
      "Return the normalized style list stored in CELL.")

(defun %style-color (channel first &optional second third)
  (cond
    ((and (null second) (null third))
     (unless (%valid-color-byte-p first)
       (error "Invalid ~A color index ~S; expected an integer in [0, 255]."
              channel
              first))
     (list channel first))
    ((and second third)
     (unless (every #'%valid-color-byte-p (list first second third))
       (error "Invalid ~A RGB color ~S; expected integers in [0, 255]."
              channel
              (list first second third)))
     (list channel first second third))
    (t
     (error "~A color constructors accept either INDEX or RED GREEN BLUE."
            channel))))

(defun style-fg (first &optional second third)
  "Return a validated foreground style entry."
  (%style-color :fg first second third))

(setf (documentation 'style-fg 'function)
      "Return a foreground style entry of the form (:FG INDEX) or (:FG R G B).")

(defun style-bg (first &optional second third)
  "Return a validated background style entry."
  (%style-color :bg first second third))

(setf (documentation 'style-bg 'function)
      "Return a background style entry of the form (:BG INDEX) or (:BG R G B).")

(defun %color-style-item-p (item)
  (and (consp item)
       (member (first item) '(:fg :bg) :test #'eq)))

(defun %cell-style-items (style)
  (cond
    ((null style) nil)
    ((%color-style-item-p style) (list style))
    (t (ensure-list* style))))

(defun %valid-color-byte-p (value)
  (typep value '(integer 0 255)))

(defun %normalize-color-style-item (item)
  (when (%color-style-item-p item)
    (let ((channel (first item))
          (payload (rest item)))
      (cond
        ((and (= (length payload) 1)
              (%valid-color-byte-p (first payload)))
         (list channel (first payload)))
        ((and (= (length payload) 3)
              (every #'%valid-color-byte-p payload))
         (list* channel payload))
        (t nil)))))

(defun %normalize-cell-style (style)
  (let ((modifiers (normalize-modifiers style))
        (foreground nil)
        (background nil))
    (dolist (item (%cell-style-items style))
      (let ((color (%normalize-color-style-item item)))
        (when color
          (case (first color)
            (:fg (setf foreground color))
            (:bg (setf background color))))))
    (append modifiers
            (when foreground (list foreground))
            (when background (list background)))))

(defun make-style (&rest items)
  "Return a normalized style list from modifier keywords and color entries."
  (copy-list (%normalize-cell-style items)))

(setf (documentation 'make-style 'function)
      "Return a normalized style list with deduplicated modifiers and the last valid fg/bg entries.")

(defun make-cell (&key (char #\Space) style)
  "Create a CELL, normalizing any supplied style list."
  (%make-cell :char char
              :style (and style (copy-list (%normalize-cell-style style)))))

(defun %blank-cell ()
  (make-cell))

(defun copy-cell (cell)
  "Return a fresh copy of CELL."
  (make-cell :char (cell-char cell)
             :style (cell-style cell)))
