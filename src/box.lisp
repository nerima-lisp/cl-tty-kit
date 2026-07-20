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

(defun %box-border-chars (name)
  "Return the six border characters (H V TL TR BL BR) for style NAME."
  (let ((entry (assoc name +box-borders+)))
    (unless entry
      (error "Unknown box border ~S; expected one of ~S."
             name
             (mapcar #'car +box-borders+)))
    (mapcar #'code-char (rest entry))))

(defun %assert-box-title (title)
  (unless (or (null title) (stringp title))
    (error "Box TITLE ~S must be NIL or a string." title)))

(defun %assert-box-title-align (align)
  (unless (member align '(:left :center :right))
    (error "Box TITLE-ALIGN ~S must be one of :LEFT, :CENTER, or :RIGHT." align)))

(defun %box-put (screen x y char style style-supplied-p)
  (if style-supplied-p
      (screen-put-cell screen x y char :style style)
      (screen-put-cell screen x y char)))

(defun screen-draw-horizontal-line (screen x y length
                                    &key (border :single) (style nil style-supplied-p))
  "Draw a LENGTH-column horizontal line at (X, Y) in SCREEN, returning SCREEN.
BORDER selects the glyph set (:SINGLE, :ROUNDED, :DOUBLE, :HEAVY, or :ASCII) and
STYLE, when supplied, is applied to every cell. A zero LENGTH is a no-op; a line
that leaves the screen signals SCREEN-INDEX-OUT-OF-BOUNDS."
  (%assert-screen-rect-bounds screen x y length 1)
  (when (plusp length)
    (let ((h (first (%box-border-chars border))))
      (loop for column from x below (+ x length)
            do (%box-put screen column y h style style-supplied-p))))
  screen)

(defun screen-draw-vertical-line (screen x y length
                                  &key (border :single) (style nil style-supplied-p))
  "Draw a LENGTH-row vertical line at (X, Y) in SCREEN, returning SCREEN.
BORDER selects the glyph set (:SINGLE, :ROUNDED, :DOUBLE, :HEAVY, or :ASCII) and
STYLE, when supplied, is applied to every cell. A zero LENGTH is a no-op; a line
that leaves the screen signals SCREEN-INDEX-OUT-OF-BOUNDS."
  (%assert-screen-rect-bounds screen x y 1 length)
  (when (plusp length)
    (let ((v (second (%box-border-chars border))))
      (loop for row from y below (+ y length)
            do (%box-put screen x row v style style-supplied-p))))
  screen)

(defun %box-title-column (x width title-cells align)
  "Return the starting column for a TITLE-CELLS-wide title on a box's top edge,
inset one cell from each corner and placed by ALIGN."
  (let ((inner-width (- width 2)))
    (ecase align
      (:left (1+ x))
      (:right (+ x 1 (max 0 (- inner-width title-cells))))
      (:center (+ x 1 (max 0 (floor (- inner-width title-cells) 2)))))))

(defun %draw-box-title (screen x y width title align style style-supplied-p title-style)
  "Write TITLE into the top border row of a box, clipped to the space between
the corners. Uses TITLE-STYLE when given, else the box STYLE."
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
               (screen-write-string screen column y clipped)))))))))

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
