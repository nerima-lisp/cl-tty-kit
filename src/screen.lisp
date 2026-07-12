(in-package #:cl-tty-kit)

(defstruct (screen (:constructor %make-screen))
  "A fixed-size two-dimensional grid of CELL objects."
  (width 0 :type fixnum)
  (height 0 :type fixnum)
  (cells #() :type simple-vector))

(setf (documentation 'screen-width 'function)
      "Return the width of SCREEN.")

(setf (documentation 'screen-height 'function)
      "Return the height of SCREEN.")

(setf (documentation 'screen-cells 'function)
      "Return the backing vector of cells for SCREEN.")

(defun %coerce-cell-template (value)
  (etypecase value
    (cell (copy-cell value))
    (character (make-cell :char value))
    (null (make-cell))))

(defun %coerce-cell-style (style)
  (and style (copy-list (%normalize-cell-style style))))

(defun %assert-screen-dimensions (width height)
  (unless (and (typep width '(integer 0 *))
               (typep height '(integer 0 *)))
    (error 'screen-dimensions-invalid
           :width width
           :height height)))

(defun %screen-index (screen x y)
  (+ (* y (screen-width screen)) x))

(defun %assert-screen-bounds (screen x y)
  (unless (and (<= 0 x) (< x (screen-width screen))
               (<= 0 y) (< y (screen-height screen)))
    (error 'screen-index-out-of-bounds
           :screen screen
           :x x
           :y y
           :width (screen-width screen)
           :height (screen-height screen))))

(defun %assert-screen-rect-bounds (screen x y width height)
  (%assert-screen-dimensions width height)
  (when (and (plusp width) (plusp height))
    (%assert-screen-bounds screen x y)
    (%assert-screen-bounds screen (+ x (1- width)) (+ y (1- height)))))

(defun %screen-vector (width height &optional (cell (%blank-cell)))
  (make-array (* width height)
              :initial-contents
              (loop repeat (* width height)
                    collect (%coerce-cell-template cell))))

(defun screen-cell (screen x y)
  "Return the CELL at X and Y in SCREEN."
  (%assert-screen-bounds screen x y)
  (aref (screen-cells screen) (%screen-index screen x y)))

(defun (setf screen-cell) (value screen x y)
  (%assert-screen-bounds screen x y)
  (setf (aref (screen-cells screen) (%screen-index screen x y))
        (etypecase value
          (cell (copy-cell value))
          (character (make-cell :char value)))))

(defun screen-put-cell (screen x y value &key (style nil style-supplied-p))
  "Write VALUE into SCREEN at X and Y, optionally overriding style."
  (setf (screen-cell screen x y)
        (etypecase value
          (cell (make-cell :char (cell-char value)
                           :style (if style-supplied-p
                                      (%coerce-cell-style style)
                                      (cell-style value))))
          (character (make-cell :char value :style style))))
  screen)

