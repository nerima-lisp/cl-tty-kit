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

(defun screen-fill (screen value &key (style nil style-supplied-p))
  "Fill every cell of SCREEN with VALUE, returning SCREEN.
VALUE is a CELL template or a character; STYLE overrides its style when supplied.
This is SCREEN-FILL-RECT applied to the whole grid, so an empty screen is a
no-op."
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
  (let* ((source (screen-cells screen))
         (cells (make-array (length source))))
    (dotimes (index (length source))
      (setf (aref cells index) (copy-cell (aref source index))))
    (%make-screen :width (screen-width screen)
                  :height (screen-height screen)
                  :cells cells)))

(defun screen-row-string (screen y &key (start 0) (end (screen-width screen)))
  "Return the characters stored in row Y of SCREEN between columns START and END.
A double-width glyph appears once followed by the blank spacer cell that
SCREEN-WRITE-STRING writes after it, matching the grid's column layout. An
out-of-range row or column span signals SCREEN-INDEX-OUT-OF-BOUNDS."
  (unless (and (<= 0 y) (< y (screen-height screen))
               (<= 0 start) (<= start end) (<= end (screen-width screen)))
    (error 'screen-index-out-of-bounds
           :screen screen
           :x start
           :y y
           :width (screen-width screen)
           :height (screen-height screen)))
  (with-output-to-string (out)
    (loop for x from start below end
          do (write-char (cell-char (screen-cell screen x y)) out))))

(defun screen-scroll (screen count &key fill)
  "Scroll SCREEN vertically by COUNT rows in place, returning SCREEN.
A positive COUNT moves content up, exposing new rows at the bottom; a negative
COUNT moves it down, exposing new rows at the top. Exposed rows are filled with
independent copies of FILL, a CELL template, a character, or NIL for a blank
cell. A |COUNT| of at least the height clears the whole screen."
  (let ((width (screen-width screen))
        (height (screen-height screen)))
    (when (and (plusp width) (plusp height) (/= count 0))
      (let ((shift (max (- height) (min height count))))
        (flet ((fill-or-copy (x y source)
                 (setf (screen-cell screen x y)
                       (if (and (<= 0 source) (< source height))
                           (screen-cell screen x source)
                           (%coerce-cell-template fill)))))
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
  (let* ((start-x (max 0 (rect-x rect)))
         (start-y (max 0 (rect-y rect)))
         (end-x (min (screen-width screen) (+ (rect-x rect) (rect-width rect))))
         (end-y (min (screen-height screen) (+ (rect-y rect) (rect-height rect))))
         (width (max 0 (- end-x start-x)))
         (height (max 0 (- end-y start-y)))
         (result (make-screen width height)))
    (loop for row from 0 below height
          do (loop for column from 0 below width
                   do (setf (screen-cell result column row)
                            (screen-cell screen (+ start-x column) (+ start-y row)))))
    result))

(defun screen-blit (dest src &key (dest-x 0) (dest-y 0) (src-x 0) (src-y 0)
                                  (width (screen-width src))
                                  (height (screen-height src)))
  "Copy a WIDTH by HEIGHT region of SRC at (SRC-X, SRC-Y) into DEST at
(DEST-X, DEST-Y), returning DEST. Cells are copied independently. The region is
clipped to the parts that fall inside both SRC and DEST, so a blit that runs off
an edge copies only its visible overlap instead of signaling. This is the
primitive for compositing sub-screens (panels, widgets) onto a frame."
  (loop for row from 0 below height
        for sy = (+ src-y row)
        for dy = (+ dest-y row)
        when (and (<= 0 sy) (< sy (screen-height src))
                  (<= 0 dy) (< dy (screen-height dest)))
          do (loop for col from 0 below width
                   for sx = (+ src-x col)
                   for dx = (+ dest-x col)
                   when (and (<= 0 sx) (< sx (screen-width src))
                             (<= 0 dx) (< dx (screen-width dest)))
                     do (setf (screen-cell dest dx dy)
                              (screen-cell src sx sy))))
  dest)

