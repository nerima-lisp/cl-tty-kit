(in-package #:cl-tty-kit)

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
  (let ((consumed 0)
        (result start))
    (loop for index from start below end
          for width = (%character-width (char string index))
          while (<= (+ consumed width) budget)
          do (incf consumed width)
             (setf result (1+ index)))
    result))

(defun %string-cell-width (string &key (start 0) (end (length string)))

  (loop for index from start below end
        sum (max 1 (%character-width (char string index)))))





(defun %cells-prefix-end (string budget)
  "Return the largest prefix length of STRING whose cell cost (per
%STRING-CELL-WIDTH) stays within BUDGET, matching SCREEN-WRITE-STRING's bounds
check exactly so a clipped run never overflows its region. The second value is
the cell cost of that prefix."
  (let ((consumed 0)
        (result 0))
    (loop for index from 0 below (length string)
          for cost = (max 1 (%character-width (char string index)))
          while (<= (+ consumed cost) budget)
          do (incf consumed cost)
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
  (let ((width (max 0 width)))
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
  (let* ((width (max 0 width))
         (current (string-width string))
         (deficit (- width current)))
    (if (<= deficit 0)
        string
        (let* ((left-padding (ecase align
                               (:left 0)
                               (:right deficit)
                               (:center (floor deficit 2))))
               (result (make-string (+ (length string) deficit)
                                    :initial-element pad)))
          (replace result string :start1 left-padding)
          result))))

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

(defun %split-on-char (string char)
  (let ((parts '())
        (start 0)
        (length (length string)))
    (loop for position = (position char string :start start)
          do (push (subseq string start (or position length)) parts)
             (if position
                 (setf start (1+ position))
                 (return)))
    (nreverse parts)))

(defun %call-with-wrapped-paragraph-lines (paragraph width continuation
                                             &key (start 0) (end (length paragraph)))
  "Call CONTINUATION for each wrapped line in PARAGRAPH.

CONTINUATION returns true to continue or NIL to stop. Chunks retain source
ranges while wrapping, so only the callback boundary materializes a line."
  (let ((current-chunks (list))
        (current-width 0))
    (labels ((current-line ()
               (with-output-to-string (out)
                 (loop for chunk in (nreverse current-chunks)
                       for first = t then nil
                       do (unless first (write-char #\Space out))
                          (write-string paragraph out
                                        :start (car chunk)
                                        :end (cdr chunk)))))
             (emit-current-line ()
               (unless (funcall continuation (current-line))
                 (return-from %call-with-wrapped-paragraph-lines nil))
               (setf current-chunks (list)
                     current-width 0))
             (place (chunk-start chunk-end chunk-width)
               (setf current-chunks (list (cons chunk-start chunk-end))
                     current-width chunk-width))
             (append-chunk (chunk-start chunk-end chunk-width)
               (push (cons chunk-start chunk-end) current-chunks)
               (setf current-width (+ current-width 1 chunk-width)))
             (add-chunk (chunk-start chunk-end chunk-width)
               (cond
                 ((null current-chunks)
                  (place chunk-start chunk-end chunk-width))
                 ((<= (+ current-width 1 chunk-width) width)
                  (append-chunk chunk-start chunk-end chunk-width))
                 (t
                  (emit-current-line)
                  (place chunk-start chunk-end chunk-width)))))
      ;; Stream words so a consumer can stop before scanning later input.
      (loop with cursor = start
            while (< cursor end)
            for word-end = (or (position #\Space paragraph
                                         :start cursor
                                         :end end)
                               end)
            do (when (> word-end cursor)
                 (let ((word-width (string-width paragraph
                                                 :start cursor
                                                 :end word-end)))
                   (if (> word-width width)
                       (loop with index = cursor
                             while (< index word-end)
                             for next = (%width-prefix-end paragraph width
                                                           :start index
                                                           :end word-end)
                             do (when (= next index)
                                  (setf next (1+ index)))
                                (add-chunk index next
                                           (%string-cell-width paragraph
                                                               :start index
                                                               :end next))
                                (setf index next))
                       (add-chunk cursor word-end word-width))))
               (setf cursor (1+ word-end)))
      (funcall continuation (if current-chunks (current-line) "")))))

(defun expand-tabs (string &key (tab-width 8))
  "Return STRING with each tab expanded to spaces up to the next TAB-WIDTH stop.
The column is tracked by display width and reset by a newline, so the stops line
up the way a terminal renders them. TAB-WIDTH must be a positive integer."
  (%assert-layout-string "STRING" string)
  (%assert (and (integerp tab-width) (plusp tab-width))
           "TAB-WIDTH ~S must be a positive integer." tab-width)
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
                  (incf column (max 1 (%character-width char)))))))))

(defun chop-string (string width)
  "Return STRING cut into a list of pieces each at most WIDTH terminal columns.
Unlike WRAP-STRING this is a hard chop at column boundaries with no word breaking;
a glyph wider than WIDTH becomes a lone over-width piece. An empty STRING yields
an empty list. WIDTH must be a positive integer."
  (%assert-layout-string "STRING" string)
  (%assert-layout-width "WIDTH" width :positive t)
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
                   when (char= (char string cursor) #\Esc)
                     do (return-from %skip-escape-sequence cursor)
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
  (%assert-layout-string "STRING" string)
  (with-output-to-string (out)
    (let ((index 0)
          (limit (length string)))
      (loop while (< index limit)
            do (if (char= (char string index) #\Esc)
                   (setf index (%skip-escape-sequence string index limit))
                   (progn
                     (write-char (char string index) out)
                     (incf index)))))))

(defun %call-with-wrapped-lines (string width continuation)
  "Call CONTINUATION for each line produced by validated STRING and WIDTH.

Stop immediately when CONTINUATION returns NIL, avoiding work for lines a
consumer will not observe."
  (let ((start 0)
        (end (length string)))
    (loop for newline = (position #\Newline string :start start :end end)
          for paragraph-end = (or newline end)
          unless (%call-with-wrapped-paragraph-lines
                  string width continuation :start start :end paragraph-end)
            do (return nil)
          do (if newline
                 (setf start (1+ newline))
                 (return t)))))

(defun %wrap-string-unchecked (string width)
  "Wrap validated STRING to validated positive WIDTH."
  (let ((lines '()))
    (%call-with-wrapped-lines
     string width
     (lambda (line)
       (push line lines)
       t))
    (nreverse lines)))

(defun wrap-string (string width)
  "Return a list of lines wrapping STRING to at most WIDTH terminal columns each.
Words -- runs between spaces -- are kept whole and greedily packed; a single word
wider than WIDTH is hard-split at a column boundary. Runs of spaces collapse to a
single separator, but embedded newlines are honored as forced breaks, so a blank
line in the input yields an empty string in the result. WIDTH must be positive."
  (%assert-layout-string "STRING" string)
  (%assert-layout-width "WIDTH" width :positive t)
  (%wrap-string-unchecked string width))
