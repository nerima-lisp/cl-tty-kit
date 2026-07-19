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
  (unless (and (typep width '(integer 0 *))
               (typep height '(integer 0 *)))
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
Returns SCREEN. An optional STYLE is applied to every written cell. A run that
would extend past the screen edge signals SCREEN-INDEX-OUT-OF-BOUNDS and leaves
SCREEN unchanged; an empty run is a no-op."
  (let ((run-length (- end start)))
    (when (plusp run-length)
      (%assert-screen-bounds screen x y)
      (%assert-screen-bounds screen (+ x (1- run-length)) y)
      (loop for offset from 0 below run-length
            do (screen-put-cell screen (+ x offset) y
                                (char string (+ start offset))
                                :style style))))
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

