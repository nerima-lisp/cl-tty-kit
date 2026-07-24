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

(defun %proper-screen-text-list-p (value)
  (loop for rest = value then (cdr rest)
        while (consp rest)
        finally (return (null rest))))

(defun %assert-screen-text-lines (lines)
  (%assert (and (%proper-screen-text-list-p lines)
               (every #'stringp lines)) "LINES ~S must be a proper list of strings." lines))

(defun %assert-screen-text-align (align)
  (%assert (member align '(:left :right :center) :test #'eq) "ALIGN ~S must be one of :LEFT, :RIGHT, or :CENTER." align))

(defun %assert-screen-text-vertical (vertical)
  (%assert (member vertical '(:top :middle :bottom) :test #'eq) "VERTICAL ~S must be one of :TOP, :MIDDLE, or :BOTTOM." vertical))

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
      (let* ((end (%cells-prefix-end text rect-width))
             (cells (%string-cell-width text :end end))
             (column-offset (ecase align
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
              (screen-write-string screen x y text :end end))))))
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
        (height (screen-height screen)))
    (when (and (<= 0 x) (< x width))
      (let ((available (- width x)))
        (loop for line in lines
              for row from y
              when (and (<= 0 row) (< row height))
                do (let ((end (%cells-prefix-end line available)))
                     (when (plusp end)
                       (if style
                           (screen-write-string screen x row line :style style :end end)
                           (screen-write-string screen x row line :end end))))))))
  screen)

(defun screen-write-wrapped (screen x y width text &key style)
  "Wrap TEXT to WIDTH columns and write the lines down from (X, Y).
Returns (VALUES SCREEN COUNT), where COUNT is how many wrapped lines landed
inside the screen. Lines are further clipped to the right edge and rows past the
bottom are dropped. WIDTH must be positive (it is the wrap column, not a screen
coordinate). STYLE, when non-NIL, applies to every written cell."
  (%assert-screen-text-screen screen)
  (%assert-screen-text-coordinate "X" x)
  (%assert-screen-text-coordinate "Y" y)
  (let ((lines (wrap-string text width))
        (screen-width (screen-width screen))
        (screen-height (screen-height screen)))
    (screen-write-lines screen x y lines :style style)
    (values screen
            (if (and (<= 0 x) (< x screen-width))
                (loop for index from 0 below (length lines)
                      for row = (+ y index)
                      when (and (<= 0 row) (< row screen-height))
                        count 1)
                0))))

(defun screen-to-string (screen)
  "Return SCREEN's contents as plain text: each row's stored characters joined
by newlines, with no styling. A double-width glyph appears once followed by its
spacer, matching the grid. Useful for snapshots and test assertions."
  (%assert-screen-text-screen screen)
  (with-output-to-string (out)
    (dotimes (y (screen-height screen))
      (when (plusp y)
        (write-char #\Newline out))
      (write-string (screen-row-string screen y) out))))
