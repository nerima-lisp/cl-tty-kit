(in-package #:cl-tty-kit)

(define-simple-assert %assert-constraint-real (name value constraint)
  (realp value)
  "Layout constraint ~S has non-real ~A ~S." constraint name value)

(defmacro %constraint-baseline (constraint available)
  `(let ((constraint ,constraint) (available ,available))
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
         (:fill 0)))))

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

(defmacro %clip-sizes (sizes available)
  "Clip SIZES cumulatively so their running sum never exceeds AVAILABLE."
  `(let ((%clip-sizes-list ,sizes) (%clip-sizes-remaining ,available))
     (mapcar (lambda (size)
               (let ((take (max 0 (min size %clip-sizes-remaining))))
                 (decf %clip-sizes-remaining take)
                 take))
             %clip-sizes-list)))

(defmacro %largest-remainder-order (shares weights)
  "Return the indices of SHARES (each a weighted fractional share of the
leftover being distributed), sorted by descending fractional remainder and
skipping any index whose WEIGHT is zero -- the order the largest-remainder
method hands out leftover whole units in."
  `(let ((shares ,shares) (weights ,weights))
     (mapcar #'car
             (sort (loop for share in shares
                         for weight in weights
                         for index from 0
                         when (plusp weight)
                           collect (cons index (- share (floor share))))
                   #'> :key #'cdr))))

(defmacro %distribute-remaining (sizes weights remaining)
  "Add REMAINING cells to SIZES in proportion to WEIGHTS, using the
largest-remainder method so the integer sizes still sum exactly."
  `(let ((sizes ,sizes) (weights ,weights) (remaining ,remaining))
     (let ((total-weight (reduce #'+ weights)))
       (if (or (<= remaining 0) (zerop total-weight))
           sizes
           (let* ((shares (mapcar (lambda (weight) (/ (* remaining weight) total-weight))
                                  weights))
                  (floors (mapcar #'floor shares))
                  (leftover (- remaining (reduce #'+ floors)))
                  (order (%largest-remainder-order shares weights))
                  ;; Incrementing selected list elements with NTH is quadratic.
                  ;; Keep the public list result while updating a transient vector.
                  (result (coerce (mapcar #'+ sizes floors) 'vector)))
             (declare (type vector result))
             (loop repeat leftover
                   for index in order
                   do (incf (aref result index)))
             (coerce result 'list))))))

(defmacro %layout-solve-sizes (available constraints)
  `(let* ((available ,available)
          (constraints ,constraints)
          (baselines (mapcar (lambda (constraint)
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
