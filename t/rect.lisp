(in-package #:cl-tty-kit/test)

(defun %rect-is (rect x y width height)
  (is (= x (rect-x rect)))
  (is (= y (rect-y rect)))
  (is (= width (rect-width rect)))
  (is (= height (rect-height rect))))

(defun %rect-signals-non-type-error (thunk)
  (handler-case
      (progn
        (funcall thunk)
        (is nil))
    (type-error (condition)
      (declare (ignore condition))
      (is nil))
    (error (condition)
      (declare (ignore condition))
      (is t))))

(defun %test-make-rect ()
  (%rect-is (make-rect :x 1 :y 2 :width 3 :height 4) 1 2 3 4)
  (%rect-is (make-rect) 0 0 0 0)
  (signals (error c) (make-rect :x -1) (is c))
  (signals (error c) (make-rect :width -2) (is c))
  (%rect-signals-non-type-error (lambda () (make-rect :x :bad))))

(defun %test-rect-inset ()
  (%rect-is (rect-inset (make-rect :width 10 :height 6) :all 1) 1 1 8 4)
  (%rect-is (rect-inset (make-rect :width 10 :height 6) :left 2 :right 1) 2 0 7 6)
  (%rect-is (rect-inset (make-rect :width 10 :height 6) :all 1 :top 2) 1 2 8 3)
  ;; Over-large inset collapses to a zero-size rect at the inset origin.
  (%rect-is (rect-inset (make-rect :width 4 :height 4) :all 3) 3 3 0 0)
  (%rect-signals-non-type-error
   (lambda () (rect-inset (make-rect) :left :bad))))

(defun %test-rect-split ()
  (multiple-value-bind (left right)
      (rect-split-horizontal (make-rect :width 10 :height 4) 4)
    (%rect-is left 0 0 4 4)
    (%rect-is right 4 0 6 4))
  (multiple-value-bind (left right)
      (rect-split-horizontal (make-rect :width 10 :height 4) 4 :gap 1)
    (%rect-is left 0 0 4 4)
    (%rect-is right 5 0 5 4))
  ;; AT beyond the width clamps; the right part is empty.
  (multiple-value-bind (left right)
      (rect-split-horizontal (make-rect :width 10 :height 4) 20)
    (%rect-is left 0 0 10 4)
    (%rect-is right 10 0 0 4))
  (multiple-value-bind (top bottom)
      (rect-split-vertical (make-rect :width 6 :height 10) 3)
    (%rect-is top 0 0 6 3)
    (%rect-is bottom 0 3 6 7))
  ;; Origin is preserved through a split.
  (multiple-value-bind (left right)
      (rect-split-horizontal (make-rect :x 2 :y 3 :width 10 :height 4) 4)
    (%rect-is left 2 3 4 4)
    (%rect-is right 6 3 6 4))
  (%rect-signals-non-type-error
   (lambda () (rect-split-horizontal (make-rect) :bad)))
  (%rect-signals-non-type-error
   (lambda () (rect-split-vertical (make-rect) 1 :gap :bad))))

(defun %test-rect-contains ()
  (let ((rect (make-rect :x 1 :y 1 :width 3 :height 3)))
    (is (rect-contains-p rect 1 1))
    (is (rect-contains-p rect 3 3))
    (is (not (rect-contains-p rect 4 1)))
    (is (not (rect-contains-p rect 0 1)))
    (is (not (rect-contains-p rect 1 4)))
    (%rect-signals-non-type-error
     (lambda () (rect-contains-p rect :bad 1)))))

(defun %test-rect-measure ()
  (is (rect-empty-p (make-rect :width 0 :height 3)))
  (is (rect-empty-p (make-rect :width 3 :height 0)))
  (is (not (rect-empty-p (make-rect :width 3 :height 3))))
  (is (= 12 (rect-area (make-rect :width 3 :height 4))))
  (is (= 0 (rect-area (make-rect :width 0 :height 4)))))

(defun %test-rect-intersect ()
  (%rect-is (rect-intersect (make-rect :width 4 :height 4)
                            (make-rect :x 2 :y 2 :width 4 :height 4))
            2 2 2 2)
  ;; Non-overlapping rects intersect to an empty rect.
  (is (rect-empty-p (rect-intersect (make-rect :width 2 :height 2)
                                    (make-rect :x 5 :y 5 :width 2 :height 2))))
  ;; Intersecting with a containing rect is a no-op clip.
  (%rect-is (rect-intersect (make-rect :x 1 :y 1 :width 2 :height 2)
                            (make-rect :width 10 :height 10))
            1 1 2 2))

(defun %test-rect-union ()
  (%rect-is (rect-union (make-rect :width 2 :height 2)
                        (make-rect :x 3 :y 3 :width 2 :height 2))
            0 0 5 5)
  ;; An empty operand is ignored.
  (%rect-is (rect-union (make-rect) (make-rect :x 1 :y 1 :width 2 :height 2))
            1 1 2 2)
  (%rect-is (rect-union (make-rect :x 1 :y 1 :width 2 :height 2) (make-rect))
            1 1 2 2))

(defun %test-layout-split ()
  ;; Fixed lengths plus a fill taking the remainder.
  (destructuring-bind (a b c)
      (layout-split (make-rect :width 100 :height 10) :horizontal
                    '((:length 20) (:fill 1) (:length 30)))
    (%rect-is a 0 0 20 10)
    (%rect-is b 20 0 50 10)
    (%rect-is c 70 0 30 10))
  ;; Percentages.
  (destructuring-bind (a b)
      (layout-split (make-rect :width 100 :height 10) :horizontal
                    '((:percentage 50) (:percentage 50)))
    (%rect-is a 0 0 50 10)
    (%rect-is b 50 0 50 10))
  ;; Weighted fills split proportionally.
  (destructuring-bind (a b)
      (layout-split (make-rect :width 100 :height 10) :horizontal
                    '((:fill 1) (:fill 3)))
    (%rect-is a 0 0 25 10)
    (%rect-is b 25 0 75 10))
  ;; Spacing sits between segments.
  (destructuring-bind (a b)
      (layout-split (make-rect :width 10 :height 4) :horizontal
                    '((:fill 1) (:fill 1)) :spacing 2)
    (%rect-is a 0 0 4 4)
    (%rect-is b 6 0 4 4))
  ;; Vertical direction splits rows.
  (destructuring-bind (a b)
      (layout-split (make-rect :width 6 :height 10) :vertical
                    '((:length 3) (:fill 1)))
    (%rect-is a 0 0 6 3)
    (%rect-is b 0 3 6 7))
  ;; :MIN provides a floor and still grows with the fill.
  (destructuring-bind (a b)
      (layout-split (make-rect :width 100 :height 4) :horizontal
                    '((:min 30) (:fill 1)))
    (%rect-is a 0 0 65 4)
    (%rect-is b 65 0 35 4))
  ;; Ratio.
  (destructuring-bind (a b)
      (layout-split (make-rect :width 90 :height 4) :horizontal
                    '((:ratio 1 3) (:fill 1)))
    (%rect-is a 0 0 30 4)
    (%rect-is b 30 0 60 4))
  ;; Invalid ratio denominators are rejected before division.
  (signals (error c)
      (layout-split (make-rect :width 90 :height 4) :horizontal
                    '((:ratio 1 0) (:fill 1)))
    (is (search "Invalid ratio denominator" (format nil "~A" c))))
  (signals (error c)
      (layout-split (make-rect :width 90 :height 4) :horizontal
                    '((:ratio 1 -1) (:fill 1)))
    (is (search "Invalid ratio denominator" (format nil "~A" c))))
  (signals (error c)
      (layout-split (make-rect :width 90 :height 4) :horizontal
                    '((:ratio 1 :bad) (:fill 1)))
    (is (search "Invalid ratio denominator" (format nil "~A" c))))
  (%rect-signals-non-type-error
   (lambda ()
     (layout-split (make-rect :width 10 :height 4) :horizontal
                   '((:length :bad)))))
  (%rect-signals-non-type-error
   (lambda ()
     (layout-split (make-rect :width 10 :height 4) :horizontal
                   '((:fill :bad)))))
  (%rect-signals-non-type-error
   (lambda ()
     (layout-split (make-rect :width 10 :height 4) :horizontal
                   '(:bad))))
  (%rect-signals-non-type-error
   (lambda ()
     (layout-split (make-rect :width 10 :height 4) :horizontal
                   '((:fill 1)) :spacing :bad)))
  ;; The rect origin is preserved.
  (destructuring-bind (a b)
      (layout-split (make-rect :x 5 :y 3 :width 10 :height 2) :horizontal
                    '((:fill 1) (:fill 1)))
    (%rect-is a 5 3 5 2)
    (%rect-is b 10 3 5 2))
  (is (null (layout-split (make-rect :width 10 :height 4) :horizontal '()))))

(defun test-rect ()
  (%test-make-rect)
  (%test-rect-inset)
  (%test-rect-split)
  (%test-rect-contains)
  (%test-rect-measure)
  (%test-rect-intersect)
  (%test-rect-union)
  (%test-layout-split)
  t)
