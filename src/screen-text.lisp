(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Higher-level screen text placement
;;;
;;; These build on SCREEN-WRITE-STRING and the text-layout helpers to place
;;; multi-line and wrapped text, clipping to the grid instead of signaling so a
;;; block of content can be dropped into a region without the caller measuring.
;;; --------------------------------------------------------------------------

(defun %assert-screen-text-screen (screen)
  (%assert (screen-p screen) "SCREEN ~S must be a screen." screen))

(defun %assert-screen-text-rect (rect)
  (%assert (rect-p rect) "RECT ~S must be a rect." rect))

(defun %assert-screen-text-string (name value)
  (%assert (stringp value) "~A ~S must be a string." name value))

(defun %assert-screen-text-coordinate (name value)
  (%assert (integerp value) "~A ~S must be an integer coordinate." name value))

(defun %assert-screen-text-lines (lines)
  (%assert (and (%proper-list-p lines)
               (every #'stringp lines)) "LINES ~S must be a proper list of strings." lines))

(defun %assert-screen-text-align (align)
  (%assert (member align '(:left :right :center) :test #'eq)
           "ALIGN ~S must be one of :LEFT, :RIGHT, or :CENTER." align))

(defun %assert-screen-text-vertical (vertical)
  (%assert (member vertical '(:top :middle :bottom) :test #'eq)
           "VERTICAL ~S must be one of :TOP, :MIDDLE, or :BOTTOM." vertical))



(defun screen-write-aligned (screen rect text &key (align :left) (vertical :top) style)
  "Write the single line TEXT inside RECT, returning SCREEN.
ALIGN places it horizontally (:LEFT, :RIGHT, or :CENTER) and VERTICAL places it
(:TOP, :MIDDLE, or :BOTTOM) within the rectangle; TEXT is clipped to RECT's width
so it never spills. STYLE, when non-NIL, applies to every written cell. This is
the natural way to center a label in a panel carved out with RECT-INSET."
  (%assert-screen-text-screen screen)
  (%assert-screen-text-rect rect)
  (%assert-screen-text-string "TEXT" text)
  (%assert-screen-text-align align)
  (%assert-screen-text-vertical vertical)
  (let ((rect-width (rect-width rect))
        (rect-height (rect-height rect)))
    (when (and (plusp rect-width) (plusp rect-height))
      (multiple-value-bind (end cells) (%cells-prefix-end text rect-width)
        (let* ((column-offset (ecase align
                                (:left 0)
                                (:right (- rect-width cells))
                                (:center (floor (- rect-width cells) 2))))
               (row-offset (ecase vertical
                             (:top 0)
                             (:middle (floor (1- rect-height) 2))
                             (:bottom (1- rect-height))))
               (x (+ (rect-x rect) (max 0 column-offset)))
               (y (+ (rect-y rect) row-offset)))
          (when (plusp end)
            (if style
                (screen-write-string screen x y text :style style :end end)
                (screen-write-string screen x y text :end end)))))))
  screen)

(defun screen-write-lines (screen x y lines &key style)
  "Write each string in LINES on successive rows starting at (X, Y), returning
SCREEN. Each line is clipped to the columns available from X to the right edge,
and rows outside the screen are skipped, so an over-long or over-tall block never
signals. STYLE, when non-NIL, applies to every written cell."
  (%assert-screen-text-screen screen)
  (%assert-screen-text-coordinate "X" x)
  (%assert-screen-text-coordinate "Y" y)
  (%assert-screen-text-lines lines)
  (let ((width (screen-width screen))
        (height (screen-height screen))
        (normalized-style nil)
        (style-normalized-p nil))
    (when (and (<= 0 x) (< x width))
      (let ((available (- width x)))
        (loop for line in lines
              for row from y
              when (and (<= 0 row) (< row height))
                do (let ((end (%cells-prefix-end line available)))
                     (when (plusp end)
                       (if style
                           (progn
                             (unless style-normalized-p
                               (setf normalized-style (%coerce-cell-style style)
                                     style-normalized-p t))
                             (%screen-write-string-normalized
                              screen x row line 0 end normalized-style))
                           (%screen-write-string-normalized
                            screen x row line 0 end nil)))))))
  screen))

(defun screen-write-wrapped (screen x y width text &key style)
  "Word-wrap TEXT to WIDTH and write it at X,Y.

Returns SCREEN and the number of visible lines written. TEXT must be a string and
WIDTH a positive integer. Existing cells after a line's visible content are
preserved, as with SCREEN-WRITE-LINES."
  (%assert-screen-text-screen screen)
  (%assert-screen-text-coordinate "X" x)
  (%assert-screen-text-coordinate "Y" y)
  (%assert-screen-text-string "TEXT" text)
  (%assert (and (integerp width) (plusp width))
           "WIDTH ~S must be a positive integer." width)
  (let ((screen-width (screen-width screen))
        (screen-height (screen-height screen)))
    (if (or (minusp x) (>= x screen-width) (>= y screen-height))
        (values screen 0)
        (let ((available (- screen-width x))
              (normalized-style nil)
              (style-normalized-p nil)
              (visible-count 0))
          (%call-with-wrapped-lines
           text width
           (let ((row y))
             (lambda (line)
               (cond
                 ((minusp row))
                 ((>= row screen-height)
                  nil)
                 (t
                  (let ((end (%cells-prefix-end line available)))
                    (when (plusp end)
                      (if style
                          (progn
                            (unless style-normalized-p
                              (setf normalized-style (%coerce-cell-style style)
                                    style-normalized-p t))
                            (%screen-write-string-normalized
                             screen x row line 0 end normalized-style))
                          (%screen-write-string-normalized
                           screen x row line 0 end nil)))
                    (incf visible-count))))
               (incf row)
               (< row screen-height))))
          (values screen visible-count)))))

(defun screen-to-string (screen)
  "Return SCREEN's contents as plain text: each row's stored characters joined
by newlines, with no styling. A double-width glyph appears once followed by its
spacer, matching the grid. Useful for snapshots and test assertions."
  (%assert-screen-text-screen screen)
  (let* ((width (screen-width screen))
         (height (screen-height screen))
         (cells (screen-cells screen))
         (result (make-string (+ (* width height) (max 0 (1- height)))))
         (output-index 0)
         (cell-index 0))
    (dotimes (y height result)
      (loop repeat width
            do (setf (char result output-index)
                     (cell-char (aref cells cell-index)))
               (incf output-index)
               (incf cell-index))
      (unless (= y (1- height))
        (setf (char result output-index) #\Newline)
        (incf output-index)))))
