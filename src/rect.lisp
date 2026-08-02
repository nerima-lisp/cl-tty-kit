(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Rectangular regions for layout
;;;
;;; A RECT is a plain 0-based (X, Y, WIDTH, HEIGHT) value. It carries no screen;
;;; it is the geometry callers thread through SCREEN-DRAW-BOX, SCREEN-WRITE-*,
;;; and SCREEN-FILL-RECT to lay panels out without recomputing offsets by hand.
;;; --------------------------------------------------------------------------

(defstruct (rect (:constructor %make-rect (&key (x 0) (y 0) (width 0) (height 0)))
                 (:copier nil))
  "A rectangular region with a 0-based X/Y origin and WIDTH/HEIGHT extents."
  (x 0 :type (integer 0))
  (y 0 :type (integer 0))
  (width 0 :type (integer 0))
  (height 0 :type (integer 0)))

(document-function 'rect-x "Return the origin column of RECT.")
(document-function 'rect-y "Return the origin row of RECT.")
(document-function 'rect-width "Return the column extent of RECT.")
(document-function 'rect-height "Return the row extent of RECT.")

(defun rect-right (rect)
  "Return the column just past RECT's right edge (RECT-X + RECT-WIDTH)."
  (+ (rect-x rect) (rect-width rect)))

(defun rect-bottom (rect)
  "Return the row just past RECT's bottom edge (RECT-Y + RECT-HEIGHT)."
  (+ (rect-y rect) (rect-height rect)))

(define-simple-assert %assert-rect-extent (name value)
  (typep value '(integer 0 *))
  "RECT ~A ~S must be a non-negative integer." name value)

(define-simple-assert %assert-rect-integer (name value)
  (integerp value)
  "RECT ~A ~S must be an integer." name value)

(defun make-rect (&key (x 0) (y 0) (width 0) (height 0))
  "Create a RECT at (X, Y) with the given WIDTH and HEIGHT.
Each field must be a non-negative integer; otherwise an error is signaled."
  (%assert-rect-extent :x x)
  (%assert-rect-extent :y y)
  (%assert-rect-extent :width width)
  (%assert-rect-extent :height height)
  (%make-rect :x x :y y :width width :height height))

(defun rect-inset (rect &key (all 0) (left all) (top all) (right all) (bottom all))
  "Return a new RECT shrunk inward by the given non-negative margins.
  ALL sets a default applied to every side that is not given its own margin. The
origin moves in by LEFT/TOP and the extents shrink by LEFT+RIGHT / TOP+BOTTOM,
clamped at zero, so an over-large inset collapses to a zero-size rect at the
inset origin. This is the natural way to carve the interior out of a bordered
box (inset by 1 on every side)."
  (%assert-rect-integer :left left)
  (%assert-rect-integer :top top)
  (%assert-rect-integer :right right)
  (%assert-rect-integer :bottom bottom)
  (%make-rect :x (+ (rect-x rect) (max 0 left))
              :y (+ (rect-y rect) (max 0 top))
              :width (max 0 (- (rect-width rect) (max 0 left) (max 0 right)))
              :height (max 0 (- (rect-height rect) (max 0 top) (max 0 bottom)))))

(defmacro %define-rect-split (name doc extent-accessor first-part second-part)
  "Define a RECT-splitting function NAME with DOC that partitions RECT along one
axis at offset AT, with a GAP between the two parts -- the shared shape of
RECT-SPLIT-HORIZONTAL and RECT-SPLIT-VERTICAL, which differ only in which axis
EXTENT-ACCESSOR reads and how FIRST-PART/SECOND-PART build each result. Both part
forms see FIRST-EXTENT, SECOND-OFFSET, and SECOND-EXTENT bound in scope."
  `(defun ,name (rect at &key (gap 0))
     ,doc
     (%assert-rect-integer :at at)
     (%assert-rect-integer :gap gap)
     (let* ((extent (,extent-accessor rect))
            (first-extent (clamp at 0 extent))
            (second-offset (min extent (+ first-extent (max 0 gap))))
            (second-extent (- extent second-offset)))
       (values ,first-part ,second-part))))

(%define-rect-split rect-split-horizontal
    "Split RECT into (VALUES LEFT RIGHT) at column offset AT within the rect.
LEFT receives AT columns; RIGHT begins GAP columns further right and receives the
remainder. AT and GAP are clamped so both parts stay inside RECT, each possibly
zero-width. The rows are unchanged."
  rect-width
  (%make-rect :x (rect-x rect) :y (rect-y rect)
             :width first-extent :height (rect-height rect))
  (%make-rect :x (+ (rect-x rect) second-offset) :y (rect-y rect)
             :width second-extent :height (rect-height rect)))

(%define-rect-split rect-split-vertical
    "Split RECT into (VALUES TOP BOTTOM) at row offset AT within the rect.
TOP receives AT rows; BOTTOM begins GAP rows further down and receives the
remainder. AT and GAP are clamped so both parts stay inside RECT, each possibly
zero-height. The columns are unchanged."
  rect-height
  (%make-rect :x (rect-x rect) :y (rect-y rect)
             :width (rect-width rect) :height first-extent)
  (%make-rect :x (rect-x rect) :y (+ (rect-y rect) second-offset)
             :width (rect-width rect) :height second-extent))

(defun rect-contains-p (rect x y)
  "Return true when column X and row Y fall inside RECT."
  (%assert-rect-integer :x x)
  (%assert-rect-integer :y y)
  (and (<= (rect-x rect) x) (< x (rect-right rect))
       (<= (rect-y rect) y) (< y (rect-bottom rect))))

(defun rect-empty-p (rect)
  "Return true when RECT encloses no cells (zero width or zero height)."
  (or (zerop (rect-width rect)) (zerop (rect-height rect))))

(defun rect-area (rect)
  "Return the number of cells RECT covers (its width times its height)."
  (* (rect-width rect) (rect-height rect)))

(defun rect-intersect (a b)
  "Return the overlap of rects A and B as a new RECT.
When they do not overlap the result is an empty rect (RECT-EMPTY-P true). This is
the clipping primitive: intersect a draw region with the screen bounds before
writing."
  (let* ((x (max (rect-x a) (rect-x b)))
         (y (max (rect-y a) (rect-y b)))
         (right (min (rect-right a) (rect-right b)))
         (bottom (min (rect-bottom a) (rect-bottom b))))
    (%make-rect :x x :y y
                :width (max 0 (- right x))
                :height (max 0 (- bottom y)))))

(defun rect-union (a b)
  "Return the smallest RECT that contains both A and B.
An empty operand is ignored (the other is returned), so accumulating a union
over a set of damaged regions yields their bounding box."
  (cond
    ((rect-empty-p a) b)
    ((rect-empty-p b) a)
    (t (let* ((x (min (rect-x a) (rect-x b)))
              (y (min (rect-y a) (rect-y b)))
              (right (max (rect-right a) (rect-right b)))
              (bottom (max (rect-bottom a) (rect-bottom b))))
         (%make-rect :x x :y y :width (- right x) :height (- bottom y))))))
