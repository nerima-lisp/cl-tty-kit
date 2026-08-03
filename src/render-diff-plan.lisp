(in-package #:cl-tty-kit)

(defstruct (diff-plan (:constructor %make-diff-plan (operations)) (:copier nil))
  "Reusable pairs of inclusive diff starts and exclusive ends.

An end of -1 represents an EL clear-line operation.  The renderer owns one of
these plans, avoiding a second cell comparison pass for its steady-state path."
  (operations #() :type vector))

(defun %make-screen-diff-plan (screen)
  (let ((cell-count (length (screen-cells screen))))
    (declare (type fixnum cell-count))
    (%make-diff-plan
      (make-array
        (* 2 cell-count)
        :element-type 'fixnum
        :fill-pointer 0))))

(defun %clear-diff-plan (plan)
  (setf (fill-pointer (diff-plan-operations plan)) 0)
  plan)

(defun %record-diff-operation (plan start end)
  (let* ((operations (diff-plan-operations plan))
         (operation-index (fill-pointer operations)))
    (declare (type (vector fixnum) operations)
             (type fixnum operation-index start end))
    (setf (aref operations operation-index) start
          (aref operations (1+ operation-index)) end
          (fill-pointer operations) (+ operation-index 2)))
  plan)

(defun %cell-equal-p (left right)
  (or (eq left right)
      (and (char= (cell-char left) (cell-char right))
           (or (equal (cell-raw-style left) (cell-raw-style right))
               ;; Distinct input styles can still emit the same terminal SGR.
               (equal (%cell-style-sequence left)
                      (%cell-style-sequence right))))))

(defun %render-blank-cell-p (cell)
  (and (char= (cell-char cell) #\Space) (null (%cell-style-sequence cell))))

(defun %same-screen-dimensions-p (screen previous)
  (and
    previous
    (= (screen-width screen) (screen-width previous))
    (= (screen-height screen) (screen-height previous))))

(defun %row-blank-suffix-start (cells row-start width)
  (declare (type simple-vector cells)
           (type fixnum row-start width))
  (do ((offset (1- width) (1- offset))
       (start width))
    ((minusp offset) start)
    (if (%render-blank-cell-p (aref cells (+ row-start offset))) (setf start offset)
      (return start))))

(defun %diff-cursor-length (x y)
  (declare (type fixnum x y)
           (optimize (speed 3) (safety 1)))
  (flet ((positive-decimal-digit-count (number)
           (declare (type fixnum number))
           (let ((digits 1)
                 (remaining number))
             (declare (type fixnum digits remaining))
             (loop while (>= remaining 10)
                   do (incf digits)
                      (setf remaining (truncate remaining 10)))
             digits)))
    (the fixnum
      (+
        4
        (positive-decimal-digit-count (1+ y))
        (positive-decimal-digit-count (1+ x))))))

(defun %plan-diff-length (screen previous plan &optional changed-since)
    "Record sparse updates in PLAN and return their rendered length."
    (%clear-diff-plan plan)
    (if (and changed-since
         (eql changed-since (screen-generation screen)))
    0
    (let ((cells (screen-cells screen))
          (previous-cells (screen-cells previous))
          (row-generations (screen-row-generations screen))
          (width (screen-width screen))
          (height (screen-height screen))
          (length 0))
      (declare (type simple-vector cells previous-cells) (type (simple-array fixnum (*)) row-generations))
      (do ((y 0 (1+ y))
           (row-start 0 (+ row-start width)))
          ((>= y height) length)
        (declare (type fixnum y row-start))
        (let ((row-end (if (and changed-since
                                (<= (aref row-generations y) changed-since))
                           row-start
                           (+ row-start width)))
                (blank-suffix-start nil))
            (declare (type fixnum row-end)
                     (type fixnum width height length))
            (do ((index row-start))
                ((>= index row-end))
              (declare (type fixnum index))
            (if (%cell-equal-p (aref cells index) (aref previous-cells index))
                (incf index)
                (let ((x (- index row-start)))
                  (declare (type fixnum x))
                  (when (and (null blank-suffix-start)
                             (%render-blank-cell-p (aref cells index)))
                    (setf blank-suffix-start
                          (%row-blank-suffix-start cells row-start width)))
                  (if (and blank-suffix-start (>= x blank-suffix-start))
                      (progn
                        (%record-diff-operation plan index -1)
                        (incf length (+ (%diff-cursor-length x y) 4))
                        (setf index row-end))
                      (let ((start index))
                        (do ()
                            ((or (>= index row-end)
                                 (%cell-equal-p
                                   (aref cells index)
                                   (aref previous-cells index))))
                          (incf length (%cell-rendered-length (aref cells index)))
                          (incf index))
                        (%record-diff-operation plan start index)
                        (incf length (%diff-cursor-length x y))))))))))))

(defun %copy-diff-plan-cells (front back plan)
    "Apply PLANs changed cells from BACK to FRONT without allocating."
    (let ((front-cells (screen-cells front))
          (back-cells (screen-cells back))
          (width (screen-width back))
          (operations (diff-plan-operations plan)))
      (declare (type simple-vector front-cells back-cells)
               (type (vector fixnum) operations)
               (type fixnum width))
      (do ((operation-index 0 (+ operation-index 2))
           (operation-limit (fill-pointer operations)))
          ((>= operation-index operation-limit) front)
        (declare (type fixnum operation-index operation-limit))
        (let ((start (aref operations operation-index))
              (end (aref operations (1+ operation-index))))
          (declare (type fixnum start end))
          (when (minusp end)
            (setf end (+ start (- width (mod start width)))))
          (replace front-cells back-cells
                   :start1 start :end1 end :start2 start :end2 end)))))
