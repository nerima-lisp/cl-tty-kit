(in-package #:cl-tty-kit)

(defstruct (screen (:constructor %make-screen)) "A fixed-size two-dimensional grid of CELL objects."
  (width 0 :type fixnum)
  (height 0 :type fixnum)
  (cells #() :type simple-vector)
  (generation 0 :type fixnum)
  (mutation-depth 0 :type fixnum)
  (mutation-generation -1 :type fixnum)
  (row-generations #() :type (simple-array fixnum (*)))
  (row-dirty-starts #() :type (simple-array fixnum (*)))
  (row-dirty-ends #() :type (simple-array fixnum (*)))
  (row-dirty-bits #() :type simple-vector))

(document-function 'screen-width "Return the width of SCREEN.")

(document-function 'screen-height "Return the height of SCREEN.")

(defun %make-row-dirty-bits (width height)
  (declare (type fixnum width height))
  (let ((rows (make-array height)))
    (loop for y fixnum below height
          do (setf (aref rows y)
                   (make-array width :element-type 'bit :initial-element 0)))
    rows))

(defun %copy-row-dirty-bits (row-dirty-bits)
  (declare (type simple-vector row-dirty-bits))
  (let ((copy (make-array (length row-dirty-bits))))
    (loop for y fixnum below (length row-dirty-bits)
          do (setf (aref copy y)
                   (copy-seq (aref row-dirty-bits y))))
    copy))

(defun %screen-touch (screen &optional (start-y 0) (end-y (screen-height screen))
                                  (start-x 0) (end-x (screen-width screen)))
  (let* ((mutation-depth (screen-mutation-depth screen))
         (mutation-generation (screen-mutation-generation screen))
         (generation (if (and (plusp mutation-depth)
                              (= mutation-generation (screen-generation screen)))
                         (screen-generation screen)
                         (the fixnum (1+ (screen-generation screen)))))
         (row-generations (screen-row-generations screen))
         (row-dirty-starts (screen-row-dirty-starts screen))
         (row-dirty-ends (screen-row-dirty-ends screen))
         (row-dirty-bits (screen-row-dirty-bits screen)))
    (declare (type fixnum mutation-depth mutation-generation generation start-y end-y start-x end-x)
             (type (simple-array fixnum (*)) row-generations row-dirty-starts row-dirty-ends)
             (type simple-vector row-dirty-bits))
    (setf (screen-generation screen) generation)
    (when (plusp mutation-depth)
      (setf (screen-mutation-generation screen) generation))
    (loop for y fixnum from start-y below end-y
          do (setf (aref row-generations y) generation
                   (aref row-dirty-starts y) (min (aref row-dirty-starts y) start-x)
                   (aref row-dirty-ends y) (max (aref row-dirty-ends y) end-x))
             (fill (aref row-dirty-bits y) 1 :start start-x :end end-x)))
  screen)

(defmacro with-screen-batch ((screen) &body body)
  "Coalesce cell mutations into one screen generation."
  `(let ((screen ,screen))
     (%assert-screen screen)
     (incf (screen-mutation-depth screen))
     (unwind-protect
          (progn ,@body)
       (decf (screen-mutation-depth screen))
       (when (zerop (screen-mutation-depth screen))
         (setf (screen-mutation-generation screen) -1)))
     screen))

(defun %screen-clear-dirty-cells (screen)
  (let ((row-dirty-bits (screen-row-dirty-bits screen))
        (row-dirty-starts (screen-row-dirty-starts screen))
        (row-dirty-ends (screen-row-dirty-ends screen))
        (width (screen-width screen)))
    (declare (type simple-vector row-dirty-bits)
             (type (simple-array fixnum (*)) row-dirty-starts row-dirty-ends)
             (type fixnum width))
    (loop for y fixnum below (screen-height screen)
          for start fixnum = (aref row-dirty-starts y)
          for end fixnum = (aref row-dirty-ends y)
          when (< start end)
            do (fill (the simple-bit-vector (aref row-dirty-bits y))
                     0 :start start :end end)
               (setf (aref row-dirty-starts y) width
                     (aref row-dirty-ends y) 0)))
  screen)

(define-validating-assert
  %assert-screen
  (screen)
  (screen-p screen)
  "Expected a SCREEN, got ~S."
  screen)

(define-validating-assert
  %assert-screen-rect
  (rect)
  (rect-p rect)
  "Expected a RECT, got ~S."
  rect)

(define-validating-assert
  %assert-cell-template
  (value)
  (or (null value) (cell-p value) (characterp value))
  "Cell template ~S must be NIL, a CELL, or a character."
  value)

(define-validating-assert
  %assert-cell-value
  (value)
  (or (cell-p value) (characterp value))
  "Cell value ~S must be a CELL or a character."
  value)

(defmacro %coerce-cell-template (value)
  `(let ((value ,value))
    (%assert-cell-template value)
    (cond
      ((cell-p value) value)
      ((characterp value) (make-cell :char value))
      (t (make-cell)))))

(defmacro %coerce-cell-value (value style style-supplied-p)
  `(let ((value ,value)
        (style ,style)
        (style-supplied-p ,style-supplied-p))
    (%assert-cell-value value)
    (cond
      ((cell-p value)
        (if style-supplied-p (make-cell :char (cell-char value) :style (%coerce-cell-style style))
          value))
      (t (make-cell :char value :style style)))))

(defmacro %coerce-cell-style (style)
  `(let ((style ,style))
     (and style
          (%normalize-cell-style style))))

;; Reject not just negatives but any dimension whose cell grid could not be
;; allocated: each side must be a non-negative fixnum and the total cell
;; count must stay within ARRAY-TOTAL-SIZE-LIMIT. Without the fixnum/product
;; bound a huge-but-non-negative dimension slips past validation and then
;; raises a raw TYPE-ERROR (fixnum slot store) or MAKE-ARRAY error instead of
;; the documented SCREEN-DIMENSIONS-INVALID.
(define-simple-assert
  %assert-screen-dimensions
  (width height)
  (and
    (typep width '(and fixnum unsigned-byte))
    (typep height '(and fixnum unsigned-byte))
    (< (* width height) array-total-size-limit))
  'screen-dimensions-invalid
  :width
  width
  :height
  height)

(defmacro %screen-index (screen x y)
  `(let ((screen ,screen)
         (x ,x)
         (y ,y))
     (let ((screen-width (screen-width screen)))
       (declare (type fixnum screen-width x y))
       (+ (* y screen-width) x))))

(defmacro %assert-screen-bounds (screen x y)
  `(let ((screen ,screen)
         (x ,x)
         (y ,y))
     (%assert-screen screen)
     (let ((screen-width (screen-width screen))
           (screen-height (screen-height screen)))
       (declare (type fixnum screen-width screen-height))
       (%assert
         (and
           (integerp x)
           (integerp y)
           (<= 0 x)
           (< x screen-width)
           (<= 0 y)
           (< y screen-height))
         'screen-index-out-of-bounds
         :screen
         screen
         :x
         x
         :y
         y
         :width
         screen-width
         :height
         screen-height))))

(define-validating-assert %assert-screen-offset (name value)
  (integerp value)
  "Screen ~A ~S must be an integer."
  name
  value)

(defmacro %assert-screen-rect-bounds (screen x y width height)
  `(let ((screen ,screen)
        (x ,x)
        (y ,y)
        (width ,width)
        (height ,height))
    (%assert-screen screen)
    (%assert-screen-dimensions width height)
    (when (and (plusp width) (plusp height))
      (%assert-screen-bounds screen x y)
      (%assert-screen-bounds screen (+ x (1- width)) (+ y (1- height))))))

(defmacro %assert-string-bounds (string start end)
  `(let ((string ,string)
        (start ,start)
        (end ,end))
    (unless (stringp string)
      (error "Expected a string, got ~S." string))
    (%assert
      (and
        (integerp start)
        (integerp end)
        (<= 0 start)
        (<= start end)
        (<= end (length string)))
      "Invalid string bounds START=~S END=~S for string of length ~D."
      start
      end
      (length string))))

(defun %screen-vector (width height &optional (cell (%blank-cell)))
  (declare (type fixnum width height))
  (let* ((size (* width height))
         (template (%coerce-cell-template cell)))
    (declare (type fixnum size))
    (make-array size :initial-element template)))

(defun screen-cell (screen x y)
  "Return the CELL at X and Y in SCREEN."
  (%assert-screen screen)
  (%assert-screen-bounds screen x y)
  (let ((index (%screen-index screen x y)))
    (declare (type fixnum index))
    (aref (screen-cells screen) index)))

(defun (setf screen-cell) (value screen x y)
  (%assert-screen-bounds screen x y)
  (%assert-cell-value value)
  (let* ((index (%screen-index screen x y))
         (old-cell (aref (screen-cells screen) index)))
    (declare (type fixnum index))
    (unless (or
        (and (cell-p value) (eq value old-cell))
        (and
          (characterp value)
          (char= value (cell-char old-cell))
          (null (cell-raw-style old-cell))))
      (setf (aref (screen-cells screen) index) (if (cell-p value) value
          (make-cell :char value)))
      (%screen-touch screen y (1+ y) x (1+ x))))
  screen)

(defun %screen-put-cell-normalized-style (screen x y char style)
  "Write CHAR with an already normalized STYLE without normalizing it again.
STYLE is owned by the caller and must not be mutated after this call."
  (%assert-screen-bounds screen x y)
  (let ((index (%screen-index screen x y)))
    (declare (type fixnum index))
    (setf (aref (screen-cells screen) index)
          (%make-cell :char char :raw-style style)))
  (%screen-touch screen y (1+ y) x (1+ x))
  screen)

(defun screen-put-cell (screen x y value &key (style nil style-supplied-p))
  "Write VALUE into SCREEN at X and Y, optionally overriding style."
  (%assert-screen-bounds screen x y)
  (%assert-cell-value value)
  (let* ((index (%screen-index screen x y))
         (old-cell (aref (screen-cells screen) index)))
    (if style-supplied-p (let ((new-cell (%coerce-cell-value value style t)))
        (unless (and
            (char= (cell-char new-cell) (cell-char old-cell))
            (equal (cell-raw-style new-cell) (cell-raw-style old-cell)))
          (setf (aref (screen-cells screen) index) new-cell)
          (%screen-touch screen y (1+ y) x (1+ x))))
      (unless (or
          (and (cell-p value) (eq value old-cell))
          (and
            (characterp value)
            (char= value (cell-char old-cell))
            (null (cell-raw-style old-cell))))
        (setf (aref (screen-cells screen) index) (%coerce-cell-value value style nil))
        (%screen-touch screen y (1+ y) x (1+ x)))))
  screen)

(defun make-screen (width height &key initial-cell)
  "Create a WIDTH by HEIGHT SCREEN initialized from INITIAL-CELL. INITIAL-CELL may be a CELL template, a character, or NIL for a blank cell. Screen mutation APIs replace cell values, so equal initial cells are shared safely. Invalid dimensions signal SCREEN-DIMENSIONS-INVALID."
  (%assert-screen-dimensions width height)
  (%make-screen
   :width width
   :height height
   :cells (%screen-vector width height initial-cell)
   :row-generations (make-array height :element-type 'fixnum :initial-element 0)
   :row-dirty-starts (make-array height :element-type 'fixnum :initial-element width)
   :row-dirty-ends (make-array height :element-type 'fixnum :initial-element 0)
   :row-dirty-bits (%make-row-dirty-bits width height)))

(defun screen-resize (screen width height &key initial-cell)
  "Resize SCREEN to WIDTH by HEIGHT in place, returning SCREEN. The overlapping top-left region is preserved and newly exposed cells use INITIAL-CELL."
  (%assert-screen-dimensions width height)
  (%assert-screen screen)
  (let* ((old-width (screen-width screen))
         (old-height (screen-height screen))
         (old-cells (screen-cells screen))
         (copy-width (if (> old-width width) width old-width))
         (copy-height (if (> old-height height) height old-height))
         (new-cells (make-array (* width height)
                                :initial-element (%coerce-cell-template initial-cell)
                                :element-type (array-element-type old-cells)))
         (new-row-generations (make-array height
                                          :element-type 'fixnum
                                          :initial-element 0))
         (new-row-dirty-starts (make-array height :element-type 'fixnum :initial-element width))
         (new-row-dirty-ends (make-array height :element-type 'fixnum :initial-element 0))
         (new-row-dirty-bits (%make-row-dirty-bits width height)))
    (declare (type fixnum old-width old-height copy-width copy-height))
    (loop for y fixnum below copy-height
          for source-start fixnum = (* y old-width)
          for destination-start fixnum = (* y width)
          do (replace new-cells old-cells
                      :start1 destination-start
                      :start2 source-start
                      :end2 (+ source-start copy-width)))
    (setf (screen-width screen) width
          (screen-height screen) height
          (screen-cells screen) new-cells
          (screen-row-generations screen) new-row-generations
          (screen-row-dirty-starts screen) new-row-dirty-starts
          (screen-row-dirty-ends screen) new-row-dirty-ends
          (screen-row-dirty-bits screen) new-row-dirty-bits)
    (%screen-touch screen)
    screen))
