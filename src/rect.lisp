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

(setf (documentation 'rect-x 'function) "Return the origin column of RECT.")
(setf (documentation 'rect-y 'function) "Return the origin row of RECT.")
(setf (documentation 'rect-width 'function) "Return the column extent of RECT.")
(setf (documentation 'rect-height 'function) "Return the row extent of RECT.")

(defun rect-right (rect)
  "Return the column just past RECT's right edge (RECT-X + RECT-WIDTH)."
  (+ (rect-x rect) (rect-width rect)))

(defun rect-bottom (rect)
  "Return the row just past RECT's bottom edge (RECT-Y + RECT-HEIGHT)."
  (+ (rect-y rect) (rect-height rect)))

(defun %assert-rect-extent (name value)
  (%assert (typep value '(integer 0 *)) "RECT ~A ~S must be a non-negative integer." name value))

(defun %assert-rect-integer (name value)
  (%assert (integerp value) "RECT ~A ~S must be an integer." name value))

(defun %assert-constraint-real (name value constraint)
  (%assert (realp value) "Layout constraint ~S has non-real ~A ~S." constraint name value))

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

(defun %constraint-baseline (constraint available)
  "Return the fixed baseline size a CONSTRAINT claims from AVAILABLE cells."
  (unless (consp constraint)
    (error "Layout constraint ~S must be a non-empty list." constraint))
  (destructuring-bind (kind &rest args) constraint
    (ecase kind
      (:length
       (%assert-constraint-real :length (first args) constraint)
       (max 0 (first args)))
      (:percentage
       (%assert-constraint-real :percentage (first args) constraint)
       (max 0 (floor (* (first args) available) 100)))
      (:ratio (let ((denominator (second args)))
                (%assert-constraint-real :numerator (first args) constraint)
                (unless (and (integerp denominator) (plusp denominator))
                  (error "Invalid ratio denominator in layout constraint: ~S" constraint))
                (max 0 (floor (* (first args) available) denominator))))
      (:min
       (%assert-constraint-real :min (first args) constraint)
       (max 0 (first args)))
      (:fill 0))))

(defun %constraint-weight (constraint)
  "Return the flexible-growth weight of a CONSTRAINT (0 for fixed constraints).
CONSTRAINT's shape is already validated by %CONSTRAINT-BASELINE, which
%LAYOUT-SOLVE-SIZES always runs across every constraint first."
  (destructuring-bind (kind &rest args) constraint
    (case kind
      (:fill
       (%assert-constraint-real :fill (first args) constraint)
       (max 0 (first args)))
      (:min 1)
      (otherwise 0))))

(defun %clip-sizes (sizes available)
  "Clip SIZES cumulatively so their running sum never exceeds AVAILABLE."
  (let ((remaining available))
    (mapcar (lambda (size)
              (let ((take (max 0 (min size remaining))))
                (decf remaining take)
                take))
            sizes)))

(defun %largest-remainder-order (shares weights)
  "Return the indices of SHARES (each a weighted fractional share of the
leftover being distributed), sorted by descending fractional remainder and
skipping any index whose WEIGHT is zero -- the order the largest-remainder
method hands out leftover whole units in."
  (mapcar #'car
          (sort (loop for share in shares
                      for weight in weights
                      for index from 0
                      when (plusp weight)
                        collect (cons index (- share (floor share))))
                #'> :key #'cdr)))

(defun %distribute-remaining (sizes weights remaining)
  "Add REMAINING cells to SIZES in proportion to WEIGHTS, using the
largest-remainder method so the integer sizes still sum exactly."
  (let ((total-weight (reduce #'+ weights)))
    (if (or (<= remaining 0) (zerop total-weight))
        sizes
        (let* ((shares (mapcar (lambda (weight) (/ (* remaining weight) total-weight))
                               weights))
               (floors (mapcar #'floor shares))
               (leftover (- remaining (reduce #'+ floors)))
               (order (%largest-remainder-order shares weights))
               (result (mapcar #'+ sizes floors)))
          (loop repeat leftover
                for index in order
                do (incf (nth index result)))
          result))))

(defun %layout-solve-sizes (available constraints)
  (let* ((baselines (mapcar (lambda (constraint)
                              (%constraint-baseline constraint available))
                            constraints))
         (weights (mapcar #'%constraint-weight constraints))
         (remaining (- available (reduce #'+ baselines))))
    (%clip-sizes (%distribute-remaining baselines weights remaining) available)))

(defun layout-split (rect direction constraints &key (spacing 0))
  "Divide RECT along DIRECTION into one sub-rect per constraint, returning them.
DIRECTION is :HORIZONTAL (split into columns) or :VERTICAL (into rows). Each entry
of CONSTRAINTS sizes the matching sub-rect and is one of (:LENGTH N),
(:PERCENTAGE P), (:RATIO NUM DEN), (:MIN N), or (:FILL WEIGHT). Fixed constraints
take their size from the axis extent; the leftover is shared among :FILL (by
weight) and :MIN (weight 1, never below N) constraints via largest-remainder, so
the integer sizes tile exactly. SPACING cells sit between segments. Sizes are
clipped so the sub-rects always stay within RECT. An empty CONSTRAINTS yields an
empty list -- this is the constraint layout primitive TUIs build panels from."
  (%assert-rect-integer :spacing spacing)
  (let* ((axis-total (ecase direction
                       (:horizontal (rect-width rect))
                       (:vertical (rect-height rect))))
         (gaps (* (max 0 spacing) (max 0 (1- (length constraints)))))
         (available (max 0 (- axis-total gaps)))
         (sizes (%layout-solve-sizes available constraints))
         (offset 0)
         (rects '()))
    (dolist (size sizes (nreverse rects))
      (push (ecase direction
              (:horizontal (%make-rect :x (+ (rect-x rect) offset)
                                       :y (rect-y rect)
                                       :width size
                                       :height (rect-height rect)))
              (:vertical (%make-rect :x (rect-x rect)
                                     :y (+ (rect-y rect) offset)
                                     :width (rect-width rect)
                                     :height size)))
            rects)
      (incf offset (+ size (max 0 spacing))))))

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
