(in-package #:cl-tty-kit)

(declaim (notinline sb-unicode:general-category)
         (inline %character-width))

(defun %zero-width-general-category-p (category code)
  (or (eq category :mn)
      (eq category :me)
      (and (eq category :cf)
           (/= code #x00AD))))

(defun %unicode-general-category (char)
  (sb-unicode:general-category char))

(defparameter +wide-code-point-vector+
  (coerce +wide-code-point-ranges+ 'simple-vector)
  "The sorted, non-overlapping wide-code-point ranges as a vector, so membership
is a binary search instead of a linear scan of the source list.")

(defconstant +maximum-unicode-code-point+ #x10FFFF)

(defun %valid-code-point-p (value)
  (and (integerp value)
       (<= 0 value +maximum-unicode-code-point+)))

(defun %validate-code-point-designator (value)
  (cond
    ((characterp value) (char-code value))
    ((%valid-code-point-p value) value)
    (t (error "Expected a character or Unicode code point, got ~S." value))))

(defun %validate-string-bounds (string start end)
  (let ((length (length string)))
    (unless (and (integerp start)
                 (integerp end)
                 (<= 0 start end length))
      (error "Invalid string bounds START=~S END=~S for string of length ~D."
             start end length))))

(defun %code-point-in-sorted-ranges-p (code ranges)
  "Return true when CODE lies inside one of the sorted, non-overlapping
(START . END) ranges in the simple-vector RANGES, using binary search."
  (declare (type simple-vector ranges))
  (let ((low 0)
        (high (1- (length ranges))))
    (loop while (<= low high) do
      (let* ((mid (ash (+ low high) -1))
             (range (svref ranges mid)))
        (cond ((< code (car range)) (setf high (1- mid)))
              ((> code (cdr range)) (setf low (1+ mid)))
              (t (return-from %code-point-in-sorted-ranges-p t)))))
    nil))

(defun %zero-width-code-point-p (code)
  (let ((char (code-char code)))
    (and char
         (let ((category (%unicode-general-category char)))
           (or (%zero-width-general-category-p category code)
               (<= #x1160 code #x11FF))))))

(defun %wide-code-point-p (code)
  "Return true when CODE occupies two terminal columns."
  (%code-point-in-sorted-ranges-p code +wide-code-point-vector+))

(defun %control-code-point-p (code)
  (and (integerp code)
       (or (< code #x20)
           (<= #x7F code #x9F))))

(defvar *east-asian-ambiguous-wide* nil
  "When true, CHAR-WIDTH counts East Asian Ambiguous code points (such as U+00A7
and many box-drawing and Greek characters) as two columns, matching CJK-locale
terminals that render them full-width. The default NIL treats them as one column,
which is correct for most Western terminals -- and keeps the ASCII fast path,
since the ambiguous check runs only when this is true.")

(defun %ambiguous-width-code-point-p (code)
  (let ((char (code-char code)))
    (and char (eq :a (sb-unicode:east-asian-width char)))))

(defun %code-point-width (code)
  (cond
    ((%control-code-point-p code) 0)
    ((and *east-asian-ambiguous-wide* (%ambiguous-width-code-point-p code)) 2)
    ;; Below U+0300 (the start of Combining Diacritical Marks) there is no
    ;; zero-width or wide code point, only Basic Latin/Latin-1/Latin
    ;; Extended/IPA/spacing-modifier letters and punctuation -- verified
    ;; against SB-UNICODE:GENERAL-CATEGORY and +WIDE-CODE-POINT-RANGES+,
    ;; whose lowest range starts at U+1100. Skipping straight to width 1
    ;; here avoids a GENERAL-CATEGORY table lookup for the common case of
    ;; writing plain ASCII text.
    ((< code #x300) 1)
    ((%zero-width-code-point-p code) 0)
    ((%wide-code-point-p code) 2)
    (t 1)))

(defun %character-width (character)
  (%code-point-width (char-code character)))

(defun char-width (character)
  "Return the terminal column width of CHARACTER or a Unicode code point."
  (%code-point-width (%validate-code-point-designator character)))

(defun string-width (string &key (start 0) (end (length string)))
  "Return the total terminal column width of STRING between START and END.
The width is the sum of CHAR-WIDTH over the selected characters, so callers
can align text that mixes ASCII, CJK, combining marks, and emoji."
  (check-type string string)
  (%validate-string-bounds string start end)
  (loop for index from start below end
        sum (%character-width (char string index))))

(defun string-graphemes (string)
  "Return STRING split into a list of grapheme-cluster strings.
A cluster is what a reader perceives as one character -- a base plus its
combining marks, or a ZWJ emoji sequence -- via SB-UNICODE's Unicode
grapheme-break rules (already in the image, so no data tables are shipped). This
is the right unit for cursor movement and grapheme-aware truncation, unlike
per-code-point iteration."
  ;; SB-UNICODE:GRAPHEMES indexes position 0 unconditionally, so it errors on an
  ;; empty string; guard that edge here.
  (if (zerop (length string))
      '()
      (sb-unicode:graphemes string)))

(defun grapheme-count (string)
  "Return the number of grapheme clusters in STRING (see STRING-GRAPHEMES)."
  (length (string-graphemes string)))

(defun grapheme-width (grapheme)
  "Return the terminal column width of the grapheme cluster GRAPHEME (a string).
The width is the maximum width of its code points, so a base plus combining
marks is the base width and a wide emoji cluster is two columns. Honors
*EAST-ASIAN-AMBIGUOUS-WIDE* through CHAR-WIDTH."
  (let ((width 0))
    (loop for char across grapheme
          do (setf width (max width (%character-width char))))
    width))
