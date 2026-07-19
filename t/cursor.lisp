(in-package #:cl-tty-kit/test)

(defun %assert-cursor-parameter-invalid (thunk parameter value expected)
  (let ((failed nil))
    (handler-case
        (funcall thunk)
      (cursor-parameter-invalid (condition)
        (is (eq parameter (cursor-parameter-invalid-parameter condition)))
        (is (equal value (cursor-parameter-invalid-value condition)))
        (is (string= expected (cursor-parameter-invalid-expected condition)))
        (setf failed t)))
    (is failed)))

(defun test-cursor ()
  (let ((cursor (make-cursor)))
    (is (= 0 (cursor-x cursor)))
    (is (= 0 (cursor-y cursor)))
    (is (cursor-visible-p cursor))
    (move-cursor cursor 5 6 :width 10 :height 10)
    (is (= 5 (cursor-x cursor)))
    (is (= 6 (cursor-y cursor)))
    (move-cursor cursor 50 60 :width 10 :height 10)
    (is (= 9 (cursor-x cursor)))
    (is (= 9 (cursor-y cursor)))
    (move-cursor cursor 3 4 :width 0 :height 0)
    (is (= 0 (cursor-x cursor)))
    (is (= 0 (cursor-y cursor)))
    (setf (cursor-x cursor) 7
          (cursor-y cursor) 8)
    (is (= 7 (cursor-x cursor)))
    (is (= 8 (cursor-y cursor)))
    (setf (cursor-visible-p cursor) nil)
    (is (not (cursor-visible-p cursor))))
  ;; The documented contract is "any non-negative integer", so a bignum
  ;; coordinate must be stored, not rejected by the slot's numeric type.
  (let ((cursor (make-cursor :x (expt 10 30) :y (1+ most-positive-fixnum))))
    (is (= (expt 10 30) (cursor-x cursor)))
    (is (= (1+ most-positive-fixnum) (cursor-y cursor)))
    (setf (cursor-x cursor) (* 2 (expt 10 30)))
    (is (= (* 2 (expt 10 30)) (cursor-x cursor))))
  (%assert-cursor-parameter-invalid
   (lambda () (make-cursor :x -1))
   :x -1 "a non-negative integer")
  (%assert-cursor-parameter-invalid
   (lambda () (make-cursor :y -1))
   :y -1 "a non-negative integer")
  (%assert-cursor-parameter-invalid
   (lambda () (make-cursor :visible :maybe))
   :visible :maybe "a boolean")
  (%assert-cursor-parameter-invalid
   (lambda () (move-cursor (make-cursor) -1 0))
   :x -1 "a non-negative integer")
  (%assert-cursor-parameter-invalid
   (lambda () (move-cursor (make-cursor) 0 -1))
   :y -1 "a non-negative integer")
  (%assert-cursor-parameter-invalid
   (lambda () (move-cursor (make-cursor) 0 0 :width -1))
   :width -1 "a non-negative integer")
  (%assert-cursor-parameter-invalid
   (lambda () (move-cursor (make-cursor) 0 0 :height -1))
   :height -1 "a non-negative integer")
  (%assert-cursor-parameter-invalid
   (lambda ()
     (let ((cursor (make-cursor)))
       (setf (cursor-x cursor) -1)))
   :x -1 "a non-negative integer")
  (%assert-cursor-parameter-invalid
   (lambda ()
     (let ((cursor (make-cursor)))
       (setf (cursor-y cursor) -1)))
   :y -1 "a non-negative integer")
  (%assert-cursor-parameter-invalid
   (lambda ()
     (let ((cursor (make-cursor)))
       (setf (cursor-visible-p cursor) :maybe)))
   :visible :maybe "a boolean"))
