(in-package #:cl-tty-kit/test)

(defun %code-points->string (code-points)
  (map 'string #'code-char code-points))

(defun %sbcl-grapheme-boundaries (string)
  "Cluster boundaries of STRING according to SB-UNICODE:GRAPHEMES, the oracle."
  (let ((offsets (list 0))
        (position 0))
    (when (plusp (length string))
      (dolist (cluster (sb-unicode:graphemes string))
        (incf position (length cluster))
        (push position offsets)))
    (nreverse offsets)))

(defun %boundaries->lengths (boundaries)
  (loop for (start end) on boundaries
        while end
        collect (- end start)))

(defun %linker-free-p (string)
  "True when STRING has no InCB=Linker code point, so GB9c cannot apply to it.
GB9c needs a Linker before the Consonant it joins, so on such a string the
rules this library implements are exactly the ones every SB-UNICODE:GRAPHEMES
implements: SBCL 2.6.10 has GB9c and older SBCLs have no GB9c at all. Only
these strings are compared against the runtime, which keeps the comparison
valid on every SBCL version without branching on it; GB9c itself is checked
against Unicode's GraphemeBreakTest.txt below."
  (notany (lambda (char)
            (cl-tty-kit::%incb-p char cl-tty-kit::+incb-linker-vector+))
          string))

(defparameter *grapheme-cases*
  ;; (code points, cluster lengths UAX #29 for Unicode 18.0.0 gives)
  '(((#x0D #x0A) (2))
    ((#x0D #x0A #x61) (2 1))
    ((#x65 #x301 #x302) (3))
    ((#x1F468 #x200D #x1F469 #x200D #x1F467) (5))
    ((#x1F1EF #x1F1F5) (2))
    ((#x1F1EF #x1F1F5 #x1F1FA) (2 1))
    ((#x1F1EF #x1F1F5 #x1F1FA #x1F1F8) (2 2))
    ((#x1100 #x1161 #x11A8) (3))
    ((#xAC00 #x11A8) (2))
    ((#x1F44B #x1F3FD) (2))
    ((#x2764 #xFE0F) (2))
    ((#x600 #x31) (2))
    ((#x61 #x903) (2))
    ((#xE01 #xE33) (2))
    ((#x61 #x200D #x1F600) (2 1))
    ((#x1F600 #x301 #x200D #x1F600) (4))
    ;; GB9c: KA VIRAMA SSA is the conjunct KSSA.
    ((#x915 #x94D #x937) (3))
    ;; GB9c needs a Consonant after the Linker.
    ((#x915 #x94D #x61) (2 1))))

(defparameter *grapheme-code-point-pool*
  #(#x61 #x41 #x20 #x0D #x0A #x09 #x00 #x7F #xAD #xA9 #x301 #x302 #x200D #x200B
    #xFE0F #x1F1EF #x1F1F5 #x1F1FA #x1100 #x1161 #x11A8 #xAC00 #xAC01 #x1F44B
    #x1F3FB #x1F3FD #x2764 #x1F468 #x1F469 #x1F600 #x600 #x31 #x903 #xE01 #xE33
    #x915 #x94D #x937 #x4E00 #xE0020 #xFF21))

(defun %pseudo-random-grapheme-strings (count &key (seed 20261115) (max-length 12))
  "COUNT strings drawn from *GRAPHEME-CODE-POINT-POOL* by a fixed-seed linear
congruential generator, so every run checks the same corpus."
  (let ((state seed)
        (pool *grapheme-code-point-pool*))
    (flet ((next (bound)
             (setf state (mod (+ (* state 6364136223846793005) 1442695040888963407)
                              (expt 2 64)))
             (mod (ash state -33) bound)))
      (loop repeat count
            collect (let ((length (next (1+ max-length))))
                      (%code-points->string
                       (loop repeat length
                             collect (aref pool (next (length pool))))))))))

(defparameter *grapheme-corpus*
  (append (mapcar (lambda (case) (%code-points->string (first case)))
                  *grapheme-cases*)
          (list "" "abc" (%code-points->string '(#x4E00 #x4E8C #x0301 #x61)))
          (%pseudo-random-grapheme-strings 400)))

(defparameter *grapheme-runtime-corpus*
  (remove-if-not #'%linker-free-p *grapheme-corpus*)
  "The part of *GRAPHEME-CORPUS* that can be compared against the runtime,
SB-UNICODE:GRAPHEMES directly or through STRING-GRAPHEMES (see %LINKER-FREE-P).")

(defparameter *grapheme-break-test-incb-lines*
  ;; Every test line of GraphemeBreakTest-18.0.0.txt
  ;; (https://www.unicode.org/Public/18.0.0/ucd/auxiliary/GraphemeBreakTest.txt)
  ;; whose comment marks a character as Extend_ConjunctLinker,
  ;; ConjunctLinkermExtend, or LinkingConsonant, that is, every line with an
  ;; InCB=Linker or InCB=Consonant code point. The break strings are verbatim;
  ;; the trailing "# ..." comments are dropped.
  '("÷ 000D ÷ 094D ÷"
    "÷ 000D ÷ 0308 × 094D ÷"
    "÷ 000D ÷ 1CF5 ÷"
    "÷ 000D ÷ 0308 ÷ 1CF5 ÷"
    "÷ 000D ÷ 0915 ÷"
    "÷ 000D ÷ 0308 ÷ 0915 ÷"
    "÷ 000A ÷ 094D ÷"
    "÷ 000A ÷ 0308 × 094D ÷"
    "÷ 000A ÷ 1CF5 ÷"
    "÷ 000A ÷ 0308 ÷ 1CF5 ÷"
    "÷ 000A ÷ 0915 ÷"
    "÷ 000A ÷ 0308 ÷ 0915 ÷"
    "÷ 0000 ÷ 094D ÷"
    "÷ 0000 ÷ 0308 × 094D ÷"
    "÷ 0000 ÷ 1CF5 ÷"
    "÷ 0000 ÷ 0308 ÷ 1CF5 ÷"
    "÷ 0000 ÷ 0915 ÷"
    "÷ 0000 ÷ 0308 ÷ 0915 ÷"
    "÷ 094D ÷ 000D ÷"
    "÷ 094D × 0308 ÷ 000D ÷"
    "÷ 094D ÷ 000A ÷"
    "÷ 094D × 0308 ÷ 000A ÷"
    "÷ 094D ÷ 0000 ÷"
    "÷ 094D × 0308 ÷ 0000 ÷"
    "÷ 094D × 094D ÷"
    "÷ 094D × 0308 × 094D ÷"
    "÷ 094D × 0300 ÷"
    "÷ 094D × 0308 × 0300 ÷"
    "÷ 094D × 200C ÷"
    "÷ 094D × 0308 × 200C ÷"
    "÷ 094D × 200D ÷"
    "÷ 094D × 0308 × 200D ÷"
    "÷ 094D ÷ 1F1E6 ÷"
    "÷ 094D × 0308 ÷ 1F1E6 ÷"
    "÷ 094D ÷ 06DD ÷"
    "÷ 094D × 0308 ÷ 06DD ÷"
    "÷ 094D × 0903 ÷"
    "÷ 094D × 0308 × 0903 ÷"
    "÷ 094D ÷ 1100 ÷"
    "÷ 094D × 0308 ÷ 1100 ÷"
    "÷ 094D ÷ 1160 ÷"
    "÷ 094D × 0308 ÷ 1160 ÷"
    "÷ 094D ÷ 11A8 ÷"
    "÷ 094D × 0308 ÷ 11A8 ÷"
    "÷ 094D ÷ AC00 ÷"
    "÷ 094D × 0308 ÷ AC00 ÷"
    "÷ 094D ÷ AC01 ÷"
    "÷ 094D × 0308 ÷ AC01 ÷"
    "÷ 094D ÷ 1CF5 ÷"
    "÷ 094D × 0308 ÷ 1CF5 ÷"
    "÷ 094D × 0915 ÷"
    "÷ 094D × 0308 × 0915 ÷"
    "÷ 094D ÷ 00A9 ÷"
    "÷ 094D × 0308 ÷ 00A9 ÷"
    "÷ 094D ÷ 0020 ÷"
    "÷ 094D × 0308 ÷ 0020 ÷"
    "÷ 094D ÷ 0378 ÷"
    "÷ 094D × 0308 ÷ 0378 ÷"
    "÷ 0300 × 094D ÷"
    "÷ 0300 × 0308 × 094D ÷"
    "÷ 0300 ÷ 1CF5 ÷"
    "÷ 0300 × 0308 ÷ 1CF5 ÷"
    "÷ 0300 ÷ 0915 ÷"
    "÷ 0300 × 0308 ÷ 0915 ÷"
    "÷ 200C × 094D ÷"
    "÷ 200C × 0308 × 094D ÷"
    "÷ 200C ÷ 1CF5 ÷"
    "÷ 200C × 0308 ÷ 1CF5 ÷"
    "÷ 200C ÷ 0915 ÷"
    "÷ 200C × 0308 ÷ 0915 ÷"
    "÷ 200D × 094D ÷"
    "÷ 200D × 0308 × 094D ÷"
    "÷ 200D ÷ 1CF5 ÷"
    "÷ 200D × 0308 ÷ 1CF5 ÷"
    "÷ 200D ÷ 0915 ÷"
    "÷ 200D × 0308 ÷ 0915 ÷"
    "÷ 1F1E6 × 094D ÷"
    "÷ 1F1E6 × 0308 × 094D ÷"
    "÷ 1F1E6 ÷ 1CF5 ÷"
    "÷ 1F1E6 × 0308 ÷ 1CF5 ÷"
    "÷ 1F1E6 ÷ 0915 ÷"
    "÷ 1F1E6 × 0308 ÷ 0915 ÷"
    "÷ 06DD × 094D ÷"
    "÷ 06DD × 0308 × 094D ÷"
    "÷ 06DD × 1CF5 ÷"
    "÷ 06DD × 0308 ÷ 1CF5 ÷"
    "÷ 06DD × 0915 ÷"
    "÷ 06DD × 0308 ÷ 0915 ÷"
    "÷ 0903 × 094D ÷"
    "÷ 0903 × 0308 × 094D ÷"
    "÷ 0903 ÷ 1CF5 ÷"
    "÷ 0903 × 0308 ÷ 1CF5 ÷"
    "÷ 0903 ÷ 0915 ÷"
    "÷ 0903 × 0308 ÷ 0915 ÷"
    "÷ 1100 × 094D ÷"
    "÷ 1100 × 0308 × 094D ÷"
    "÷ 1100 ÷ 1CF5 ÷"
    "÷ 1100 × 0308 ÷ 1CF5 ÷"
    "÷ 1100 ÷ 0915 ÷"
    "÷ 1100 × 0308 ÷ 0915 ÷"
    "÷ 1160 × 094D ÷"
    "÷ 1160 × 0308 × 094D ÷"
    "÷ 1160 ÷ 1CF5 ÷"
    "÷ 1160 × 0308 ÷ 1CF5 ÷"
    "÷ 1160 ÷ 0915 ÷"
    "÷ 1160 × 0308 ÷ 0915 ÷"
    "÷ 11A8 × 094D ÷"
    "÷ 11A8 × 0308 × 094D ÷"
    "÷ 11A8 ÷ 1CF5 ÷"
    "÷ 11A8 × 0308 ÷ 1CF5 ÷"
    "÷ 11A8 ÷ 0915 ÷"
    "÷ 11A8 × 0308 ÷ 0915 ÷"
    "÷ AC00 × 094D ÷"
    "÷ AC00 × 0308 × 094D ÷"
    "÷ AC00 ÷ 1CF5 ÷"
    "÷ AC00 × 0308 ÷ 1CF5 ÷"
    "÷ AC00 ÷ 0915 ÷"
    "÷ AC00 × 0308 ÷ 0915 ÷"
    "÷ AC01 × 094D ÷"
    "÷ AC01 × 0308 × 094D ÷"
    "÷ AC01 ÷ 1CF5 ÷"
    "÷ AC01 × 0308 ÷ 1CF5 ÷"
    "÷ AC01 ÷ 0915 ÷"
    "÷ AC01 × 0308 ÷ 0915 ÷"
    "÷ 1CF5 ÷ 000D ÷"
    "÷ 1CF5 × 0308 ÷ 000D ÷"
    "÷ 1CF5 ÷ 000A ÷"
    "÷ 1CF5 × 0308 ÷ 000A ÷"
    "÷ 1CF5 ÷ 0000 ÷"
    "÷ 1CF5 × 0308 ÷ 0000 ÷"
    "÷ 1CF5 × 094D ÷"
    "÷ 1CF5 × 0308 × 094D ÷"
    "÷ 1CF5 × 0300 ÷"
    "÷ 1CF5 × 0308 × 0300 ÷"
    "÷ 1CF5 × 200C ÷"
    "÷ 1CF5 × 0308 × 200C ÷"
    "÷ 1CF5 × 200D ÷"
    "÷ 1CF5 × 0308 × 200D ÷"
    "÷ 1CF5 ÷ 1F1E6 ÷"
    "÷ 1CF5 × 0308 ÷ 1F1E6 ÷"
    "÷ 1CF5 ÷ 06DD ÷"
    "÷ 1CF5 × 0308 ÷ 06DD ÷"
    "÷ 1CF5 × 0903 ÷"
    "÷ 1CF5 × 0308 × 0903 ÷"
    "÷ 1CF5 ÷ 1100 ÷"
    "÷ 1CF5 × 0308 ÷ 1100 ÷"
    "÷ 1CF5 ÷ 1160 ÷"
    "÷ 1CF5 × 0308 ÷ 1160 ÷"
    "÷ 1CF5 ÷ 11A8 ÷"
    "÷ 1CF5 × 0308 ÷ 11A8 ÷"
    "÷ 1CF5 ÷ AC00 ÷"
    "÷ 1CF5 × 0308 ÷ AC00 ÷"
    "÷ 1CF5 ÷ AC01 ÷"
    "÷ 1CF5 × 0308 ÷ AC01 ÷"
    "÷ 1CF5 ÷ 1CF5 ÷"
    "÷ 1CF5 × 0308 ÷ 1CF5 ÷"
    "÷ 1CF5 × 0915 ÷"
    "÷ 1CF5 × 0308 × 0915 ÷"
    "÷ 1CF5 ÷ 00A9 ÷"
    "÷ 1CF5 × 0308 ÷ 00A9 ÷"
    "÷ 1CF5 ÷ 0020 ÷"
    "÷ 1CF5 × 0308 ÷ 0020 ÷"
    "÷ 1CF5 ÷ 0378 ÷"
    "÷ 1CF5 × 0308 ÷ 0378 ÷"
    "÷ 0915 ÷ 000D ÷"
    "÷ 0915 × 0308 ÷ 000D ÷"
    "÷ 0915 ÷ 000A ÷"
    "÷ 0915 × 0308 ÷ 000A ÷"
    "÷ 0915 ÷ 0000 ÷"
    "÷ 0915 × 0308 ÷ 0000 ÷"
    "÷ 0915 × 094D ÷"
    "÷ 0915 × 0308 × 094D ÷"
    "÷ 0915 × 0300 ÷"
    "÷ 0915 × 0308 × 0300 ÷"
    "÷ 0915 × 200C ÷"
    "÷ 0915 × 0308 × 200C ÷"
    "÷ 0915 × 200D ÷"
    "÷ 0915 × 0308 × 200D ÷"
    "÷ 0915 ÷ 1F1E6 ÷"
    "÷ 0915 × 0308 ÷ 1F1E6 ÷"
    "÷ 0915 ÷ 06DD ÷"
    "÷ 0915 × 0308 ÷ 06DD ÷"
    "÷ 0915 × 0903 ÷"
    "÷ 0915 × 0308 × 0903 ÷"
    "÷ 0915 ÷ 1100 ÷"
    "÷ 0915 × 0308 ÷ 1100 ÷"
    "÷ 0915 ÷ 1160 ÷"
    "÷ 0915 × 0308 ÷ 1160 ÷"
    "÷ 0915 ÷ 11A8 ÷"
    "÷ 0915 × 0308 ÷ 11A8 ÷"
    "÷ 0915 ÷ AC00 ÷"
    "÷ 0915 × 0308 ÷ AC00 ÷"
    "÷ 0915 ÷ AC01 ÷"
    "÷ 0915 × 0308 ÷ AC01 ÷"
    "÷ 0915 ÷ 1CF5 ÷"
    "÷ 0915 × 0308 ÷ 1CF5 ÷"
    "÷ 0915 ÷ 0915 ÷"
    "÷ 0915 × 0308 ÷ 0915 ÷"
    "÷ 0915 ÷ 00A9 ÷"
    "÷ 0915 × 0308 ÷ 00A9 ÷"
    "÷ 0915 ÷ 0020 ÷"
    "÷ 0915 × 0308 ÷ 0020 ÷"
    "÷ 0915 ÷ 0378 ÷"
    "÷ 0915 × 0308 ÷ 0378 ÷"
    "÷ 00A9 × 094D ÷"
    "÷ 00A9 × 0308 × 094D ÷"
    "÷ 00A9 ÷ 1CF5 ÷"
    "÷ 00A9 × 0308 ÷ 1CF5 ÷"
    "÷ 00A9 ÷ 0915 ÷"
    "÷ 00A9 × 0308 ÷ 0915 ÷"
    "÷ 0020 × 094D ÷"
    "÷ 0020 × 0308 × 094D ÷"
    "÷ 0020 ÷ 1CF5 ÷"
    "÷ 0020 × 0308 ÷ 1CF5 ÷"
    "÷ 0020 ÷ 0915 ÷"
    "÷ 0020 × 0308 ÷ 0915 ÷"
    "÷ 0378 × 094D ÷"
    "÷ 0378 × 0308 × 094D ÷"
    "÷ 0378 ÷ 1CF5 ÷"
    "÷ 0378 × 0308 ÷ 1CF5 ÷"
    "÷ 0378 ÷ 0915 ÷"
    "÷ 0378 × 0308 ÷ 0915 ÷"
    "÷ 0915 ÷ 0924 ÷"
    "÷ 0915 × 094D × 0924 ÷"
    "÷ 0915 × 094D × 094D × 0924 ÷"
    "÷ 0915 × 094D × 200D × 0924 ÷"
    "÷ 0915 × 093C × 200D × 094D × 0924 ÷"
    "÷ 0915 × 093C × 094D × 200D × 0924 ÷"
    "÷ 0915 × 094D × 0924 × 094D × 092F ÷"
    "÷ 0915 × 094D ÷ 0061 ÷"
    "÷ 0061 × 094D × 0924 ÷"
    "÷ 003F × 094D × 0924 ÷"
    "÷ 0915 × 094D × 094D × 0924 ÷"
    "÷ 0AB8 × 0AFB × 0ACD × 0AB8 × 0AFB ÷"
    "÷ 1019 × 1039 × 1018 ÷ 102C × 1037 ÷"
    "÷ 1004 × 103A × 1039 × 1011 × 1039 × 1011 ÷"
    "÷ 1B12 × 1B01 ÷ 1B32 × 1B44 × 1B2F ÷ 1B32 × 1B44 × 1B22 × 1B44 × 1B2C ÷ 1B32 × 1B44 × 1B22 × 1B38 ÷"
    "÷ 179F × 17D2 × 178F × 17D2 × 179A × 17B8 ÷"
    "÷ 1B26 ÷ 1B17 × 1B44 × 1B13 ÷"
    "÷ 1B27 ÷ 1B13 × 1B44 × 1B0B ÷ 1B0B × 1B04 ÷"
    "÷ 1795 × 17D2 × 17AF ÷ 1798 ÷"
    "÷ 17A0 × 17D2 × 17AB ÷ 1791 × 17D0 ÷ 1799 ÷"
    "÷ 1B05 × 1B44 × 1B33 × 1B03 ÷"
    "÷ 1CF5 × 0995 ÷"
    "÷ 1CF6 × 09AA ÷"
    "÷ 1CF5 × 200C ÷ 0995 ÷"
    "÷ 1CF6 × 200C ÷ 09AA ÷"
    "÷ 11A3A × 11A0B ÷"))

(defun %parse-grapheme-break-test-line (line)
  "Return the code points of a GraphemeBreakTest.txt break string such as
\"÷ 0915 × 094D × 0924 ÷\" and its boundary offsets (the ÷ positions)."
  (let ((code-points '())
        (boundaries '())
        (start 0))
    (loop
      (let* ((token-start (position #\Space line :start start :test-not #'char=))
             (token-end (and token-start
                             (or (position #\Space line :start token-start)
                                 (length line)))))
        (unless token-start
          (return (values (nreverse code-points) (nreverse boundaries))))
        (let ((token (subseq line token-start token-end)))
          (cond ((string= token "÷") (push (length code-points) boundaries))
                ((string= token "×"))
                (t (push (parse-integer token :radix 16) code-points))))
        (setf start token-end)))))

(defun %error-type-of (thunk)
  (handler-case (progn (funcall thunk) nil)
    (error (condition) (type-of condition))))

(describe "next-grapheme-boundary"
  (it "segments the named UAX #29 cases, agreeing with SB-UNICODE:GRAPHEMES without a Linker"
    (dolist (case *grapheme-cases*)
      (let ((string (%code-points->string (first case))))
        (expect (%boundaries->lengths (grapheme-boundaries string))
                :to-equal (second case))
        (when (%linker-free-p string)
          (expect (grapheme-boundaries string)
                  :to-equal (%sbcl-grapheme-boundaries string))))))
  (it "agrees with SB-UNICODE:GRAPHEMES on a fixed-seed pseudo-random corpus without a Linker"
    (expect (length *grapheme-corpus*) :to-be-greater-than 400)
    (expect (length *grapheme-runtime-corpus*) :to-be-greater-than 200)
    (dolist (string *grapheme-runtime-corpus*)
      (expect (grapheme-boundaries string)
              :to-equal (%sbcl-grapheme-boundaries string))))
  (it "matches every InCB line of Unicode 18.0.0 GraphemeBreakTest.txt (GB9c)"
    (expect (length *grapheme-break-test-incb-lines*) :to-be 248)
    (dolist (line *grapheme-break-test-incb-lines*)
      (multiple-value-bind (code-points boundaries)
          (%parse-grapheme-break-test-line line)
        (expect (list line (grapheme-boundaries (%code-points->string code-points)))
                :to-equal (list line boundaries)))))
  ;; U+200C ZERO WIDTH NON-JOINER is Grapheme_Cluster_Break=Extend but
  ;; InCB=None, so it joins by GB9 yet ends the Linker run GB9c looks back on.
  (it "lets an InCB=None Extend before the Linker pass but end GB9c after it"
    (dolist (case '(((#x915 #x200C #x94D #x924) (0 4))
                    ((#x915 #x94D #x200C #x924) (0 3 4))))
      (expect (grapheme-boundaries (%code-points->string (first case)))
              :to-equal (second case))))
  (it "classifies ASCII exactly as SB-UNICODE:GRAPHEME-BREAK-CLASS does"
    (dotimes (code 128)
      (let ((char (code-char code)))
        (expect (cl-tty-kit::%grapheme-class char)
                :to-be (sb-unicode:grapheme-break-class char))
        (expect (sb-unicode:proplist-p char :extended-pictographic) :to-be-falsy))))
  (it "returns the next boundary and NIL at END"
    (let ((string (%code-points->string '(#x65 #x301 #x61))))
      (expect (next-grapheme-boundary string 0) :to-be 2)
      (expect (next-grapheme-boundary string 2) :to-be 3)
      (expect (next-grapheme-boundary string 3) :to-be-falsy)
      (expect (next-grapheme-boundary string 0 :end 1) :to-be 1)
      (expect (next-grapheme-boundary string 1 :end 1) :to-be-falsy)
      (expect (next-grapheme-boundary "" 0) :to-be-falsy)))
  (it "restarts regional-indicator parity at INDEX"
    (let ((flags (%code-points->string '(#x1F1EF #x1F1F5 #x1F1FA #x1F1F8))))
      (expect (next-grapheme-boundary flags 0) :to-be 2)
      (expect (next-grapheme-boundary flags 1) :to-be 3)))
  (it "rejects invalid bounds with the condition type STRING-WIDTH signals"
    (let ((expected (%error-type-of (lambda () (string-width "abc" :end 4)))))
      (expect expected :to-be-truthy)
      (expect (%error-type-of (lambda () (next-grapheme-boundary "abc" 4)))
              :to-be expected)
      (expect (%error-type-of (lambda () (next-grapheme-boundary "abc" -1)))
              :to-be expected)
      (expect (%error-type-of (lambda () (next-grapheme-boundary "abc" 2 :end 1)))
              :to-be expected)
      (expect (%error-type-of (lambda () (next-grapheme-boundary "abc" 0 :end 4)))
              :to-be expected)
      (expect (%error-type-of (lambda () (grapheme-boundaries "abc" :start 1.5)))
              :to-be expected)
      (expect (%error-type-of (lambda () (string-display-width "abc" :start 2 :end 1)))
              :to-be expected)
      (expect (%error-type-of
               (lambda () (do-grapheme-boundaries (s e "abc" :end 9) (list s e))))
              :to-be expected))))

(describe "do-grapheme-boundaries"
  (it "visits each cluster of a subrange in order"
    (let ((string (%code-points->string '(#x61 #x65 #x301 #x1F1EF #x1F1F5 #x62)))
          (visited '()))
      (do-grapheme-boundaries (start end string :start 1 :end 5)
        (push (cons start end) visited))
      (expect (nreverse visited) :to-equal '((1 . 3) (3 . 5)))))
  (it "returns RESULT, supports RETURN, and treats END NIL as the length"
    (expect (do-grapheme-boundaries (s e "abc" :end nil :result :done)
              (declare (ignore s e)))
            :to-be :done)
    (expect (do-grapheme-boundaries (s e "abc")
              (when (= s 1) (return e)))
            :to-be 2)
    (expect (do-grapheme-boundaries (s e "" :result 0)
              (declare (ignore s e))
              (return 1))
            :to-be 0))
  (it "evaluates STRING, START, and END once each, in order"
    (let ((log '())
          (count 0))
      (do-grapheme-boundaries (s e (progn (push :string log) "abcd")
                               :start (progn (push :start log) 1)
                               :end (progn (push :end log) 3))
        (declare (ignore s e))
        (incf count))
      (expect (nreverse log) :to-equal '(:string :start :end))
      (expect count :to-be 2))))

(describe "grapheme-boundaries"
  (it "returns a fresh list of offsets and their count"
    (let ((string (%code-points->string '(#x65 #x301 #x61))))
      (expect (multiple-value-list (grapheme-boundaries string))
              :to-equal '((0 2 3) 3))
      (expect (multiple-value-list (grapheme-boundaries string :start 2))
              :to-equal '((2 3) 2))
      (expect (multiple-value-list (grapheme-boundaries "")) :to-equal '((0) 1))
      (expect (multiple-value-list (grapheme-boundaries "abc" :start 3))
              :to-equal '((3) 1))))
  (it "fills a simple vector from index 0 and returns it with the count"
    (let* ((into (make-array 8 :initial-element -1))
           (string (%code-points->string '(#x65 #x301 #x61))))
      (multiple-value-bind (result count) (grapheme-boundaries string :into into)
        (expect result :to-be into)
        (expect count :to-be 3)
        (expect (coerce (subseq into 0 count) 'list) :to-equal '(0 2 3)))))
  (it "resets and fills a fill-pointer vector"
    (let ((into (make-array 1 :element-type 'fixnum :fill-pointer 1 :adjustable t)))
      (expect (grapheme-boundaries "abcd" :start 1 :into into) :to-be into)
      (expect (coerce into 'list) :to-equal '(1 2 3 4))))
  ;; SBCL makes every fill-pointer vector adjustable, so only a vector without a
  ;; fill pointer can run out of room here.
  (it "signals when a vector without a fill pointer is too short"
    (expect-non-type-error (grapheme-boundaries "abcd" :into (make-array 2)))
    (expect-non-type-error (grapheme-boundaries "abcd" :into :not-a-vector)))
  (it "agrees between the list and INTO shapes on the corpus"
    (let ((into (make-array 32 :element-type 'fixnum :fill-pointer 0)))
      (dolist (string *grapheme-corpus*)
        (grapheme-boundaries string :into into)
        (expect (coerce into 'list) :to-equal (grapheme-boundaries string))))))

(describe "string-display-width and grapheme-count"
  (it "is the sum of GRAPHEME-WIDTH over STRING-GRAPHEMES on the corpus without a Linker"
    (dolist (string *grapheme-runtime-corpus*)
      (expect (string-display-width string)
              :to-be (reduce #'+ (mapcar #'grapheme-width (string-graphemes string))))))
  (it "equals STRING-WIDTH on ASCII and CJK text"
    (dolist (string (list "" "hello, world" (%code-points->string '(#x4E00 #x4E8C #x4E09))
                          (%code-points->string '(#x61 #x65E5 #x672C #x8A9E #x62))))
      (expect (string-display-width string) :to-be (string-width string))))
  (it "counts a cluster once where STRING-WIDTH counts its code points"
    (let ((family (%code-points->string '(#x1F468 #x200D #x1F469 #x200D #x1F467))))
      (expect (string-display-width family) :to-be 2)
      (expect (string-width family) :to-be 6)))
  (it "honors START and END"
    (let ((string (%code-points->string '(#x61 #x4E00 #x65 #x301 #x62))))
      (expect (string-display-width string :start 1 :end 4) :to-be 3)
      (expect (string-display-width string :start 5) :to-be 0)))
  (it "keeps STRING-GRAPHEMES equal to the GRAPHEME-BOUNDARIES clusters, Linkers included"
    (dolist (string *grapheme-corpus*)
      (expect (grapheme-count string) :to-be (length (string-graphemes string)))
      (expect (mapcar #'length (string-graphemes string))
              :to-equal (%boundaries->lengths (grapheme-boundaries string))))
    (expect (string-graphemes (%code-points->string '(#x915 #x94D #x937)))
            :to-equal (list (%code-points->string '(#x915 #x94D #x937))))
    (expect (string-graphemes "") :to-equal '())
    (expect (grapheme-count "") :to-be 0)))

(defun %bytes-consed-by (thunk iterations)
  "Fewest bytes consed over three windows of calling THUNK ITERATIONS times,
each after a warm-up call and a full GC. Small allocations are only visible in
aggregate, hence the loop."
  (declare (type function thunk) (type fixnum iterations))
  ;; The first full GC in a process leaves ~30 KB of its own allocation to be
  ;; counted after it returns (a no-op thunk measured that much on SBCL 2.6.6);
  ;; collecting once before the warm-up keeps that out of the measured window.
  ;; GET-BYTES-CONSED is process-wide, so another thread consing during the
  ;; window (the finalizer thread wakes after a GC) inflates a single reading.
  ;; Take the smallest of three windows: a THUNK that conses does so in every
  ;; window, so the minimum still reports it.
  (sb-ext:gc :full t)
  (funcall thunk)
  (loop repeat 3
        minimize (progn
                   (sb-ext:gc :full t)
                   (let ((before (sb-ext:get-bytes-consed)))
                     (dotimes (i iterations)
                       (funcall thunk))
                     (- (sb-ext:get-bytes-consed) before)))))

(defparameter *allocation-sample*
  (%code-points->string
   '(#x68 #x69 #x20 #x65 #x301 #x4E00 #x1F468 #x200D #x1F469 #x200D #x1F467
     #x1F1EF #x1F1F5 #x0D #x0A #xAC00 #x11A8 #x915 #x94D #x937 #x2764 #xFE0F)))

(describe "allocation"
  (it "the measurement itself reads 0 for a thunk that does not cons"
    (expect (%bytes-consed-by (lambda () nil) 100000) :to-be 0)
    (expect (%bytes-consed-by (lambda () (make-list 4)) 100000)
            :to-be-greater-than 0))
  (it "next-grapheme-boundary does not cons"
    (let ((string *allocation-sample*))
      (expect (%bytes-consed-by
               (lambda () (next-grapheme-boundary string 6 :end 14))
               100000)
              :to-be 0)))
  (it "do-grapheme-boundaries does not cons"
    (let ((string *allocation-sample*)
          (count 0))
      (declare (type fixnum count))
      (expect (%bytes-consed-by
               (lambda ()
                 (do-grapheme-boundaries (s e string)
                   (declare (ignore s e))
                   (setf count (logand (1+ count) #xFFFF))))
               100000)
              :to-be 0)))
  (it "grapheme-boundaries with INTO does not cons"
    (let ((string *allocation-sample*)
          (simple (make-array 64 :element-type 'fixnum))
          (filled (make-array 64 :element-type 'fixnum :fill-pointer 0 :adjustable t)))
      (expect (%bytes-consed-by
               (lambda () (grapheme-boundaries string :into simple))
               100000)
              :to-be 0)
      (expect (%bytes-consed-by
               (lambda () (grapheme-boundaries string :into filled))
               100000)
              :to-be 0)))
  (it "string-display-width and grapheme-count do not cons"
    (let ((string *allocation-sample*))
      (expect (%bytes-consed-by (lambda () (string-display-width string)) 100000)
              :to-be 0)
      (expect (%bytes-consed-by (lambda () (grapheme-count string)) 100000)
              :to-be 0))))
