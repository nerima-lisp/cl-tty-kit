(in-package #:cl-tty-kit)

;;; Allocation-free grapheme-cluster segmentation.
;;;
;;; This is a port of SBCL's internal MAP-GRAPHEME-BOUNDARIES (the extended
;;; UAX #29 rules behind SB-UNICODE:GRAPHEMES: GB3-GB5, GB6-GB8 Hangul, GB9,
;;; GB9a, GB9b, GB9c, the GB11 Extended_Pictographic/ZWJ state machine and
;;; GB12/GB13 regional-indicator parity) built on the exported
;;; SB-UNICODE:GRAPHEME-BREAK-CLASS and SB-UNICODE:PROPLIST-P, neither of which
;;; conses.
;;;
;;; GB9c is the exception: it reads Indic_Conjunct_Break from the static
;;; tables in src/grapheme-data.lisp instead of the runtime, because SBCL
;;; before 2.6.10 (Unicode 15.0 data) has neither the InCB property nor the
;;; rule, and a cluster count that changed with the SBCL version would be
;;; worse than either answer. The rule is the Unicode 18.0.0 form (UAX #29
;;; revision 49), which is what SBCL 2.6.10 implements:
;;;
;;;   GB9c  \p{InCB=Linker} \p{InCB=Extend}* x \p{InCB=Consonant}
;;;
;;; Revisions 43-48 (Unicode 15.1-17.0) additionally required a Consonant
;;; before the Linker. With that one difference, STRING-GRAPHEMES (which
;;; still calls SB-UNICODE:GRAPHEMES) and these functions agree on every
;;; cluster on SBCL 2.6.10, and on every string without an InCB=Linker
;;; code point on older SBCLs; t/grapheme-test.lisp checks the latter and
;;; checks GB9c itself against Unicode's GraphemeBreakTest.txt.

