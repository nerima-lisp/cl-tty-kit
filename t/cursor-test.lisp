(in-package #:cl-tty-kit/test)

(defun %cursor-parameter-invalid-matcher (parameter value expected)
  (lambda (condition)
    (and (typep condition 'cursor-parameter-invalid)
         (eq parameter (cursor-parameter-invalid-parameter condition))
         (equal value (cursor-parameter-invalid-value condition))
         (string= expected (cursor-parameter-invalid-expected condition)))))

(defmacro expect-cursor-parameter-invalid (thunk parameter value expected)
  `(expect ,thunk :to-throw (%cursor-parameter-invalid-matcher ,parameter ,value ,expected)))

(describe "make-cursor"
  (it "starts at the origin, visible"
    (let ((cursor (make-cursor)))
      (expect (cursor-x cursor) :to-be 0)
      (expect (cursor-y cursor) :to-be 0)
      (expect (cursor-visible-p cursor) :to-be-truthy)))
  (it "stores a bignum coordinate without narrowing: the contract is any non-negative integer"
    (let ((cursor (make-cursor :x (expt 10 30) :y (1+ most-positive-fixnum))))
      (expect (cursor-x cursor) :to-be (expt 10 30))
      (expect (cursor-y cursor) :to-be (1+ most-positive-fixnum))))
  (it "rejects a negative x"
    (expect-cursor-parameter-invalid (lambda () (make-cursor :x -1))
                                     :x -1 "a non-negative integer"))
  (it "rejects a negative y"
    (expect-cursor-parameter-invalid (lambda () (make-cursor :y -1))
                                     :y -1 "a non-negative integer"))
  (it "rejects a non-boolean visible"
    (expect-cursor-parameter-invalid (lambda () (make-cursor :visible :maybe))
                                     :visible :maybe "a boolean")))

(describe "move-cursor"
  (it "stores the coordinate verbatim when no width/height is given"
    (let ((cursor (make-cursor)))
      (move-cursor cursor 15 20)
      (expect (cursor-x cursor) :to-be 15)
      (expect (cursor-y cursor) :to-be 20)))
  (it "leaves an in-bounds coordinate alone when width/height is given"
    (let ((cursor (make-cursor)))
      (move-cursor cursor 5 6 :width 10 :height 10)
      (expect (cursor-x cursor) :to-be 5)
      (expect (cursor-y cursor) :to-be 6)))
  (it "clamps to the last valid column and row when width/height is given"
    (let ((cursor (make-cursor)))
      (move-cursor cursor 50 60 :width 10 :height 10)
      (expect (cursor-x cursor) :to-be 9)
      (expect (cursor-y cursor) :to-be 9)))
  (it "clamps to zero for a zero-width, zero-height region"
    (let ((cursor (make-cursor)))
      (move-cursor cursor 3 4 :width 0 :height 0)
      (expect (cursor-x cursor) :to-be 0)
      (expect (cursor-y cursor) :to-be 0)))
  (it "rejects a negative x"
    (expect-cursor-parameter-invalid (lambda () (move-cursor (make-cursor) -1 0))
                                     :x -1 "a non-negative integer"))
  (it "rejects a negative y"
    (expect-cursor-parameter-invalid (lambda () (move-cursor (make-cursor) 0 -1))
                                     :y -1 "a non-negative integer"))
  (it "rejects a negative width"
    (expect-cursor-parameter-invalid (lambda () (move-cursor (make-cursor) 0 0 :width -1))
                                     :width -1 "a non-negative integer"))
  (it "rejects a negative height"
    (expect-cursor-parameter-invalid (lambda () (move-cursor (make-cursor) 0 0 :height -1))
                                     :height -1 "a non-negative integer")))

(describe "setf accessors"
  (it "cursor-x and cursor-y are setfable"
    (let ((cursor (make-cursor)))
      (setf (cursor-x cursor) 7
            (cursor-y cursor) 8)
      (expect (cursor-x cursor) :to-be 7)
      (expect (cursor-y cursor) :to-be 8)))
  (it "cursor-visible-p is setfable"
    (let ((cursor (make-cursor)))
      (setf (cursor-visible-p cursor) nil)
      (expect (cursor-visible-p cursor) :to-be-falsy)))
  (it "growing (setf cursor-x) keeps the bignum contract"
    (let ((cursor (make-cursor)))
      (setf (cursor-x cursor) (* 2 (expt 10 30)))
      (expect (cursor-x cursor) :to-be (* 2 (expt 10 30)))))
  (it "rejects a negative (setf cursor-x)"
    (expect-cursor-parameter-invalid
     (lambda () (let ((cursor (make-cursor))) (setf (cursor-x cursor) -1)))
     :x -1 "a non-negative integer"))
  (it "rejects a negative (setf cursor-y)"
    (expect-cursor-parameter-invalid
     (lambda () (let ((cursor (make-cursor))) (setf (cursor-y cursor) -1)))
     :y -1 "a non-negative integer"))
  (it "rejects a non-boolean (setf cursor-visible-p)"
    (expect-cursor-parameter-invalid
     (lambda () (let ((cursor (make-cursor))) (setf (cursor-visible-p cursor) :maybe)))
     :visible :maybe "a boolean")))
