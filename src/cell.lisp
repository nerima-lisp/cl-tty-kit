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

(defun %assert-cell-character (char)
  (unless (characterp char)
    (error "Cell character must be a character, got ~S." char))
  char)

(defun %assert-cell (cell)
  (unless (cell-p cell)
    (error "Expected a CELL, got ~S." cell))
  cell)

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

(defun style-underline-color (first &optional second third)
  "Return a validated underline-color style entry (SGR 58)."
  (%style-color :underline-color first second third))

(setf (documentation 'style-underline-color 'function)
      "Return an underline-color style entry, (:UNDERLINE-COLOR INDEX) or
(:UNDERLINE-COLOR R G B), coloring the underline independently of the text (SGR
58) on terminals that support it.")

(defparameter +named-colors+
  '((:black . 0)
    (:red . 1)
    (:green . 2)
    (:yellow . 3)
    (:blue . 4)
    (:magenta . 5)
    (:cyan . 6)
    (:white . 7)
    (:bright-black . 8)
    (:gray . 8)
    (:grey . 8)
    (:bright-red . 9)
    (:bright-green . 10)
    (:bright-yellow . 11)
    (:bright-blue . 12)
    (:bright-magenta . 13)
    (:bright-cyan . 14)
    (:bright-white . 15))
  "Maps the sixteen standard ANSI color names (plus :GRAY/:GREY aliases for
:BRIGHT-BLACK) to their palette indices.")

(defun named-color (name)
  "Return the 0-15 palette index for the standard ANSI color NAME.
NAME is a keyword such as :RED, :BRIGHT-CYAN, or :GRAY. The result is an index
suitable for STYLE-FG or STYLE-BG, so (STYLE-FG (NAMED-COLOR :BRIGHT-RED)) reads
more clearly than the bare integer. An unknown NAME signals an error."
  (or (cdr (assoc name +named-colors+))
      (error "Unknown color name ~S; expected one of ~S."
             name
             (mapcar #'car +named-colors+))))

(defun %color-style-item-p (item)
  (and (consp item)
       (member (first item) '(:fg :bg :underline-color) :test #'eq)))

(defun %proper-style-list-p (value)
  (loop for rest = value then (cdr rest)
        while (consp rest)
        finally (return (null rest))))

(defun %cell-style-items (style)
  (cond
    ((null style) nil)
    ((%color-style-item-p style) (list style))
    ((%proper-style-list-p style) style)
    (t (list style))))

(defun %valid-color-byte-p (value)
  (typep value '(integer 0 255)))

(defun %normalize-color-style-item (item)
  (when (%color-style-item-p item)
    (let ((channel (first item))
          (payload (rest item)))
      (when (%proper-style-list-p payload)
        (cond
          ((and (= (length payload) 1)
                (%valid-color-byte-p (first payload)))
           (list channel (first payload)))
          ((and (= (length payload) 3)
                (every #'%valid-color-byte-p payload))
           (list* channel payload))
          (t nil))))))

(defun %normalize-cell-style (style)
  (let* ((items (%cell-style-items style))
         (modifiers (normalize-modifiers items))
        (foreground nil)
        (background nil)
        (underline nil))
    (dolist (item items)
      (let ((color (%normalize-color-style-item item)))
        (when color
          (case (first color)
            (:fg (setf foreground color))
            (:bg (setf background color))
            (:underline-color (setf underline color))))))
    (append modifiers
            (when foreground (list foreground))
            (when background (list background))
            (when underline (list underline)))))

(defun make-style (&rest items)
  "Return a normalized style list from modifier keywords and color entries."
  (copy-list (%normalize-cell-style items)))

(setf (documentation 'make-style 'function)
      "Return a normalized style list with deduplicated modifiers and the last valid fg/bg entries.")

(defun style-merge (base override)
  "Return a normalized style combining BASE with OVERRIDE, OVERRIDE winning.
Modifier keywords from both are unioned; OVERRIDE's foreground/background replace
BASE's when present, otherwise BASE's are kept. Each argument is any style value
accepted by MAKE-STYLE (a normalized list, a bare color entry, or NIL). Layering
a highlight over a base style is (STYLE-MERGE base-style (MAKE-STYLE :REVERSE))."
  (copy-list (%normalize-cell-style
              (append (%normalize-cell-style base)
                      (%normalize-cell-style override)))))

(defun make-cell (&key (char #\Space) style)
  "Create a CELL, normalizing any supplied style list."
  (%make-cell :char (%assert-cell-character char)
              :style (and style (copy-list (%normalize-cell-style style)))))

(defun %blank-cell ()
  (make-cell))

(defun copy-cell (cell)
  "Return a fresh copy of CELL."
  (let ((cell (%assert-cell cell)))
    (make-cell :char (cell-char cell)
               :style (cell-style cell))))
