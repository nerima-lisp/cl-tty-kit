(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Display-width-aware text layout
;;;
;;; Every operation here measures in terminal columns via CHAR-WIDTH/STRING-WIDTH
;;; rather than character counts, so a double-width CJK ideograph or a zero-width
;;; combining mark is placed the way a real terminal renders it. A wide glyph is
;;; never split across a column boundary.
;;; --------------------------------------------------------------------------

(defun %width-prefix-end (string budget &key (start 0) (end (length string)))
  "Return the largest index E in [START, END] whose column span from START is
still within BUDGET. Characters are counted by CHAR-WIDTH, so a wide glyph is
kept whole -- it is excluded rather than half-included when it would overflow."
  (let ((consumed 0)
        (result start))
    (loop for index from start below end
          for width = (char-width (char string index))
          while (<= (+ consumed width) budget)
          do (incf consumed width)
             (setf result (1+ index)))
    result))

(defun %string-cell-width (string)
  "Return the number of grid columns SCREEN-WRITE-STRING would consume for
STRING, counting each character as at least one column (a double-width glyph
costs two, including its spacer cell)."
  (loop for index from 0 below (length string)
        sum (max 1 (char-width (char string index)))))

(defun %cells-prefix-end (string budget)
  "Return the largest prefix length of STRING whose cell cost (per
%STRING-CELL-WIDTH) stays within BUDGET, matching SCREEN-WRITE-STRING's bounds
check exactly so a clipped run never overflows its region."
  (let ((consumed 0)
        (result 0))
    (loop for index from 0 below (length string)
          for cost = (max 1 (char-width (char string index)))
          while (<= (+ consumed cost) budget)
          do (incf consumed cost)
             (setf result (1+ index)))
    result))

