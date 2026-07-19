(in-package #:cl-tty-kit)

(defstruct (screen (:constructor %make-screen))
  "A fixed-size two-dimensional grid of CELL objects."
  (width 0 :type fixnum)
  (height 0 :type fixnum)
  (cells #() :type simple-vector))

(setf (documentation 'screen-width 'function)
      "Return the width of SCREEN.")

(setf (documentation 'screen-height 'function)
      "Return the height of SCREEN.")

(setf (documentation 'screen-cells 'function)
      "Return the backing vector of cells for SCREEN.")

(defun %coerce-cell-template (value)
  (etypecase value
    (cell (copy-cell value))
    (character (make-cell :char value))
    (null (make-cell))))

(defun %coerce-cell-style (style)
  (and style (copy-list (%normalize-cell-style style))))

(defun %assert-screen-dimensions (width height)
  ;; Reject not just negatives but any dimension whose cell grid could not be
  ;; allocated: each side must be a non-negative fixnum and the total cell
  ;; count must stay within ARRAY-TOTAL-SIZE-LIMIT. Without the fixnum/product
  ;; bound a huge-but-non-negative dimension slips past validation and then
  ;; raises a raw TYPE-ERROR (fixnum slot store) or MAKE-ARRAY error instead of
  ;; the documented SCREEN-DIMENSIONS-INVALID.
  (unless (and (typep width '(and fixnum unsigned-byte))
               (typep height '(and fixnum unsigned-byte))
               (< (* width height) array-total-size-limit))
    (error 'screen-dimensions-invalid
           :width width
           :height height)))

(defun %screen-index (screen x y)
  (+ (* y (screen-width screen)) x))

(defun %assert-screen-bounds (screen x y)
  (unless (and (<= 0 x) (< x (screen-width screen))
               (<= 0 y) (< y (screen-height screen)))
    (error 'screen-index-out-of-bounds
           :screen screen
           :x x
           :y y
           :width (screen-width screen)
           :height (screen-height screen))))

(defun %assert-screen-rect-bounds (screen x y width height)
  (%assert-screen-dimensions width height)
  (when (and (plusp width) (plusp height))
    (%assert-screen-bounds screen x y)
    (%assert-screen-bounds screen (+ x (1- width)) (+ y (1- height)))))

(defun %screen-vector (width height &optional (cell (%blank-cell)))
  (make-array (* width height)
              :initial-contents
              (loop repeat (* width height)
                    collect (%coerce-cell-template cell))))

(defun screen-cell (screen x y)
  "Return the CELL at X and Y in SCREEN."
  (%assert-screen-bounds screen x y)
  (aref (screen-cells screen) (%screen-index screen x y)))

(defun (setf screen-cell) (value screen x y)
  (%assert-screen-bounds screen x y)
  (setf (aref (screen-cells screen) (%screen-index screen x y))
        (etypecase value
          (cell (copy-cell value))
          (character (make-cell :char value)))))

(defun screen-put-cell (screen x y value &key (style nil style-supplied-p))
  "Write VALUE into SCREEN at X and Y, optionally overriding style."
  (setf (screen-cell screen x y)
        (etypecase value
          (cell (make-cell :char (cell-char value)
                           :style (if style-supplied-p
                                      (%coerce-cell-style style)
                                      (cell-style value))))
          (character (make-cell :char value :style style))))
  screen)

(defun make-screen (width height &key initial-cell)
  "Create a WIDTH by HEIGHT SCREEN.
Each cell is an independent copy of INITIAL-CELL, which may be a CELL template,
a character, or NIL for a blank cell. Invalid dimensions signal
SCREEN-DIMENSIONS-INVALID."
  (%assert-screen-dimensions width height)
  (%make-screen :width width
                :height height
                :cells (%screen-vector width height initial-cell)))

(defun screen-clear (screen &key cell)
  "Reset every cell in SCREEN to an independent copy of CELL, returning SCREEN.
CELL may be a CELL template, a character, or NIL for a blank cell."
  (let ((cells (screen-cells screen)))
    (dotimes (index (length cells))
      (setf (aref cells index) (%coerce-cell-template cell))))
  screen)

(defun screen-resize (screen width height &key initial-cell)
  "Resize SCREEN to WIDTH by HEIGHT in place, returning SCREEN.
The overlapping top-left region is preserved and any newly exposed area is
filled with independent copies of INITIAL-CELL. Invalid dimensions signal
SCREEN-DIMENSIONS-INVALID."
  (%assert-screen-dimensions width height)
  (let ((old-width (screen-width screen))
        (old-height (screen-height screen))
        (old-cells (screen-cells screen))
        (new-cells (make-array (* width height))))
    (dotimes (y height)
      (dotimes (x width)
        (setf (aref new-cells (+ (* y width) x))
              (if (and (< x old-width) (< y old-height))
                  (copy-cell (aref old-cells (+ (* y old-width) x)))
                  (%coerce-cell-template initial-cell)))))
    (setf (screen-width screen) width
          (screen-height screen) height
          (screen-cells screen) new-cells))
  screen)

(defun screen-write-string (screen x y string
                            &key style (start 0) (end (length string)))
  "Write STRING (bounded by START and END) into SCREEN starting at X and Y.
Each character advances the column by its CHAR-WIDTH rather than by one cell
per character: a double-width character (CHAR-WIDTH 2, such as a CJK
ideograph) also fills the column immediately after it with a blank spacer
cell, so the grid's column count matches what a real terminal displays. A
zero-width character (CHAR-WIDTH 0, such as a combining mark) still consumes
its own column, since this function does not cluster it onto the previous
cell. Returns SCREEN. An optional STYLE is applied to every written cell,
including spacer cells. A run that would extend past the screen edge signals
SCREEN-INDEX-OUT-OF-BOUNDS and leaves SCREEN unchanged; an empty run is a
no-op."
  (let ((run-length (- end start)))
    (when (plusp run-length)
      (let ((total-width (loop for offset from start below end
                                sum (max 1 (char-width (char string offset))))))
        (%assert-screen-bounds screen x y)
        (%assert-screen-bounds screen (+ x (1- total-width)) y)
        (let ((column x))
          (loop for offset from start below end
                for char = (char string offset)
                for width = (char-width char)
                do (screen-put-cell screen column y char :style style)
                   (when (= width 2)
                     (screen-put-cell screen (1+ column) y #\Space :style style))
                   (incf column (max 1 width)))))))
  screen)

(defun screen-fill-rect (screen x y width height value &key (style nil style-supplied-p))
  "Fill the WIDTH by HEIGHT rectangle at X and Y in SCREEN with VALUE.
Returns SCREEN. VALUE may be a CELL template or a character and STYLE overrides
its style when supplied. A zero-width or zero-height rectangle is a no-op even
when its origin is off-screen; a positive rectangle that leaves the screen
signals SCREEN-INDEX-OUT-OF-BOUNDS and negative extents signal
SCREEN-DIMENSIONS-INVALID, both leaving SCREEN unchanged."
  (%assert-screen-rect-bounds screen x y width height)
  (when (and (plusp width) (plusp height))
    (loop for row from y below (+ y height)
          do (loop for col from x below (+ x width)
                   do (if style-supplied-p
                          (screen-put-cell screen col row value :style style)
                          (screen-put-cell screen col row value)))))
  screen)