(deftype %string-index ()
  '(integer 0 (#.array-dimension-limit)))

(defparameter +incb-linker-vector+ (coerce +incb-linker-ranges+ 'simple-vector))
(defparameter +incb-consonant-vector+ (coerce +incb-consonant-ranges+ 'simple-vector))
(defparameter +incb-extend-vector+ (coerce +incb-extend-ranges+ 'simple-vector))

(declaim (inline %grapheme-class %extended-pictographic-p %incb-p))

(defun %incb-p (char ranges)
  "True when CHAR has the InCB value whose ranges are the vector RANGES."
  ;; U+0300 is the lowest code point with an InCB value other than None.
  (let ((code (char-code char)))
    (and (>= code #x300)
         (%code-point-in-sorted-ranges-p code ranges))))

(defun %grapheme-class (char)
  "SB-UNICODE:GRAPHEME-BREAK-CLASS of CHAR, with ASCII classified inline."
  (let ((code (char-code char)))
    (cond ((>= code #x7F) (sb-unicode:grapheme-break-class char))
          ((>= code #x20) nil)
          ((= code 10) :lf)
          ((= code 13) :cr)
          (t :control))))

(defun %extended-pictographic-p (char)
  ;; No ASCII code point is Extended_Pictographic.
  (and (>= (char-code char) #x80)
       (sb-unicode:proplist-p char :extended-pictographic)))

(declaim (ftype (function (string %string-index %string-index)
                          (values %string-index &optional))
                %next-grapheme-boundary))

(defun %next-grapheme-boundary (string index end)
  "Return the first grapheme boundary after INDEX, which must be < END. The
Extended_Pictographic, Indic conjunct, and regional-indicator state starts
fresh at INDEX."
  (declare (type string string)
           (type %string-index index end))
  (let* ((char2 (char string index))
         (class2 (%grapheme-class char2))
         (pictographic-state nil)
         ;; True when CHAR1 ends \p{InCB=Linker} \p{InCB=Extend}*.
         (after-linker nil)
         (regional-indicators (if (eq class2 :regional-indicator) 1 0)))
    (declare (type %string-index regional-indicators))
    (do ((position (1+ index) (1+ position)))
        ((>= position end) end)
      (declare (type %string-index position))
      (let ((char1 char2)
            (class1 class2))
        (setf char2 (char string position)
              class2 (%grapheme-class char2))
        (if (eq class2 :regional-indicator)
            (incf regional-indicators)
            (setf regional-indicators 0))
        (setf pictographic-state
              (cond ((%extended-pictographic-p char1) :start)
                    ((and (or (eq pictographic-state :start)
                              (eq pictographic-state :extend))
                          (eq class1 :extend))
                     :extend)
                    ((and (or (eq pictographic-state :start)
                              (eq pictographic-state :extend))
                          (eq class1 :zwj))
                     :zwj)
                    (t nil)))
        (setf after-linker
              (if after-linker
                  (or (%incb-p char1 +incb-linker-vector+)
                      (%incb-p char1 +incb-extend-vector+))
                  (%incb-p char1 +incb-linker-vector+)))
        (unless (cond
                  ;; GB3
                  ((and (eq class1 :cr) (eq class2 :lf)) t)
                  ;; GB4, GB5
                  ((or (eq class1 :control) (eq class1 :cr) (eq class1 :lf)
                       (eq class2 :control) (eq class2 :cr) (eq class2 :lf))
                   nil)
                  ;; GB6-GB8
                  ((or (and (eq class1 :l)
                            (or (eq class2 :l) (eq class2 :v)
                                (eq class2 :lv) (eq class2 :lvt)))
                       (and (or (eq class1 :v) (eq class1 :lv))
                            (or (eq class2 :v) (eq class2 :t)))
                       (and (eq class2 :t)
                            (or (eq class1 :lvt) (eq class1 :t))))
                   t)
                  ;; GB9
                  ((or (eq class2 :extend) (eq class2 :zwj)) t)
                  ;; GB9a, GB9b
                  ((or (eq class2 :spacing-mark) (eq class1 :prepend)) t)
                  ;; GB9c
                  ((and after-linker (%incb-p char2 +incb-consonant-vector+)) t)
                  ;; GB11
                  ((and (eq pictographic-state :zwj)
                        (%extended-pictographic-p char2))
                   t)
                  ;; GB12, GB13
                  ((and (eq class1 :regional-indicator)
                        (eq class2 :regional-indicator)
                        (evenp regional-indicators))
                   t)
                  ;; GB999
                  (t nil))
          (return position))))))

(defun %resolve-grapheme-range (string start end)
  "Validate START and END (NIL meaning the length of STRING) like STRING-WIDTH
does and return them as two values."
  (let ((end (or end (length string))))
    (%validate-string-bounds string start end)
    (values start end)))

(defun next-grapheme-boundary (string index &key (end (length string)))
  "Return the index of the next grapheme-cluster boundary in STRING strictly
after INDEX and no greater than END, or NIL when INDEX is at or past END.
INDEX must be the start of a cluster: segmentation state such as the parity
of a regional-indicator run restarts at INDEX, exactly as if STRING began
there. STRING is treated as if it ended at END. Signals an error when INDEX
and END are not valid bounds of STRING (0 <= INDEX <= END <= length).
Does not allocate."
  (%validate-string-bounds string index end)
  (if (>= index end)
      nil
      (%next-grapheme-boundary string index end)))

(defmacro do-grapheme-boundaries ((start-var end-var string
                                   &key (start 0) end result)
                                  &body body)
  "Evaluate BODY once per grapheme cluster of STRING between START and END
(NIL meaning the length of STRING), with START-VAR and END-VAR bound to the
cluster's bounds [START-VAR, END-VAR). STRING, START, and END are evaluated
once, in that order. BODY runs in an implicit block named NIL; RESULT is
evaluated and returned when iteration ends. Does not allocate."
  (let ((string-var (gensym "STRING"))
        (position (gensym "POSITION"))
        (limit (gensym "LIMIT"))
        (next (gensym "NEXT")))
    `(let ((,string-var ,string))
       (multiple-value-bind (,position ,limit)
           (%resolve-grapheme-range ,string-var ,start ,end)
         (declare (type %string-index ,position ,limit))
         (block nil
           (loop
             (when (>= ,position ,limit)
               (return ,result))
             (let ((,next (%next-grapheme-boundary ,string-var ,position ,limit)))
               (declare (type %string-index ,next))
               (let ((,start-var ,position)
                     (,end-var ,next))
                 (declare (ignorable ,start-var ,end-var))
                 ,@body)
               (setf ,position ,next))))))))

(defun grapheme-boundaries (string &key (start 0) end into)
  "Return the grapheme-cluster boundaries of STRING between START and END
(NIL meaning the length of STRING): the start offset of every cluster followed
by END, so N clusters give N+1 offsets and an empty range gives just START.
The second value is the number of offsets.

When INTO is NIL the offsets are returned as a fresh list. Otherwise INTO must
be a vector whose element type holds the offsets, and is returned after being
filled without allocating: a vector with a fill pointer has it reset to zero
and the offsets pushed (an adjustable one grows with VECTOR-PUSH-EXTEND when
needed, which does allocate); any other vector receives the offsets from index
0. Signals an error when INTO cannot hold every offset."
  (multiple-value-bind (start end) (%resolve-grapheme-range string start end)
    (cond
      ((null into)
       (let ((offsets (list start))
             (count 1))
         (declare (type %string-index count))
         (do-grapheme-boundaries (cluster-start cluster-end string
                                  :start start :end end)
           (declare (ignore cluster-start))
           (push cluster-end offsets)
           (incf count))
         (values (nreverse offsets) count)))
      ((not (vectorp into))
       (error "INTO must be NIL or a vector, got ~S." into))
      (t
       (let ((fill-pointer-p (array-has-fill-pointer-p into))
             (adjustable-p (adjustable-array-p into))
             (count 0))
         (declare (type %string-index count))
         (when fill-pointer-p
           (setf (fill-pointer into) 0))
         (flet ((store (offset)
                  (cond ((and fill-pointer-p adjustable-p)
                         (vector-push-extend offset into))
                        ((< count (array-dimension into 0))
                         (setf (aref into count) offset)
                         (when fill-pointer-p
                           (setf (fill-pointer into) (1+ count))))
                        (t
                         (error "INTO has room for ~D offsets but the range ~
                                 START=~D END=~D needs ~D."
                                (array-dimension into 0) start end
                                (nth-value 1 (grapheme-boundaries
                                              string :start start :end end)))))
                  (incf count)))
           (declare (dynamic-extent #'store))
           (store start)
           (do-grapheme-boundaries (cluster-start cluster-end string
                                    :start start :end end)
             (declare (ignore cluster-start))
             (store cluster-end)))
         (values into count))))))

(defun string-display-width (string &key (start 0) (end (length string)))
  "Return the terminal column width of STRING between START and END measured
per grapheme cluster: the sum of GRAPHEME-WIDTH over the clusters, so a base
plus combining marks or a ZWJ emoji sequence counts once. Unlike STRING-WIDTH,
which sums every code point, this is the width a terminal that renders
clusters as single glyphs displays. Does not allocate."
  (let ((width 0))
    (declare (type fixnum width))
    (do-grapheme-boundaries (cluster-start cluster-end string
                             :start start :end end :result width)
      (let ((cluster-width 0))
        (declare (type fixnum cluster-width))
        (do ((index cluster-start (1+ index)))
            ((>= index cluster-end))
          (declare (type %string-index index))
          (let ((char-width (%character-width (char string index))))
            (declare (type fixnum char-width))
            (when (> char-width cluster-width)
              (setf cluster-width char-width))))
        (incf width cluster-width)))))

(defun string-graphemes (string)
  "Return STRING split into a list of grapheme-cluster strings.
A cluster is what a reader perceives as one character -- a base plus its
combining marks, or a ZWJ emoji sequence. The clusters are the ones
DO-GRAPHEME-BOUNDARIES walks, so the list agrees with GRAPHEME-COUNT and
GRAPHEME-BOUNDARIES on every SBCL version. This is the right unit for cursor
movement and grapheme-aware truncation, unlike per-code-point iteration."
  (let ((clusters '()))
    (do-grapheme-boundaries (cluster-start cluster-end string
                             :result (nreverse clusters))
      (push (subseq string cluster-start cluster-end) clusters))))

(defun grapheme-count (string)
  "Return the number of grapheme clusters in STRING (see STRING-GRAPHEMES)."
  (let ((count 0))
    (declare (type %string-index count))
    (do-grapheme-boundaries (cluster-start cluster-end string :result count)
      (declare (ignore cluster-start cluster-end))
      (incf count))))
