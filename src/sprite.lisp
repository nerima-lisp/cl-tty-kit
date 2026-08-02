(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Transparent sprite blitting
;;;
;;; SPRITE-BLIT composites a block of multi-line text ("ASCII art") onto a
;;; SCREEN, treating a caller-chosen transparent marker character (a blank
;;; space by default) as pass-through: a transparent source cell leaves the
;;; destination cell beneath it untouched instead of overwriting it. This is
;;; the piece SCREEN-BLIT (screen-regions.lisp) does not offer -- SCREEN-BLIT
;;; always copies every cell of its source region, including its blanks, so it
;;; cannot by itself composite an irregular sprite over existing content.
;;;
;;; The edge-clipping bounds below are SCREEN-BLIT's own
;;; (MAX 0 (- SRC-OFFSET) (- DEST-OFFSET)) / (MIN LENGTH ...) formula,
;;; specialized to a sprite that always reads its own text starting at source
;;; offset (0, 0): with SRC-X = SRC-Y = 0 and the source dimensions equal to
;;; the sprite's own WIDTH/HEIGHT, SCREEN-BLIT's four clipping bounds reduce
;;; to the four computed in %SPRITE-CLIP-BOUNDS. This keeps a sprite clipped
;;; exactly the way SCREEN-BLIT clips a full region, without materializing a
;;; second SCREEN and threading it through SCREEN-BLIT only to then have to
;;; reverse its unconditional cell copy for the transparent cells.
;;; --------------------------------------------------------------------------

(define-simple-assert %assert-sprite-text (text)
  (stringp text)
  "Sprite TEXT ~S must be a string." text)

(define-simple-assert %assert-sprite-transparent (transparent)
  (characterp transparent)
  "Sprite :TRANSPARENT ~S must be a character." transparent)

(defmacro %sprite-clip-bounds (x y width height screen)
  "Return (VALUES COLUMN-START COLUMN-END ROW-START ROW-END), the sprite-local
bounds (see the file header) at which a WIDTH by HEIGHT sprite placed at
(X, Y) overlaps SCREEN."
  `(let ((x ,x) (y ,y) (width ,width) (height ,height) (screen ,screen))
     (values (max 0 (- x))
             (min width (- (screen-width screen) x))
             (max 0 (- y))
             (min height (- (screen-height screen) y)))))

(defun sprite-blit (screen text x y &key (transparent #\Space) style)
  "Composite the multi-line TEXT onto SCREEN at (X, Y), returning SCREEN.
TEXT is split on #\\Newline into rows of ASCII art; each character becomes
one screen cell -- a one-column-per-character sprite format, unlike
SCREEN-WRITE-STRING's CHAR-WIDTH-aware column advance, since ASCII art is
already laid out in a monospaced source grid.

A character EQL to TRANSPARENT (a blank space by default) is skipped: the
destination cell beneath it is left untouched rather than overwritten, so an
irregular or non-rectangular sprite composites over whatever SCREEN already
holds. A ragged line shorter than the sprite's own width is likewise
transparent past its own end. Non-transparent characters are written with
STYLE via SCREEN-PUT-CELL.

The sprite is clipped to SCREEN the same way SCREEN-BLIT clips a region (see
the file header); a sprite placed partly or fully off SCREEN draws only its
visible overlap instead of signaling. An empty TEXT (or one with only empty
lines) is a no-op."
  (%assert-screen screen)
  (%assert-sprite-text text)
  (%assert-screen-offset :x x)
  (%assert-screen-offset :y y)
  (%assert-sprite-transparent transparent)
  (let* ((text-length (length text))
         (screen-width (screen-width screen))
         (screen-height (screen-height screen))
         (cells (screen-cells screen))
         (normalized-style nil)
         (style-ready-p (null style))
         (line-start 0)
         (row 0)
         (first-changed-row nil)
         (last-changed-row nil))
    (loop
      for newline-position = (position #\Newline text :start line-start)
      for line-end = (or newline-position text-length)
      for destination-y = (+ y row)
      when (and (<= 0 destination-y) (< destination-y screen-height))
        do (loop with column-start = (max 0 (- x))
                 with column-end = (min (- line-end line-start)
                                        (- screen-width x))
                 for column from column-start below column-end
                 for char = (char text (+ line-start column))
                 unless (char= char transparent)
                   do (unless style-ready-p
                        (setf normalized-style (%normalize-cell-style style)
                              style-ready-p t))
                      (setf (aref cells (+ (* destination-y screen-width)
                                           x column))
                            (%make-cell :char char
                                        :raw-style (and normalized-style
                                                        (copy-tree normalized-style))))
                      (unless first-changed-row
                        (setf first-changed-row destination-y))
                      (setf last-changed-row destination-y))
      if newline-position
        do (setf line-start (1+ newline-position))
           (incf row)
      else
        do (return))
    (when first-changed-row
      (%screen-touch screen first-changed-row (1+ last-changed-row))))
  screen)
