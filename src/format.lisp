(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Textual widgets: progress bars and aligned columns
;;;
;;; Pure string builders that produce fixed-width output measured in terminal
;;; columns, ready to hand to SCREEN-WRITE-STRING or print directly.
;;; --------------------------------------------------------------------------

(defparameter +full-block+ (code-char #x2588)
  "The full block glyph used as the default filled cell of a progress bar.")

(defun %assert-real (name value)
  (%assert (realp value) "~A ~S must be a real number." name value))

(defun %assert-non-negative-width (name value)
  (%assert (typep value '(integer 0 *)) "~A ~S must be a non-negative integer." name value))

(defun %assert-string-field (name value)
  (%assert (stringp value) "~A ~S must be a string." name value))

(defun %assert-character-field (name value)
  (%assert (characterp value) "~A ~S must be a character." name value))

(defun %assert-column-align (name value)
  (%assert (member value '(:left :right :center) :test #'eq) "~A ~S must be :LEFT, :RIGHT, or :CENTER." name value))

(defun %assert-aligns (aligns)
  (unless (or (null aligns) (listp aligns))
    (error "ALIGNS ~S must be NIL or a list." aligns))
  (dolist (align aligns)
    (%assert-column-align "Column align" align)))

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
  (%assert-real "Progress bar RATIO" ratio)
  (%assert-non-negative-width "Progress bar WIDTH" width)
  (%assert-character-field "Progress bar FULL" full)
  (%assert-character-field "Progress bar EMPTY" empty)
  (let ((ratio (clamp ratio 0 1)))
    (with-output-to-string (out)
      (if fractional
          (let* ((eighths (round (* ratio width 8)))
                 (complete (floor eighths 8))
                 (remainder (mod eighths 8))
                 (partial-p (and (plusp remainder) (< complete width))))
            (dotimes (index complete)
              (write-char full out))
            (when partial-p
              (write-char (%fractional-block remainder) out))
            (dotimes (index (- width complete (if partial-p 1 0)))
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
  (unless (typep values 'sequence)
    (error "VALUES ~S must be a sequence." values))
  (when min (%assert-real "MIN" min))
  (when max (%assert-real "MAX" max))
  (let ((values (coerce values 'list)))
    (if (null values)
        ""
        (progn
          (dolist (value values)
            (%assert-real "Sparkline value" value))
          (let* ((low (or min (reduce #'min values)))
                 (high (or max (reduce #'max values)))
                 (range (- high low)))
            (with-output-to-string (out)
              (dolist (value values)
                (let ((level (if (<= range 0)
                                 0
                                 (round (* (/ (- (clamp value low high) low) range)
                                           (1- +sparkline-levels+))))))
                  (write-char (%sparkline-char level) out)))))))))

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
  (unless (integerp index)
    (error "Spinner INDEX ~S must be an integer." index))
  (let ((set (cond
               ((keywordp frames)
                (or (cdr (assoc frames +spinner-frame-sets+))
                    (error "Unknown spinner frame set ~S; expected one of ~S."
                           frames (mapcar #'car +spinner-frame-sets+))))
               ((typep frames 'sequence)
                frames)
               (t
                (error "FRAMES ~S must be a keyword or sequence." frames)))))
    (if (zerop (length set))
        ""
        (let ((frame (elt set (mod index (length set)))))
          (unless (or (characterp frame) (stringp frame))
            (error "Spinner frame ~S must be a character or string." frame))
          (string frame)))))

(defun format-columns (fields widths &key aligns (separator " ") (pad #\Space))
  "Return FIELDS padded to WIDTHS and joined by SEPARATOR into one row string.
FIELDS and WIDTHS are equal-length lists; each field is padded to its width with
PAD and the matching entry of ALIGNS (:LEFT, :RIGHT, or :CENTER, defaulting to
:LEFT when ALIGNS is shorter). Padding uses PAD-STRING, so a field already wider
than its column is left intact rather than truncated -- clip it first with
TRUNCATE-STRING if a hard cap is needed."
  (unless (and (listp fields) (listp widths))
    (error "FIELDS and WIDTHS must be lists."))
  (unless (= (length fields) (length widths))
    (error "FIELDS and WIDTHS must be the same length (~D vs ~D)."
           (length fields) (length widths)))
  (dolist (field fields)
    (%assert-string-field "Field" field))
  (dolist (width widths)
    (%assert-non-negative-width "Column width" width))
  (%assert-aligns aligns)
  (%assert-string-field "Separator" separator)
  (%assert-character-field "PAD" pad)
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
  (unless (listp rows)
    (error "ROWS ~S must be a list of rows." rows))
  (%assert-aligns aligns)
  (%assert-string-field "Separator" separator)
  (%assert-character-field "PAD" pad)
  (dolist (row rows)
    (unless (listp row)
      (error "Table row ~S must be a list." row))
    (dolist (field row)
      (%assert-string-field "Table field" field)))
  (if (null rows)
      '()
      (let* ((columns (reduce #'max rows :key #'length :initial-value 0))
             (widths (make-array columns :initial-element 0)))
        (dolist (row rows)
          (loop for field in row
                for index from 0
                for width = (string-width field)
                do (when (> width (aref widths index))
                     (setf (aref widths index) width))))
        (let ((width-list (coerce widths 'list)))
          (mapcar (lambda (row)
                    (format-columns
                     (append row (make-list (- columns (length row))
                                            :initial-element ""))
                     width-list
                     :aligns aligns
                     :separator separator
                     :pad pad))
                  rows)))))
