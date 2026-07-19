(in-package #:cl-tty-kit)

(declaim (notinline sb-unicode:general-category))

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

(defun %code-point-width (code)
  (cond
    ((%control-code-point-p code) 0)
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

(defun char-width (character)
  "Return the terminal column width of CHARACTER or a Unicode code point."
  (%code-point-width
   (if (characterp character)
       (char-code character)
       character)))

(defun string-width (string &key (start 0) (end (length string)))
  "Return the total terminal column width of STRING between START and END.
The width is the sum of CHAR-WIDTH over the selected characters, so callers
can align text that mixes ASCII, CJK, combining marks, and emoji."
  (loop for index from start below end
        sum (char-width (char string index))))

