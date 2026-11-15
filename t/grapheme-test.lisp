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

(defparameter *grapheme-cases*
  ;; (code points, cluster lengths SB-UNICODE:GRAPHEMES produces)
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
    ((#x915 #x94D #x937) (2 1))))

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

(defun %error-type-of (thunk)
  (handler-case (progn (funcall thunk) nil)
    (error (condition) (type-of condition))))

(describe "next-grapheme-boundary"
  (it "agrees with SB-UNICODE:GRAPHEMES on the named UAX #29 cases"
    (dolist (case *grapheme-cases*)
      (let ((string (%code-points->string (first case))))
        (expect (%boundaries->lengths (grapheme-boundaries string))
                :to-equal (second case))
        (expect (grapheme-boundaries string)
                :to-equal (%sbcl-grapheme-boundaries string)))))
  (it "agrees with SB-UNICODE:GRAPHEMES on a fixed-seed pseudo-random corpus"
    (expect (length *grapheme-corpus*) :to-be-greater-than 400)
    (dolist (string *grapheme-corpus*)
      (expect (grapheme-boundaries string)
              :to-equal (%sbcl-grapheme-boundaries string))))
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
  (it "is the sum of GRAPHEME-WIDTH over STRING-GRAPHEMES on the corpus"
    (dolist (string *grapheme-corpus*)
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
  (it "keeps GRAPHEME-COUNT equal to the length of STRING-GRAPHEMES"
    (dolist (string *grapheme-corpus*)
      (expect (grapheme-count string) :to-be (length (string-graphemes string))))
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
