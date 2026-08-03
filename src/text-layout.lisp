(in-package #:cl-tty-kit)

(declaim (inline %string-cell-width %skip-escape-sequence))

;;; --------------------------------------------------------------------------
;;; Display-width-aware text layout
;;;
;;; Every operation here measures in terminal columns via CHAR-WIDTH/STRING-WIDTH
;;; rather than character counts, so a double-width CJK ideograph or a zero-width
;;; combining mark is placed the way a real terminal renders it. A wide glyph is
;;; never split across a column boundary.
;;; --------------------------------------------------------------------------

(define-simple-assert %assert-layout-string (name value)
  (stringp value)
  "~A ~S must be a string." name value)

(define-simple-assert %assert-layout-width (name value &key positive)
  (and (integerp value) (if positive (plusp value) t))
  "~A ~S must be ~:[an integer~;a positive integer~]." name value positive)

(define-simple-assert %assert-layout-character (name value)
  (characterp value)
  "~A ~S must be a character." name value)

(define-simple-assert %assert-layout-align (align)
  (member align '(:left :right :center) :test #'eq)
  "ALIGN ~S must be one of :LEFT, :RIGHT, or :CENTER." align)

(defun %width-prefix-end (string budget &key (start 0) (end (length string)))
  "Return the largest index E in [START, END] whose column span from START is
still within BUDGET. Characters are counted by CHAR-WIDTH, so a wide glyph is
kept whole -- it is excluded rather than half-included when it would overflow."
  (declare (type fixnum start end budget))
  (let ((consumed 0)
        (result start))
    (declare (type fixnum consumed result))
    (loop for index fixnum from start below end
          for width fixnum = (%character-width (char string index))
          while (<= (+ consumed width) budget)
          do (incf consumed width)
             (setf result (1+ index)))
    result))

(defun %string-cell-width (string &key (start 0) (end (length string)))
  (declare (type fixnum start end))
  (let ((width 0))
    (declare (type fixnum width))
    (do ((index start (1+ index)))
        ((>= index end) width)
      (declare (type fixnum index))
      (let ((cell-width (%character-width (char string index))))
        (declare (type fixnum cell-width))
        (incf width (if (zerop cell-width) 1 cell-width))))))

(defmacro %cells-prefix-end (string budget)
  "Return the largest prefix length of STRING whose cell cost (per
%STRING-CELL-WIDTH) stays within BUDGET, matching SCREEN-WRITE-STRING's bounds
check exactly so a clipped run never overflows its region. The second value is
the cell cost of that prefix."
  `(let ((string ,string) (budget ,budget) (consumed 0) (result 0))
     (declare (type fixnum budget consumed result))
     (loop for index fixnum from 0 below (length string)
           for cost fixnum = (%character-width (char string index))
           while (<= (+ consumed cost) budget)
           do (incf consumed (if (zerop cost) 1 cost))
              (setf result (1+ index)))
     (values result consumed)))

(defun truncate-string (string width &key (ellipsis ""))
  "Return STRING clipped so its terminal column width does not exceed WIDTH.
When STRING already fits it is returned unchanged. Otherwise the longest prefix
that leaves room for ELLIPSIS (measured in columns too) is kept and ELLIPSIS is
appended, so the result stays within WIDTH. A wide glyph straddling the limit is
dropped whole. When ELLIPSIS alone would not fit in WIDTH it is omitted and the
plain prefix is returned. A negative WIDTH is treated as zero."
  (%assert-layout-string "STRING" string)
  (%assert-layout-string "ELLIPSIS" ellipsis)
  (%assert-layout-width "WIDTH" width)
  (let ((width (if (minusp width) 0 width)))
    (if (<= (string-width string) width)
        string
        (let* ((ellipsis-width (string-width ellipsis))
               (ellipsis-length (length ellipsis))
               (use-ellipsis (<= ellipsis-width width))
               (budget (if use-ellipsis (- width ellipsis-width) width))
               (prefix-end (%width-prefix-end string budget)))
          (if (and use-ellipsis (plusp ellipsis-length))
              (let ((result (make-string (+ prefix-end ellipsis-length))))
                (replace result string :end1 prefix-end :end2 prefix-end)
                (replace result ellipsis :start1 prefix-end)
                result)
              (subseq string 0 prefix-end))))))

(defun pad-string (string width &key (align :left) (pad #\Space))
  "Return STRING padded with PAD to exactly WIDTH terminal columns.
ALIGN is :LEFT (pad on the right), :RIGHT (pad on the left), or :CENTER (split
the padding, with any odd column added on the right). PAD must be a single-column
character. When STRING is already at least WIDTH columns wide it is returned
unchanged -- PAD-STRING never truncates. A negative WIDTH is treated as zero."
  (%assert-layout-string "STRING" string)
  (%assert-layout-width "WIDTH" width)
  (%assert-layout-character "PAD" pad)
  (%assert-layout-align align)
  (%assert (= 1 (char-width pad)) "PAD ~S must be a single-column character." pad)
  (let* ((width (if (minusp width) 0 width))
         (current (string-width string))
         (deficit (- width current)))
    (declare (type fixnum width current deficit))
    (if (<= deficit 0)
        string
         (let* ((left-padding (ecase align
                                (:left 0)
                                (:right deficit)
                                (:center (ash deficit -1))))
                (result (make-string (+ (length string) deficit)
                                     :initial-element pad)))
          (replace result string :start1 left-padding)
          result))))

(defun expand-tabs (string &key (tab-width 8))
  "Return STRING with each tab expanded to spaces up to the next TAB-WIDTH stop.
The column is tracked by display width and reset by a newline, so the stops line
up the way a terminal renders them. TAB-WIDTH must be a positive integer."
  (%assert-layout-string "STRING" string)
  (%assert (and (integerp tab-width) (plusp tab-width))
           "TAB-WIDTH ~S must be a positive integer." tab-width)
  (with-output-to-string (out)
    (let ((column 0)
          (limit (length string)))
      (declare (type fixnum column limit))
      (loop for index fixnum from 0 below limit
            for char = (char string index)
            do (cond
                 ((char= char #\Tab)
                  (let ((spaces (- tab-width (mod column tab-width))))
                    (declare (type fixnum spaces))
                    (dotimes (index spaces)
                      (declare (type fixnum index))
                      (write-char #\Space out))
                    (incf column spaces)))
                   ((char= char #\Newline)
                    (write-char char out)
                    (setf column 0))
                   (t
                    (write-char char out)
                    (let ((char-width (%character-width char)))
                      (declare (type fixnum char-width))
                      (incf column (if (zerop char-width) 1 char-width)))))))))

(defun %skip-escape-sequence (string index limit)
  "Return the index just past the ANSI escape sequence starting at INDEX (an ESC)."
  (declare (type fixnum index limit))
  (if (>= (1+ index) limit)
      (1+ index)
      (let ((next (char string (1+ index))))
        (cond
          ((char= next #\[)
           (let ((cursor (+ index 2)))
             (declare (type fixnum cursor))
             (loop while (and (< cursor limit)
                              (not (<= #x40 (char-code (char string cursor)) #x7E)))
                   when (char= (char string cursor) #\Esc)
                     do (return-from %skip-escape-sequence cursor)
                   do (incf cursor))
             (if (< cursor limit) (1+ cursor) cursor)))
          ((char= next #\])
           (let ((cursor (+ index 2)))
             (declare (type fixnum cursor))
             (loop while (< cursor limit)
                   do (cond
                        ((char= (char string cursor) (code-char 7))
                         (return))
                        ((and (char= (char string cursor) #\Esc)
                              (< (1+ cursor) limit)
                              (char= (char string (1+ cursor)) #\\))
                         (setf cursor (1+ cursor))
                         (return)))
                      (incf cursor))
             (if (< cursor limit) (1+ cursor) cursor)))
          (t (+ index 2))))))

(defun strip-ansi (string)
  "Return STRING with ANSI escape sequences removed, leaving the printable text.
Handles CSI (`ESC [ ... final'), OSC (`ESC ] ... BEL/ST'), and simple two-byte
`ESC X' sequences -- enough to measure or store text a terminal produced. Use
STRING-WIDTH on the result to get the visible column count of styled text."
  (%assert-layout-string "STRING" string)
  (with-output-to-string (out)
    (let ((index 0)
          (limit (length string)))
      (declare (type fixnum index limit))
      (loop while (< index limit)
            do (if (char= (char string index) #\Esc)
                   (setf index (%skip-escape-sequence string index limit))
                   (progn
                     (write-char (char string index) out)
                     (incf index)))))))
