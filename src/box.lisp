(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Box drawing
;;;
;;; Border glyphs are stored as Unicode code points and materialized with
;;; CODE-CHAR, so this source file needs no non-ASCII bytes and the character
;;; set is unambiguous regardless of the file's external format.
;;; --------------------------------------------------------------------------

(defparameter +box-borders+
  (list
   ;;      name       H       V       TL      TR      BL      BR
   (list :single  #x2500 #x2502 #x250C #x2510 #x2514 #x2518)
   (list :rounded #x2500 #x2502 #x256D #x256E #x2570 #x256F)
   (list :double  #x2550 #x2551 #x2554 #x2557 #x255A #x255D)
   (list :heavy   #x2501 #x2503 #x250F #x2513 #x2517 #x251B)
   (list :ascii   #.(char-code #\-) #.(char-code #\|)
                  #.(char-code #\+) #.(char-code #\+)
                  #.(char-code #\+) #.(char-code #\+)))
  "Maps a border-style keyword to its six drawing code points, in the order
horizontal, vertical, top-left, top-right, bottom-left, bottom-right.")

(defmacro %box-border-chars (name)
  "Return the six border characters (H V TL TR BL BR) for style NAME."
  `(let ((name ,name))
     (let ((entry (assoc name +box-borders+)))
       (unless entry
         (error "Unknown box border ~S; expected one of ~S."
                name
                (mapcar #'car +box-borders+)))
       (mapcar #'code-char (rest entry)))))

(define-simple-assert %assert-box-title (title)
  (or (null title) (stringp title))
  "Box TITLE ~S must be NIL or a string." title)

(define-simple-assert %assert-box-title-align (align)
  (member align '(:left :center :right))
  "Box TITLE-ALIGN ~S must be one of :LEFT, :CENTER, or :RIGHT." align)

(defmacro %box-put (screen x y char style style-supplied-p)
  `(let ((screen ,screen) (x ,x) (y ,y) (char ,char) (style ,style)
         (style-supplied-p ,style-supplied-p))
     (if style-supplied-p
         (screen-put-cell screen x y char :style style)
         (screen-put-cell screen x y char))))

(defmacro %screen-draw-line (screen glyph length style style-supplied-p cell-at)
  "Paint LENGTH cells of GLYPH along a line, calling CELL-AT with each offset
from 0 below LENGTH to get that cell's (VALUES X Y). Shared by
SCREEN-DRAW-HORIZONTAL-LINE and SCREEN-DRAW-VERTICAL-LINE, which differ only in
how an offset maps to a screen coordinate."
  `(let ((screen ,screen) (glyph ,glyph) (length ,length) (style ,style)
         (style-supplied-p ,style-supplied-p) (cell-at ,cell-at))
     (when (plusp length)
       (loop for offset below length
             do (multiple-value-bind (x y) (funcall cell-at offset)
                  (%box-put screen x y glyph style style-supplied-p))))
     screen))

(defun screen-draw-horizontal-line (screen x y length
                                    &key (border :single) (style nil style-supplied-p))
  "Draw a LENGTH-column horizontal line at (X, Y) in SCREEN, returning SCREEN.
BORDER selects the glyph set (:SINGLE, :ROUNDED, :DOUBLE, :HEAVY, or :ASCII) and
STYLE, when supplied, is applied to every cell. A zero LENGTH is a no-op; a line
that leaves the screen signals SCREEN-INDEX-OUT-OF-BOUNDS."
  (%assert-screen-rect-bounds screen x y length 1)
  (%screen-draw-line screen (first (%box-border-chars border)) length style style-supplied-p
                     (lambda (offset) (values (+ x offset) y))))

(defun screen-draw-vertical-line (screen x y length
                                  &key (border :single) (style nil style-supplied-p))
  "Draw a LENGTH-row vertical line at (X, Y) in SCREEN, returning SCREEN.
BORDER selects the glyph set (:SINGLE, :ROUNDED, :DOUBLE, :HEAVY, or :ASCII) and
STYLE, when supplied, is applied to every cell. A zero LENGTH is a no-op; a line
that leaves the screen signals SCREEN-INDEX-OUT-OF-BOUNDS."
  (%assert-screen-rect-bounds screen x y 1 length)
  (%screen-draw-line screen (second (%box-border-chars border)) length style style-supplied-p
                     (lambda (offset) (values x (+ y offset)))))

(defmacro %box-title-column (x width title-cells align)
  "Return the starting column for a TITLE-CELLS-wide title on a box's top edge,
inset one cell from each corner and placed by ALIGN."
  `(let ((x ,x) (width ,width) (title-cells ,title-cells) (align ,align))
     (let* ((inner-width (- width 2))
            (remaining (- inner-width title-cells))
            (half (ash remaining -1)))
       (declare (type fixnum inner-width remaining half))
       (ecase align
         (:left (1+ x))
         (:right (if (minusp remaining) (1+ x) (+ x 1 remaining)))
         (:center (+ x 1 (if (minusp half) 0 half)))))))

(defmacro %draw-box-title (screen x y width title align style style-supplied-p title-style)
  "Write TITLE into the top border row of a box, clipped to the space between
the corners. Uses TITLE-STYLE when given, else the box STYLE."
  `(let ((screen ,screen) (x ,x) (y ,y) (width ,width) (title ,title) (align ,align)
         (style ,style) (style-supplied-p ,style-supplied-p) (title-style ,title-style))
     (let ((inner-width (- width 2)))
       (when (and title (plusp inner-width))
         (let* ((clipped (subseq title 0 (%cells-prefix-end title inner-width)))
                (cells (%string-cell-width clipped)))
           (when (plusp (length clipped))
             (let ((column (%box-title-column x width cells align)))
               (cond
                 (title-style
                  (screen-write-string screen column y clipped :style title-style))
                 (style-supplied-p
                  (screen-write-string screen column y clipped :style style))
                 (t
                  (screen-write-string screen column y clipped))))))))))

(defun screen-draw-box (screen x y width height
                        &key (border :single) (style nil style-supplied-p)
                             title (title-align :center) title-style)
  "Draw a WIDTH by HEIGHT box outline at (X, Y) in SCREEN, returning SCREEN.
The four corners, top/bottom edges, and left/right edges are painted with the
BORDER glyph set (:SINGLE, :ROUNDED, :DOUBLE, :HEAVY, or :ASCII); the interior is
left untouched, so a box can frame content drawn separately. STYLE, when
supplied, applies to every border cell. TITLE, when given, is written into the
top border between the corners, positioned by TITLE-ALIGN (:LEFT, :CENTER, or
:RIGHT) and styled with TITLE-STYLE (falling back to STYLE); it is clipped to the
inner width and only drawn on a box at least two cells wide and tall. A
degenerate box one cell tall or wide collapses to the matching line. A zero-area
box is a no-op even off-screen; a positive box that leaves the screen signals
SCREEN-INDEX-OUT-OF-BOUNDS and negative extents signal
SCREEN-DIMENSIONS-INVALID, both leaving SCREEN unchanged."
  (%assert-screen-rect-bounds screen x y width height)
  (%assert-box-title title)
  (%assert-box-title-align title-align)
  (when (and (plusp width) (plusp height))
    (cond
      ((= height 1)
       (screen-draw-horizontal-line screen x y width
                                    :border border
                                    :style (and style-supplied-p style)))
      ((= width 1)
       (screen-draw-vertical-line screen x y height
                                  :border border
                                  :style (and style-supplied-p style)))
      (t
       (destructuring-bind (h v tl tr bl br) (%box-border-chars border)
         (let ((right (+ x width -1))
               (bottom (+ y height -1)))
           (flet ((put (cx cy ch)
                    (%box-put screen cx cy ch style style-supplied-p)))
             (put x y tl)
             (put right y tr)
             (put x bottom bl)
             (put right bottom br)
             (loop for column from (1+ x) below right
                   do (put column y h)
                      (put column bottom h))
             (loop for row from (1+ y) below bottom
                   do (put x row v)
                      (put right row v))))
         (%draw-box-title screen x y width title title-align
                          style style-supplied-p title-style)))))
  screen)
