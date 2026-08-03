(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Bulk and region operations on SCREEN
;;;
;;; Everything here composes the single-cell primitives in screen.lisp
;;; (SCREEN-CELL, SCREEN-PUT-CELL) into whole-string, rectangle, and
;;; whole-grid operations: writing text, filling regions, scrolling,
;;; cropping, and compositing one screen onto another.
;;; --------------------------------------------------------------------------
  (defmacro %screen-write-string-normalized (screen x y string start end style all-width-one-p)
  "Write a validated STRING span using an already normalized STYLE."
  `(let ((screen ,screen)
         (x ,x)
         (y ,y)
         (string ,string)
         (start ,start)
         (end ,end)
         (style ,style)
         (all-width-one-p ,all-width-one-p))
     (let* ((screen-width (screen-width screen))
            (cells (screen-cells screen))
            (spacer nil)
            (cell nil)
            (previous-char nil)
            (column x)
            (row-start (* y screen-width)))
        (declare (type fixnum screen-width column row-start x y start end))
        (loop for offset fixnum from start below end
              for char = (char string offset)
              for width fixnum = (if all-width-one-p 1 (%character-width char))
              for advance fixnum = (if (= width 2) 2 1)
              for index fixnum = (+ row-start column)
             do (unless (and cell (char= char previous-char))
                  (setf cell (%make-cell :char char :raw-style style)
                        previous-char char))
                (setf (aref cells index) cell)
                (when (= width 2)
                  (unless spacer
                    (setf spacer (%make-cell :char #\Space :raw-style style)))
                  (setf (aref cells (1+ index)) spacer))
                (incf column advance))
       (%screen-touch screen y (1+ y)))))

  (defun screen-write-string (screen x y string &key style (start 0) (end nil end-supplied-p))
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
    ;; END is computed from STRING/END-SUPPLIED-P before either is known to be
    ;; well-formed, so it stays undeclared until %ASSERT-STRING-BOUNDS has
    ;; confirmed STRING is a string and START/END are in-bounds integers --
    ;; declaring it FIXNUM any earlier makes SBCL's own binding-time check
    ;; fire on a malformed call (e.g. a non-string STRING, which leaves END
    ;; NIL) before that assertion gets a chance to signal the library's own
    ;; condition. See SCREEN-ROW-STRING for the same validate-before-declare
    ;; shape.
    (let ((end (if end-supplied-p end (and (stringp string) (length string)))))
      (%assert-string-bounds string start end)
      (let ((run-length (- end start)))
        (declare (type fixnum run-length))
        (when (plusp run-length)
          (let ((total-width 0)
                (all-width-one-p t))
            (declare (type fixnum total-width))
            (loop for offset fixnum from start below end
                  for width fixnum = (%character-width (char string offset))
                  do (incf total-width (if (= width 2) 2 1))
                     (unless (= width 1)
                       (setf all-width-one-p nil)))
            (%assert-screen-bounds screen x y)
            (%assert-screen-bounds screen (+ x (1- total-width)) y)
            (%screen-write-string-normalized
             screen x y string start end (%coerce-cell-style style) all-width-one-p)))
        screen)))

  (defun screen-fill-rect (screen x y width height value &key (style nil style-supplied-p))
    "Fill the WIDTH by HEIGHT rectangle at X and Y in SCREEN with VALUE. Returns SCREEN."
    (%assert-screen-rect-bounds screen x y width height)
    (when (and (plusp width) (plusp height))
      (let ((cells (screen-cells screen))
            (cell (%coerce-cell-value value style style-supplied-p))
            (screen-width (screen-width screen))
            (end-y (+ y height)))
        (declare (type simple-vector cells)
                 (type fixnum screen-width end-y))
        (loop for row fixnum from y below end-y
              for start fixnum = (+ (* row screen-width) x)
              do (fill cells cell :start start :end (+ start width)))
        (%screen-touch screen y end-y)))
    screen)

(defun screen-fill (screen value &key (style nil style-supplied-p))
  "Fill every cell of SCREEN with VALUE, returning SCREEN.
VALUE is a CELL template or a character; STYLE overrides its style when supplied.
This is SCREEN-FILL-RECT applied to the whole grid, so an empty screen is a
no-op."
  (%assert-screen screen)
  (let ((width (screen-width screen))
        (height (screen-height screen)))
    (declare (type fixnum width height))
    (if style-supplied-p
        (screen-fill-rect screen 0 0 width height value :style style)
        (screen-fill-rect screen 0 0 width height value)))
  screen)

(defun screen-copy (screen) "Return a new SCREEN with an independent backing vector and shared cells." (%assert-screen screen) (%make-screen :width (screen-width screen) :height (screen-height screen) :cells (copy-seq (screen-cells screen)) :generation (screen-generation screen) :row-generations (copy-seq (screen-row-generations screen))))

(defun screen-row-string (screen y &key (start 0) (end nil end-supplied-p))
  "Return the characters stored in row Y of SCREEN between columns START and END.
A double-width glyph appears once followed by the blank spacer cell that
SCREEN-WRITE-STRING writes after it, matching the grid's column layout. An
out-of-range row or column span signals SCREEN-INDEX-OUT-OF-BOUNDS."
  (%assert-screen screen)
  (let* ((screen-width (screen-width screen))
         (end (if end-supplied-p end screen-width)))
    (declare (type fixnum screen-width))
    (unless (and (integerp y)
                 (integerp start)
                 (integerp end)
                 (<= 0 y)
                 (< y (screen-height screen))
                 (<= 0 start)
                 (<= start end)
                 (<= end screen-width))
      (error 'screen-index-out-of-bounds
             :screen screen
             :x start
             :y y
             :width screen-width
             :height (screen-height screen)))
    (let* ((length (- end start))
           (result (make-string length))
           (cells (screen-cells screen))
           (cell-index (+ (* y screen-width) start)))
      (declare (type simple-vector cells)
               (type fixnum length cell-index))
      (loop for result-index fixnum from 0 below length
            do (setf (schar result result-index)
                     (cell-char (aref cells (+ cell-index result-index)))))
      result)))

  (defun screen-scroll (screen count &key fill)
    "Scroll SCREEN vertically by COUNT rows in place, returning SCREEN."
    (%assert-screen screen)
    (%assert (integerp count) "COUNT must be an integer, got ~S" count)
    (let ((width (screen-width screen))
          (height (screen-height screen)))
      (declare (type fixnum width height)
               (type integer count))
      (when (and (plusp width) (plusp height) (not (zerop count)))
        (let* ((shift (cond ((> count height) height)
                            ((< count (- height)) (- height))
                            (t count)))
               (cells (screen-cells screen))
               (fill-cell (%coerce-cell-template fill)))
          (declare (type fixnum shift))
        (if (plusp shift)
            (let ((moved-cells (* (- height shift) width)))
              (declare (type fixnum moved-cells))
              (replace cells cells
                       :start1 0
                       :end1 moved-cells
                       :start2 (* shift width)
                       :end2 (* height width))
              (fill cells fill-cell :start moved-cells))
            (let* ((downward-shift (- shift))
                   (start (* downward-shift width)))
              (declare (type fixnum downward-shift start))
              (replace cells cells
                       :start1 start
                       :end1 (* height width)
                       :start2 0
                       :end2 (* (- height downward-shift) width))
              (fill cells fill-cell :end start)))
        (%screen-touch screen)))
    screen))

  (defun screen-crop (screen rect)
    "Return a new SCREEN holding the clipped RECT region of SCREEN."
    (%assert-screen screen)
    (%assert-screen-rect rect)
    (let* ((rect-x (rect-x rect))
           (rect-y (rect-y rect))
           (screen-width (screen-width screen))
           (screen-height (screen-height screen))
           (rect-right (rect-right rect))
           (rect-bottom (rect-bottom rect))
           (start-x (if (minusp rect-x) 0 rect-x))
           (start-y (if (minusp rect-y) 0 rect-y))
           (end-x (if (> rect-right screen-width) screen-width rect-right))
           (end-y (if (> rect-bottom screen-height) screen-height rect-bottom))
           (width (if (> end-x start-x) (- end-x start-x) 0))
           (height (if (> end-y start-y) (- end-y start-y) 0))
           (source-cells (screen-cells screen))
           (source-width screen-width)
           (result (make-screen width height))
           (result-cells (screen-cells result)))
     (declare (type fixnum rect-x rect-y screen-width screen-height rect-right rect-bottom
                           start-x start-y end-x end-y width height source-width))
      (loop for row fixnum from 0 below height
            for source-start fixnum = (+ (* (+ start-y row) source-width) start-x)
            for result-start fixnum = (* row width)
            do (replace
        result-cells
        source-cells
        :start1
        result-start
        :end1
        (+ result-start width)
        :start2
        source-start
        :end2
        (+ source-start width)))
    result))

  (defun screen-blit (dest src &key (dest-x 0) (dest-y 0) (src-x 0) (src-y 0)
                                (width nil width-supplied-p)
                                (height nil height-supplied-p))
  "Copy a WIDTH by HEIGHT region of SRC at (SRC-X, SRC-Y) into DEST at (DEST-X, DEST-Y), returning DEST. The region is clipped to the parts that fall inside both SRC and DEST, so a blit that runs off an edge copies only its visible overlap instead of signaling. Distinct screens retain independent backing vectors while sharing immutable cell values. This is the primitive for compositing sub-screens (panels, widgets) onto a frame."
  (%assert-screen dest)
  (%assert-screen src)
  (%assert-screen-offset :dest-x dest-x)
  (%assert-screen-offset :dest-y dest-y)
  (%assert-screen-offset :src-x src-x)
  (%assert-screen-offset :src-y src-y)
    (let ((width (if width-supplied-p width (screen-width src)))
          (height (if height-supplied-p height (screen-height src))))
      (%assert-screen-dimensions width height)
      (let* ((source-width (screen-width src))
             (destination-width (screen-width dest))
             (source-height (screen-height src))
             (destination-height (screen-height dest))
             (src-x-offset (if (minusp src-x) (- src-x) 0))
             (dest-x-offset (if (minusp dest-x) (- dest-x) 0))
             (src-y-offset (if (minusp src-y) (- src-y) 0))
             (dest-y-offset (if (minusp dest-y) (- dest-y) 0))
             (column-start (if (> src-x-offset dest-x-offset) src-x-offset dest-x-offset))
             (row-start (if (> src-y-offset dest-y-offset) src-y-offset dest-y-offset))
             (source-column-limit (- source-width src-x))
             (destination-column-limit (- destination-width dest-x))
             (source-row-limit (- source-height src-y))
             (destination-row-limit (- destination-height dest-y))
             (column-end (if (> source-column-limit destination-column-limit)
                             destination-column-limit
                             source-column-limit))
             (row-end (if (> source-row-limit destination-row-limit)
                          destination-row-limit
                          source-row-limit))
             (copy-width (if (> column-end column-start)
                             (- column-end column-start)
                             0))
             (copy-height (if (> row-end row-start)
                              (- row-end row-start)
                              0))
             (source-x (+ src-x column-start))
             (source-y (+ src-y row-start))
             (destination-x (+ dest-x column-start))
             (destination-y (+ dest-y row-start))
             (source-cells (screen-cells src))
             (destination-cells (screen-cells dest)))
        (declare (type fixnum width height source-width destination-width source-height destination-height
                      src-x-offset dest-x-offset src-y-offset dest-y-offset
                      source-column-limit destination-column-limit source-row-limit destination-row-limit
                      column-start column-end row-start row-end copy-width copy-height
                      source-x source-y destination-x destination-y))
        (when (and (plusp copy-width) (plusp copy-height))
          (let ((reverse-rows-p (and (eq source-cells destination-cells)
                                     (> destination-y source-y))))
            (loop for row fixnum from 0 below copy-height
                  for effective-row fixnum = (if reverse-rows-p (- copy-height row 1) row)
                for source-row-start fixnum = (+ (* (+ source-y effective-row) source-width) source-x)
                for destination-row-start fixnum = (+ (* (+ destination-y effective-row) destination-width) destination-x)
                do (replace destination-cells source-cells
                            :start1 destination-row-start
                            :end1 (+ destination-row-start copy-width)
                            :start2 source-row-start
                            :end2 (+ source-row-start copy-width))))
        (%screen-touch dest destination-y (+ destination-y copy-height))))
    dest))
