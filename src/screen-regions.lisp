(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Bulk and region operations on SCREEN
;;;
;;; Everything here composes the single-cell primitives in screen.lisp
;;; (SCREEN-CELL, SCREEN-PUT-CELL) into whole-string, rectangle, and
;;; whole-grid operations: writing text, filling regions, scrolling,
;;; cropping, and compositing one screen onto another.
;;; --------------------------------------------------------------------------

(defun screen-write-string (screen x y string
                            &key style (start 0) (end nil end-supplied-p))
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
  (%assert-screen screen)
  (let* ((end (if end-supplied-p
                  end
                  (and (stringp string) (length string))))
         (run-length (progn
                       (%assert-string-bounds string start end)
                       (- end start))))
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

(defun screen-fill (screen value &key (style nil style-supplied-p))
  "Fill every cell of SCREEN with VALUE, returning SCREEN.
VALUE is a CELL template or a character; STYLE overrides its style when supplied.
This is SCREEN-FILL-RECT applied to the whole grid, so an empty screen is a
no-op."
  (%assert-screen screen)
  (if style-supplied-p
      (screen-fill-rect screen 0 0 (screen-width screen) (screen-height screen)
                        value :style style)
      (screen-fill-rect screen 0 0 (screen-width screen) (screen-height screen)
                        value))
  screen)

(defun screen-copy (screen)
  "Return a deep copy of SCREEN with the same dimensions and independent cells.
Mutating the copy -- or the original -- never affects the other, so a copy makes
a natural previous-frame snapshot for RENDER-DIFF."
  (%assert-screen screen)
  (let* ((source (screen-cells screen))
         (cells (make-array (length source))))
    (dotimes (index (length source))
      (setf (aref cells index) (copy-cell (aref source index))))
    (%make-screen :width (screen-width screen)
                  :height (screen-height screen)
                  :cells cells)))

(defun screen-row-string (screen y &key (start 0) (end nil end-supplied-p))
  "Return the characters stored in row Y of SCREEN between columns START and END.
A double-width glyph appears once followed by the blank spacer cell that
SCREEN-WRITE-STRING writes after it, matching the grid's column layout. An
out-of-range row or column span signals SCREEN-INDEX-OUT-OF-BOUNDS."
  (%assert-screen screen)
  (let ((end (if end-supplied-p end (screen-width screen))))
    (unless (and (integerp y)
                 (integerp start)
                 (integerp end)
                 (<= 0 y) (< y (screen-height screen))
                 (<= 0 start) (<= start end) (<= end (screen-width screen)))
      (error 'screen-index-out-of-bounds
             :screen screen
             :x start
             :y y
             :width (screen-width screen)
             :height (screen-height screen)))
    (with-output-to-string (out)
      (loop for x from start below end
            do (write-char (cell-char (screen-cell screen x y)) out)))))

(defun screen-scroll (screen count &key fill)
  "Scroll SCREEN vertically by COUNT rows in place, returning SCREEN.
A positive COUNT moves content up, exposing new rows at the bottom; a negative
COUNT moves it down, exposing new rows at the top. Exposed rows are filled with
independent copies of FILL, a CELL template, a character, or NIL for a blank
  cell. A |COUNT| of at least the height clears the whole screen."
  (%assert-screen screen)
  (%assert (integerp count) "Screen scroll COUNT ~S must be an integer." count)
  (let ((width (screen-width screen))
        (height (screen-height screen)))
    (when (and (plusp width) (plusp height) (/= count 0))
      (let ((shift (max (- height) (min height count)))
            (fill-cell (%coerce-cell-template fill)))
        (flet ((fill-or-copy (x y source)
                 (setf (screen-cell screen x y)
                       (if (and (<= 0 source) (< source height))
                           (screen-cell screen x source)
                           (copy-cell fill-cell)))))
          (if (plusp shift)
              ;; Move up: write each row from the one below, top to bottom, so a
              ;; source row is still original when it is read.
              (loop for y from 0 below height do
                (loop for x from 0 below width do
                  (fill-or-copy x y (+ y shift))))
              ;; Move down: write bottom to top for the same reason.
              (loop for y from (1- height) downto 0 do
                (loop for x from 0 below width do
                  (fill-or-copy x y (+ y shift)))))))))
  screen)

(defun screen-crop (screen rect)
  "Return a new SCREEN holding the RECT region of SCREEN as independent cells.
RECT is clipped to the source bounds, so a rectangle running off an edge yields
  only the overlapping cells and a fully off-screen rectangle yields a 0x0 screen.
This is the read counterpart to SCREEN-BLIT: extract a panel, inspect or reuse it."
  (%assert-screen screen)
  (%assert-screen-rect rect)
  (let* ((start-x (max 0 (rect-x rect)))
         (start-y (max 0 (rect-y rect)))
         (end-x (min (screen-width screen) (rect-right rect)))
         (end-y (min (screen-height screen) (rect-bottom rect)))
         (width (max 0 (- end-x start-x)))
         (height (max 0 (- end-y start-y)))
         (result (make-screen width height)))
    (loop for row from 0 below height
          do (loop for column from 0 below width
                   do (setf (screen-cell result column row)
                            (screen-cell screen (+ start-x column) (+ start-y row)))))
    result))

(defun screen-blit (dest src &key (dest-x 0) (dest-y 0) (src-x 0) (src-y 0)
                                  (width nil width-supplied-p)
                                  (height nil height-supplied-p))
  "Copy a WIDTH by HEIGHT region of SRC at (SRC-X, SRC-Y) into DEST at
(DEST-X, DEST-Y), returning DEST. Cells are copied independently. The region is
clipped to the parts that fall inside both SRC and DEST, so a blit that runs off
an edge copies only its visible overlap instead of signaling. This is the
primitive for compositing sub-screens (panels, widgets) onto a frame."
  (%assert-screen dest)
  (%assert-screen src)
  (%assert-screen-offset :dest-x dest-x)
  (%assert-screen-offset :dest-y dest-y)
  (%assert-screen-offset :src-x src-x)
  (%assert-screen-offset :src-y src-y)
  (let ((width (if width-supplied-p width (screen-width src)))
        (height (if height-supplied-p height (screen-height src))))
    (%assert-screen-dimensions width height)
    (loop for row from 0 below height
          for sy = (+ src-y row)
          for dy = (+ dest-y row)
          when (and (integerp sy)
                    (integerp dy)
                    (<= 0 sy) (< sy (screen-height src))
                    (<= 0 dy) (< dy (screen-height dest)))
            do (loop for col from 0 below width
                     for sx = (+ src-x col)
                     for dx = (+ dest-x col)
                     when (and (integerp sx)
                               (integerp dx)
                               (<= 0 sx) (< sx (screen-width src))
                               (<= 0 dx) (< dx (screen-width dest)))
                       do (setf (screen-cell dest dx dy)
                                (screen-cell src sx sy)))))
  dest)