(defun truncate-string (string width &key (ellipsis ""))
  "Return STRING clipped so its terminal column width does not exceed WIDTH.
When STRING already fits it is returned unchanged. Otherwise the longest prefix
that leaves room for ELLIPSIS (measured in columns too) is kept and ELLIPSIS is
appended, so the result stays within WIDTH. A wide glyph straddling the limit is
dropped whole. When ELLIPSIS alone would not fit in WIDTH it is omitted and the
plain prefix is returned. A negative WIDTH is treated as zero."
  (let ((width (max 0 width)))
    (if (<= (string-width string) width)
        string
        (let* ((ellipsis-width (string-width ellipsis))
               (use-ellipsis (<= ellipsis-width width))
               (budget (if use-ellipsis (- width ellipsis-width) width))
               (prefix (subseq string 0 (%width-prefix-end string budget))))
          (if use-ellipsis
              (concatenate 'string prefix ellipsis)
              prefix)))))

(defun %repeat-char (char count)
  (if (plusp count)
      (make-string count :initial-element char)
      ""))

(defun pad-string (string width &key (align :left) (pad #\Space))
  "Return STRING padded with PAD to exactly WIDTH terminal columns.
ALIGN is :LEFT (pad on the right), :RIGHT (pad on the left), or :CENTER (split
the padding, with any odd column added on the right). PAD must be a single-column
character. When STRING is already at least WIDTH columns wide it is returned
unchanged -- PAD-STRING never truncates. A negative WIDTH is treated as zero."
  (unless (= 1 (char-width pad))
    (error "PAD ~S must be a single-column character." pad))
  (let* ((width (max 0 width))
         (current (string-width string))
         (deficit (- width current)))
    (if (<= deficit 0)
        string
        (ecase align
          (:left
           (concatenate 'string string (%repeat-char pad deficit)))
          (:right
           (concatenate 'string (%repeat-char pad deficit) string))
          (:center
           (let ((left (floor deficit 2)))
             (concatenate 'string
                          (%repeat-char pad left)
                          string
                          (%repeat-char pad (- deficit left)))))))))

(defun %hard-split-word (word width)
  "Split WORD into a list of chunks each at most WIDTH columns wide.
Used only for a single word longer than a full line. A glyph wider than WIDTH on
its own becomes a lone over-width chunk rather than causing an endless loop."
  (let ((chunks '())
        (length (length word))
        (index 0))
    (loop while (< index length)
          do (let ((next (%width-prefix-end word width :start index)))
               (when (= next index)
                 (setf next (1+ index)))
               (push (subseq word index next) chunks)
               (setf index next)))
    (nreverse chunks)))

(defun %split-on-newline (string)
  (let ((parts '())
        (start 0)
        (length (length string)))
    (loop for position = (position #\Newline string :start start)
          do (push (subseq string start (or position length)) parts)
             (if position
                 (setf start (1+ position))
                 (return)))
    (nreverse parts)))

(defun %split-words (string)
  (let ((words '())
        (start 0)
        (length (length string)))
    (loop for position = (position #\Space string :start start)
          do (let ((stop (or position length)))
               (when (> stop start)
                 (push (subseq string start stop) words)))
             (if position
                 (setf start (1+ position))
                 (return)))
    (nreverse words)))

(defun %wrap-paragraph (paragraph width)
  (let ((lines '())
        (current "")
        (current-width 0))
    (flet ((flush ()
             (push current lines)
             (setf current "" current-width 0))
           (place (chunk chunk-width)
             (setf current chunk current-width chunk-width)))
      (dolist (word (%split-words paragraph))
        (dolist (chunk (if (> (string-width word) width)
                           (%hard-split-word word width)
                           (list word)))
          (let ((chunk-width (string-width chunk)))
            (cond
              ((string= current "")
               (place chunk chunk-width))
              ((<= (+ current-width 1 chunk-width) width)
               (setf current (concatenate 'string current " " chunk)
                     current-width (+ current-width 1 chunk-width)))
              (t
               (flush)
               (place chunk chunk-width))))))
      (push current lines))
    (nreverse lines)))

(defun expand-tabs (string &key (tab-width 8))
  "Return STRING with each tab expanded to spaces up to the next TAB-WIDTH stop.
The column is tracked by display width and reset by a newline, so the stops line
up the way a terminal renders them. TAB-WIDTH must be a positive integer."
  (unless (and (integerp tab-width) (plusp tab-width))
    (error "TAB-WIDTH ~S must be a positive integer." tab-width))
  (with-output-to-string (out)
    (let ((column 0))
      (loop for char across string
            do (cond
                 ((char= char #\Tab)
                  (let ((spaces (- tab-width (mod column tab-width))))
                    (dotimes (index spaces) (write-char #\Space out))
                    (incf column spaces)))
                 ((char= char #\Newline)
                  (write-char char out)
                  (setf column 0))
                 (t
                  (write-char char out)
                  (incf column (max 1 (char-width char)))))))))

(defun chop-string (string width)
  "Return STRING cut into a list of pieces each at most WIDTH terminal columns.
Unlike WRAP-STRING this is a hard chop at column boundaries with no word breaking;
a glyph wider than WIDTH becomes a lone over-width piece. An empty STRING yields
an empty list. WIDTH must be a positive integer."
  (unless (and (integerp width) (plusp width))
    (error "WIDTH ~S must be a positive column count." width))
  (if (zerop (length string))
      '()
      (%hard-split-word string width)))

(defun %skip-escape-sequence (string index limit)
  "Return the index just past the ANSI escape sequence starting at INDEX (an ESC)."
  (if (>= (1+ index) limit)
      (1+ index)
      (let ((next (char string (1+ index))))
        (cond
          ((char= next #\[)
           (let ((cursor (+ index 2)))
             (loop while (and (< cursor limit)
                              (not (<= #x40 (char-code (char string cursor)) #x7E)))
                   do (incf cursor))
             (if (< cursor limit) (1+ cursor) cursor)))
          ((char= next #\])
           (let ((cursor (+ index 2)))
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
  (with-output-to-string (out)
    (let ((index 0)
          (limit (length string)))
      (loop while (< index limit)
            do (if (char= (char string index) #\Esc)
                   (setf index (%skip-escape-sequence string index limit))
                   (progn
                     (write-char (char string index) out)
                     (incf index)))))))

(defun wrap-string (string width)
  "Return a list of lines wrapping STRING to at most WIDTH terminal columns each.
Words -- runs between spaces -- are kept whole and greedily packed; a single word
wider than WIDTH is hard-split at a column boundary. Runs of spaces collapse to a
single separator, but embedded newlines are honored as forced breaks, so a blank
line in the input yields an empty string in the result. WIDTH must be positive."
  (unless (and (integerp width) (plusp width))
    (error "WIDTH ~S must be a positive column count." width))
  (loop for paragraph in (%split-on-newline string)
        append (%wrap-paragraph paragraph width)))
