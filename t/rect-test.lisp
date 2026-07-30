(in-package #:cl-tty-kit/test)

(defun %expect-rect (rect x y width height)
  (expect (rect-x rect) :to-be x)
  (expect (rect-y rect) :to-be y)
  (expect (rect-width rect) :to-be width)
  (expect (rect-height rect) :to-be height))

(describe "make-rect"
  (it "stores every supplied field"
    (%expect-rect (make-rect :x 1 :y 2 :width 3 :height 4) 1 2 3 4))
  (it "defaults to the zero rect"
    (%expect-rect (make-rect) 0 0 0 0))
  (it "rejects a negative x"
    (expect (lambda () (make-rect :x -1)) :to-throw))
  (it "rejects a negative width"
    (expect (lambda () (make-rect :width -2)) :to-throw))
  (it "signals a non-type-error for a malformed x"
    (expect (lambda () (make-rect :x :bad)) :to-throw (lambda (c) (not (typep c 'type-error))))))

(describe "rect-inset"
  (it "insets every edge equally with :all"
    (%expect-rect (rect-inset (make-rect :width 10 :height 6) :all 1) 1 1 8 4))
  (it "insets individual edges independently"
    (%expect-rect (rect-inset (make-rect :width 10 :height 6) :left 2 :right 1) 2 0 7 6))
  (it "layers :all under a more specific edge override"
    (%expect-rect (rect-inset (make-rect :width 10 :height 6) :all 1 :top 2) 1 2 8 3))
  (it "collapses to a zero-size rect at the inset origin when the inset is too large"
    (%expect-rect (rect-inset (make-rect :width 4 :height 4) :all 3) 3 3 0 0))
  (it "signals a non-type-error for a malformed inset amount"
    (expect (lambda () (rect-inset (make-rect) :left :bad))
            :to-throw (lambda (c) (not (typep c 'type-error))))))

(describe "rect-split-horizontal and rect-split-vertical"
  (it "splits at the given column"
    (multiple-value-bind (left right) (rect-split-horizontal (make-rect :width 10 :height 4) 4)
      (%expect-rect left 0 0 4 4)
      (%expect-rect right 4 0 6 4)))
  (it "reserves a gap between the two parts"
    (multiple-value-bind (left right)
        (rect-split-horizontal (make-rect :width 10 :height 4) 4 :gap 1)
      (%expect-rect left 0 0 4 4)
      (%expect-rect right 5 0 5 4)))
  (it "clamps an out-of-range split point, leaving the right part empty"
    (multiple-value-bind (left right) (rect-split-horizontal (make-rect :width 10 :height 4) 20)
      (%expect-rect left 0 0 10 4)
      (%expect-rect right 10 0 0 4)))
  (it "rect-split-vertical splits at the given row"
    (multiple-value-bind (top bottom) (rect-split-vertical (make-rect :width 6 :height 10) 3)
      (%expect-rect top 0 0 6 3)
      (%expect-rect bottom 0 3 6 7)))
  (it "preserves the rect's origin through a split"
    (multiple-value-bind (left right)
        (rect-split-horizontal (make-rect :x 2 :y 3 :width 10 :height 4) 4)
      (%expect-rect left 2 3 4 4)
      (%expect-rect right 6 3 6 4)))
  (it "signals a non-type-error for a malformed split point"
    (expect (lambda () (rect-split-horizontal (make-rect) :bad))
            :to-throw (lambda (c) (not (typep c 'type-error)))))
  (it "signals a non-type-error for a malformed gap"
    (expect (lambda () (rect-split-vertical (make-rect) 1 :gap :bad))
            :to-throw (lambda (c) (not (typep c 'type-error))))))

(describe "rect-contains-p"
  (it "is true for the corners and false just outside each edge"
    (let ((rect (make-rect :x 1 :y 1 :width 3 :height 3)))
      (expect (rect-contains-p rect 1 1) :to-be-truthy)
      (expect (rect-contains-p rect 3 3) :to-be-truthy)
      (expect (rect-contains-p rect 4 1) :to-be-falsy)
      (expect (rect-contains-p rect 0 1) :to-be-falsy)
      (expect (rect-contains-p rect 1 4) :to-be-falsy)))
  (it "signals a non-type-error for a malformed coordinate"
    (expect (lambda () (rect-contains-p (make-rect :x 1 :y 1 :width 3 :height 3) :bad 1))
            :to-throw (lambda (c) (not (typep c 'type-error))))))

(describe "rect-empty-p and rect-area"
  (it "a zero width or height is empty"
    (expect (rect-empty-p (make-rect :width 0 :height 3)) :to-be-truthy)
    (expect (rect-empty-p (make-rect :width 3 :height 0)) :to-be-truthy))
  (it "a positive width and height is not empty"
    (expect (rect-empty-p (make-rect :width 3 :height 3)) :to-be-falsy))
  (it "area is width times height"
    (expect (rect-area (make-rect :width 3 :height 4)) :to-be 12)
    (expect (rect-area (make-rect :width 0 :height 4)) :to-be 0)))

(describe "rect-intersect"
  (it "returns the overlapping region"
    (%expect-rect (rect-intersect (make-rect :width 4 :height 4)
                                  (make-rect :x 2 :y 2 :width 4 :height 4))
                  2 2 2 2))
  (it "non-overlapping rects intersect to an empty rect"
    (expect (rect-empty-p (rect-intersect (make-rect :width 2 :height 2)
                                          (make-rect :x 5 :y 5 :width 2 :height 2)))
            :to-be-truthy))
  (it "intersecting with a containing rect is a no-op clip"
    (%expect-rect (rect-intersect (make-rect :x 1 :y 1 :width 2 :height 2)
                                  (make-rect :width 10 :height 10))
                  1 1 2 2)))

(describe "rect-union"
  (it "spans both operands"
    (%expect-rect (rect-union (make-rect :width 2 :height 2)
                              (make-rect :x 3 :y 3 :width 2 :height 2))
                  0 0 5 5))
  (it "ignores an empty operand"
    (%expect-rect (rect-union (make-rect) (make-rect :x 1 :y 1 :width 2 :height 2))
                  1 1 2 2)
    (%expect-rect (rect-union (make-rect :x 1 :y 1 :width 2 :height 2) (make-rect))
                  1 1 2 2)))

(describe "layout-split"
  (it "fixed lengths plus a fill taking the remainder"
    (destructuring-bind (a b c)
        (layout-split (make-rect :width 100 :height 10) :horizontal
                      '((:length 20) (:fill 1) (:length 30)))
      (%expect-rect a 0 0 20 10)
      (%expect-rect b 20 0 50 10)
      (%expect-rect c 70 0 30 10)))
  (it "percentages"
    (destructuring-bind (a b)
        (layout-split (make-rect :width 100 :height 10) :horizontal
                      '((:percentage 50) (:percentage 50)))
      (%expect-rect a 0 0 50 10)
      (%expect-rect b 50 0 50 10)))
  (it "weighted fills split proportionally"
    (destructuring-bind (a b)
        (layout-split (make-rect :width 100 :height 10) :horizontal '((:fill 1) (:fill 3)))
      (%expect-rect a 0 0 25 10)
      (%expect-rect b 25 0 75 10)))
  (it "hands out an uneven remainder one unit at a time by largest-remainder"
    (destructuring-bind (a b c)
        (layout-split (make-rect :width 10 :height 4) :horizontal
                      '((:fill 1) (:fill 1) (:fill 1)))
      (%expect-rect a 0 0 4 4)
      (%expect-rect b 4 0 3 4)
      (%expect-rect c 7 0 3 4)))
  (it "reserves spacing between segments"
    (destructuring-bind (a b)
        (layout-split (make-rect :width 10 :height 4) :horizontal '((:fill 1) (:fill 1))
                      :spacing 2)
      (%expect-rect a 0 0 4 4)
      (%expect-rect b 6 0 4 4)))
  (it "splits rows in the :vertical direction"
    (destructuring-bind (a b)
        (layout-split (make-rect :width 6 :height 10) :vertical '((:length 3) (:fill 1)))
      (%expect-rect a 0 0 6 3)
      (%expect-rect b 0 3 6 7)))
  (it ":min provides a floor and still grows with the fill"
    (destructuring-bind (a b)
        (layout-split (make-rect :width 100 :height 4) :horizontal '((:min 30) (:fill 1)))
      (%expect-rect a 0 0 65 4)
      (%expect-rect b 65 0 35 4)))
  (it ":ratio splits proportionally to the given fraction"
    (destructuring-bind (a b)
        (layout-split (make-rect :width 90 :height 4) :horizontal '((:ratio 1 3) (:fill 1)))
      (%expect-rect a 0 0 30 4)
      (%expect-rect b 30 0 60 4)))
  (it "rejects an invalid ratio denominator before dividing"
    (flet ((rejects-ratio (denominator)
             (expect (lambda ()
                       (layout-split (make-rect :width 90 :height 4) :horizontal
                                     `((:ratio 1 ,denominator) (:fill 1))))
                     :to-throw
                     (lambda (c) (search "Invalid ratio denominator" (format nil "~A" c))))))
      (rejects-ratio 0)
      (rejects-ratio -1)
      (rejects-ratio :bad)))
  (it "signals a non-type-error for malformed constraint values"
    (flet ((rejects (constraints &rest keys)
             (expect (lambda ()
                       (apply #'layout-split (make-rect :width 10 :height 4) :horizontal
                              constraints keys))
                     :to-throw (lambda (c) (not (typep c 'type-error))))))
      (rejects '((:length :bad)))
      (rejects '((:fill :bad)))
      (rejects '(:bad))
      (rejects '((:fill 1)) :spacing :bad)))
  (it "preserves the rect's origin"
    (destructuring-bind (a b)
        (layout-split (make-rect :x 5 :y 3 :width 10 :height 2) :horizontal
                      '((:fill 1) (:fill 1)))
      (%expect-rect a 5 3 5 2)
      (%expect-rect b 10 3 5 2)))
  (it "a larger constraint set exercises the indexed remainder updates"
    (let* ((constraints (loop repeat 64 collect '(:fill 1)))
           (rects (layout-split (make-rect :width 257 :height 1) :horizontal constraints))
           (sizes (mapcar #'rect-width rects)))
      (expect (length rects) :to-be 64)
      (expect (reduce #'+ sizes) :to-be 257)
      (expect (every (lambda (size) (member size '(4 5))) sizes))))
  (it "an empty constraint list yields no rects"
    (expect (layout-split (make-rect :width 10 :height 4) :horizontal '()) :to-be-falsy)))
