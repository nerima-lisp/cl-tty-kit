(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Textual widgets: progress bars and aligned columns
;;;
;;; Pure string builders that produce fixed-width output measured in terminal
;;; columns, ready to hand to SCREEN-WRITE-STRING or print directly.
;;; --------------------------------------------------------------------------

(defparameter +full-block+ (code-char #x2588)
  "The full block glyph used as the default filled cell of a progress bar.")

(defun %fractional-block (eighths)
  "Return the left-aligned block glyph filling EIGHTHS (1-7) of a cell."
  (code-char (- #x2590 eighths)))

(defun format-progress-bar (ratio width &key (fractional t)
                                             (full +full-block+)
                                             (empty #\Space))
  "Return a WIDTH-column progress bar string for RATIO, clamped to [0, 1].
With FRACTIONAL true (the default) the bar resolves to one-eighth of a cell using
Unicode block glyphs, so a partly filled final cell shows real progress; with it
false the fill rounds to whole cells of FULL. Unfilled cells use EMPTY. The
result is always exactly WIDTH columns wide (WIDTH must be a non-negative
integer)."
  (unless (typep width '(integer 0 *))
    (error "Progress bar WIDTH ~S must be a non-negative integer." width))
  (let ((ratio (clamp ratio 0 1)))
    (with-output-to-string (out)
      (if fractional
          (let* ((eighths (round (* ratio width 8)))
                 (complete (floor eighths 8))
                 (remainder (mod eighths 8)))
            (dotimes (index complete)
              (write-char full out))
            (when (and (plusp remainder) (< complete width))
              (write-char (%fractional-block remainder) out))
            (dotimes (index (- width complete (if (and (plusp remainder)
                                                       (< complete width))
                                                  1
                                                  0)))
              (write-char empty out)))
          (let ((filled (clamp (round (* ratio width)) 0 width)))
            (dotimes (index filled) (write-char full out))
            (dotimes (index (- width filled)) (write-char empty out)))))))

(defparameter +sparkline-levels+ 8
  "The number of distinct sparkline bar heights (U+2581 through U+2588).")

(defun %sparkline-char (level)
  "Return the sparkline glyph for LEVEL, an integer in [0, 7]."
  (code-char (+ #x2581 level)))

(defun format-sparkline (values &key min max)
  "Return a one-line Unicode sparkline for the sequence VALUES.
Each value maps to one of eight bar heights (U+2581..U+2588) by its position in
the range [MIN, MAX], which default to the minimum and maximum of VALUES. Values
are clamped into that range, so an explicit narrower MIN/MAX highlights a band. A
zero-width range (all values equal, or MIN=MAX) renders the lowest bar. An empty
VALUES yields an empty string."
  (let ((values (coerce values 'list)))
    (if (null values)
        ""
        (let* ((low (or min (reduce #'min values)))
               (high (or max (reduce #'max values)))
               (range (- high low)))
          (with-output-to-string (out)
            (dolist (value values)
              (let ((level (if (<= range 0)
                               0
                               (round (* (/ (- (clamp value low high) low) range)
                                         (1- +sparkline-levels+))))))
                (write-char (%sparkline-char level) out))))))))

(defparameter +spinner-frame-sets+
  (list (cons :dots (map 'vector #'code-char
                         '(#x280B #x2819 #x2839 #x2838 #x283C
                           #x2834 #x2826 #x2827 #x2807 #x280F)))
        (cons :line "|/-\\")
        (cons :bar (map 'vector #'code-char
                        '(#x2581 #x2583 #x2584 #x2586 #x2587
                          #x2586 #x2584 #x2583))))
  "Named spinner animation frame sequences.")

(defun spinner-frame (index &key (frames :dots))
  "Return the spinner glyph for step INDEX, cycling through FRAMES.
FRAMES is a keyword naming a built-in set (:DOTS braille, :LINE, or :BAR) or a
sequence of frame characters/strings supplied directly. INDEX is taken modulo the
frame count, so a monotonically increasing counter animates the spinner. An empty
frame set yields an empty string."
  (let ((set (etypecase frames
               (keyword (or (cdr (assoc frames +spinner-frame-sets+))
                            (error "Unknown spinner frame set ~S; expected one of ~S."
                                   frames (mapcar #'car +spinner-frame-sets+))))
               (sequence frames))))
    (if (zerop (length set))
        ""
        (string (elt set (mod index (length set)))))))

(defun format-columns (fields widths &key aligns (separator " ") (pad #\Space))
  "Return FIELDS padded to WIDTHS and joined by SEPARATOR into one row string.
FIELDS and WIDTHS are equal-length lists; each field is padded to its width with
PAD and the matching entry of ALIGNS (:LEFT, :RIGHT, or :CENTER, defaulting to
:LEFT when ALIGNS is shorter). Padding uses PAD-STRING, so a field already wider
than its column is left intact rather than truncated -- clip it first with
TRUNCATE-STRING if a hard cap is needed."
  (unless (= (length fields) (length widths))
    (error "FIELDS and WIDTHS must be the same length (~D vs ~D)."
           (length fields) (length widths)))
  (with-output-to-string (out)
    (loop for field in fields
          for width in widths
          for index from 0
          for align = (or (nth index aligns) :left)
          for first = t then nil
          do (unless first
               (write-string separator out))
             (write-string (pad-string field width :align align :pad pad) out))))

(defun format-table (rows &key aligns (separator " ") (pad #\Space))
  "Return a list of row strings for ROWS, each ROW a list of field strings.
Every column is padded to the width of its widest field (by STRING-WIDTH) so the
columns align down the table; ragged rows are padded with empty trailing fields.
Each row is laid out by FORMAT-COLUMNS with ALIGNS, SEPARATOR, and PAD. An empty
ROWS yields an empty list. Feed the result to SCREEN-WRITE-LINES to place a
table, or print the lines directly."
  (if (null rows)
      '()
      (let* ((columns (reduce #'max rows :key #'length :initial-value 0))
             (widths (make-list columns :initial-element 0)))
        (dolist (row rows)
          (loop for field in row
                for index from 0
                do (setf (nth index widths)
                         (max (nth index widths) (string-width field)))))
        (mapcar (lambda (row)
                  (format-columns
                   (append row (make-list (- columns (length row))
                                          :initial-element ""))
                   widths
                   :aligns aligns
                   :separator separator
                   :pad pad))
                rows))))
