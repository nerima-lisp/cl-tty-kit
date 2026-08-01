(in-package #:cl-tty-kit/test)

(defun %edge-collector (bucket)
  "Return an ON-EXIT callback that pushes each EDGE it is called with onto
the CDR of BUCKET (a fresh (CONS NIL NIL)), ignoring the entity argument."
  (lambda (entity edge) (declare (ignore entity)) (push edge (cdr bucket))))

(describe "make-entity"
  (it "stores every supplied field, defaulting velocity and position to zero"
    (let ((entity (make-entity)))
      (expect (entity-x entity) :to-be 0)
      (expect (entity-y entity) :to-be 0)
      (expect (entity-dx entity) :to-be 0)
      (expect (entity-dy entity) :to-be 0)
      (expect (entity-on-exit entity) :to-be nil)))
  (it "stores an explicit position, velocity, and on-exit callback"
    (let* ((callback (%edge-collector (cons nil nil)))
           (entity (make-entity :x 3 :y 4 :dx 1 :dy -1 :on-exit callback)))
      (expect (entity-x entity) :to-be 3)
      (expect (entity-y entity) :to-be 4)
      (expect (entity-dx entity) :to-be 1)
      (expect (entity-dy entity) :to-be -1)
      (expect (entity-on-exit entity) :to-be callback)))
  (it "signals a non-type-error for a malformed field"
    (expect-non-type-error (make-entity :x :bad))
    (expect-non-type-error (make-entity :dx :bad))
    (expect-non-type-error (make-entity :on-exit :bad))))

(describe "entity-tick"
  (it "adds velocity to position and returns the entity"
    (let ((entity (make-entity :x 1 :y 2 :dx 3 :dy -1)))
      (expect (entity-tick entity 80 24) :to-be entity)
      (expect (entity-x entity) :to-be 4)
      (expect (entity-y entity) :to-be 1)))
  (it "advances repeatedly across successive ticks"
    (let ((entity (make-entity :x 0 :y 0 :dx 1 :dy 2)))
      (entity-tick entity 80 24)
      (entity-tick entity 80 24)
      (entity-tick entity 80 24)
      (expect (entity-x entity) :to-be 3)
      (expect (entity-y entity) :to-be 6)))
  (it "does not call on-exit while the entity stays in bounds"
    (let* ((bucket (cons nil nil))
           (entity (make-entity :x 0 :y 0 :dx 1 :dy 1 :on-exit (%edge-collector bucket))))
      (entity-tick entity 10 10)
      (expect (cdr bucket) :to-equal '())))
  (it "signals a non-type-error for a malformed entity or bound"
    (expect-non-type-error (entity-tick :not-an-entity 10 10))
    (expect-non-type-error (entity-tick (make-entity) :bad 10))
    (expect-non-type-error (entity-tick (make-entity) 10 :bad))))

(describe "entity-tick off-bounds callback, all four edges"
  (it "fires :left when the new x is negative"
    (let* ((bucket (cons nil nil))
           (entity (make-entity :x 0 :y 5 :dx -1 :dy 0 :on-exit (%edge-collector bucket))))
      (entity-tick entity 10 10)
      (expect (cdr bucket) :to-equal '(:left))))
  (it "fires :right when the new x reaches or passes width"
    (let* ((bucket (cons nil nil))
           (entity (make-entity :x 9 :y 5 :dx 1 :dy 0 :on-exit (%edge-collector bucket))))
      (entity-tick entity 10 10)
      (expect (cdr bucket) :to-equal '(:right))))
  (it "fires :top when the new y is negative"
    (let* ((bucket (cons nil nil))
           (entity (make-entity :x 5 :y 0 :dx 0 :dy -1 :on-exit (%edge-collector bucket))))
      (entity-tick entity 10 10)
      (expect (cdr bucket) :to-equal '(:top))))
  (it "fires :bottom when the new y reaches or passes height"
    (let* ((bucket (cons nil nil))
           (entity (make-entity :x 5 :y 9 :dx 0 :dy 1 :on-exit (%edge-collector bucket))))
      (entity-tick entity 10 10)
      (expect (cdr bucket) :to-equal '(:bottom))))
  (it "fires both edges, left-before-top ordering, when exiting through a corner"
    (let* ((bucket (cons nil nil))
           (entity (make-entity :x 0 :y 0 :dx -1 :dy -1 :on-exit (%edge-collector bucket))))
      (entity-tick entity 10 10)
      (expect (nreverse (cdr bucket)) :to-equal '(:left :top))))
  (it "passes the entity itself as the first callback argument"
    (let* ((seen nil)
           (entity (make-entity :x 0 :y 5 :dx -1 :dy 0
                                :on-exit (lambda (e edge) (declare (ignore edge)) (setf seen e)))))
      (entity-tick entity 10 10)
      (expect seen :to-be entity))))
