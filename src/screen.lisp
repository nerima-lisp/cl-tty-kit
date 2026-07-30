(in-package #:cl-tty-kit)

(defstruct (screen (:constructor %make-screen)) "A fixed-size two-dimensional grid of CELL objects." (width 0 :type fixnum) (height 0 :type fixnum) (cells #() :type simple-vector) (generation 0 :type fixnum) (row-generations #() :type (simple-array fixnum (*))))

(setf (documentation 'screen-width 'function) "Return the width of SCREEN.")

(setf (documentation 'screen-height 'function) "Return the height of SCREEN.")

(defun %screen-touch (screen &optional (start-y 0) (end-y (screen-height screen))) (let ((generation (the fixnum (1+ (screen-generation screen))))) (setf (screen-generation screen) generation) (fill (screen-row-generations screen) generation :start start-y :end end-y)) screen)

(defun %assert-screen (screen)
  (unless (screen-p screen)
    (error "Expected a SCREEN, got ~S." screen))
  screen)

(defun %assert-screen-rect (rect)
  (unless (rect-p rect)
    (error "Expected a RECT, got ~S." rect))
  rect)

(defun %assert-cell-template (value)
  (unless (or (null value) (cell-p value) (characterp value))
    (error "Cell template ~S must be NIL, a CELL, or a character." value))
  value)

(defun %assert-cell-value (value)
  (unless (or (cell-p value) (characterp value))
    (error "Cell value ~S must be a CELL or a character." value))
  value)

(defun %coerce-cell-template (value)
  (%assert-cell-template value)
  (cond
    ((cell-p value) value)
    ((characterp value) (make-cell :char value))
    (t (make-cell))))

(defun %coerce-cell-value (value style style-supplied-p)
  (%assert-cell-value value)
  (cond
    ((cell-p value)
     (if style-supplied-p
         (make-cell :char (cell-char value)
                    :style (%coerce-cell-style style))
         value))
    (t (make-cell :char value :style style))))

(defun %coerce-cell-style (style) (and style (copy-tree (%normalize-cell-style style))))

(defun %assert-screen-dimensions (width height)
  ;; Reject not just negatives but any dimension whose cell grid could not be
  ;; allocated: each side must be a non-negative fixnum and the total cell
  ;; count must stay within ARRAY-TOTAL-SIZE-LIMIT. Without the fixnum/product
  ;; bound a huge-but-non-negative dimension slips past validation and then
  ;; raises a raw TYPE-ERROR (fixnum slot store) or MAKE-ARRAY error instead of
  ;; the documented SCREEN-DIMENSIONS-INVALID.
  (%assert (and (typep width '(and fixnum unsigned-byte))
               (typep height '(and fixnum unsigned-byte))
               (< (* width height) array-total-size-limit)) 'screen-dimensions-invalid
           :width width
           :height height))

(defun %screen-index (screen x y)
  (+ (* y (screen-width screen)) x))

(defun %assert-screen-bounds (screen x y)
  (%assert-screen screen)
  (%assert
    (and
      (integerp x)
      (integerp y)
      (<= 0 x)
      (< x (screen-width screen))
      (<= 0 y)
      (< y (screen-height screen)))
    'screen-index-out-of-bounds
    :screen
    screen
    :x
    x
    :y
    y
    :width
    (screen-width screen)
    :height
    (screen-height screen)))

(defun %assert-screen-offset (name value)
  (unless (integerp value)
    (error "Screen ~A ~S must be an integer." name value))
  value)

(defun %assert-screen-rect-bounds (screen x y width height)
  (%assert-screen screen)
  (%assert-screen-dimensions width height)
  (when (and (plusp width) (plusp height))
    (%assert-screen-bounds screen x y)
    (%assert-screen-bounds screen (+ x (1- width)) (+ y (1- height)))))

(defun %assert-string-bounds (string start end)
  (unless (stringp string)
    (error "Expected a string, got ~S." string))
  (%assert
    (and
      (integerp start)
      (integerp end)
      (<= 0 start)
      (<= start end)
      (<= end (length string)))
    "Invalid string bounds START=~S END=~S for string of length ~D."
    start
    end
    (length string)))

(defun %screen-vector (width height &optional (cell (%blank-cell)))
  (let* ((size (* width height))
         (template (%coerce-cell-template cell)))
    (make-array size :initial-element template)))

(defun screen-cell (screen x y)
  "Return the CELL at X and Y in SCREEN."
  (%assert-screen-bounds screen x y)
  (aref (screen-cells screen) (%screen-index screen x y)))

(defun (setf screen-cell) (value screen x y) (%assert-screen-bounds screen x y) (setf (aref (screen-cells screen) (%screen-index screen x y)) (%coerce-cell-value value nil nil)) (%screen-touch screen y (1+ y)))

(defun screen-put-cell (screen x y value &key (style nil style-supplied-p)) "Write VALUE into SCREEN at X and Y, optionally overriding style." (%assert-screen-bounds screen x y) (setf (aref (screen-cells screen) (%screen-index screen x y)) (%coerce-cell-value value style style-supplied-p)) (%screen-touch screen y (1+ y)) screen)

(defun make-screen (width height &key initial-cell) "Create a WIDTH by HEIGHT SCREEN initialized from INITIAL-CELL. INITIAL-CELL may be a CELL template, a character, or NIL for a blank cell. Screen mutation APIs replace cell values, so equal initial cells are shared safely. Invalid dimensions signal SCREEN-DIMENSIONS-INVALID." (%assert-screen-dimensions width height) (%make-screen :width width :height height :cells (%screen-vector width height initial-cell) :row-generations (make-array height :element-type (quote fixnum) :initial-element 0)))

(defun screen-clear (screen &key cell) "Reset every cell in SCREEN to CELL, returning SCREEN. CELL may be a CELL template, a character, or NIL for a blank cell." (%assert-screen screen) (fill (screen-cells screen) (%coerce-cell-template cell)) (%screen-touch screen) screen)

(defun screen-resize (screen width height &key initial-cell) "Resize SCREEN to WIDTH by HEIGHT in place, returning SCREEN. The overlapping top-left region is preserved and newly exposed cells use INITIAL-CELL." (%assert-screen-dimensions width height) (%assert-screen screen) (let* ((old-width (screen-width screen)) (old-height (screen-height screen)) (old-cells (screen-cells screen)) (new-cells (make-array (* width height) :initial-element (%coerce-cell-template initial-cell) :element-type (array-element-type old-cells))) (new-row-generations (make-array height :element-type (quote fixnum) :initial-element 0))) (loop for y fixnum below (min old-height height) do (replace new-cells old-cells :start1 (* y width) :start2 (* y old-width) :end2 (+ (* y old-width) (min old-width width)))) (setf (screen-width screen) width (screen-height screen) height (screen-cells screen) new-cells (screen-row-generations screen) new-row-generations) (%screen-touch screen) screen))
