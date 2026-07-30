(in-package #:cl-tty-kit)

(declaim (ftype function %signal-invalid-utf8-sequence))

(defun %utf8-continuation-octet-p (octet)
  (and (<= #x80 octet)
       (<= octet #xBF)))

(defun %utf8-octet-at (vector index)
  (let ((octet (aref vector index)))
    (unless (typep octet '(integer 0 255))
      (%signal-invalid-utf8-sequence index octet :non-octet))
    octet))

(defun %string-to-utf8-octets (string)
  (sb-ext:string-to-octets string :external-format :utf-8))

(defun %utf8-emit-code-point (code)
  (or (code-char code)
      (error 'unsupported-code-point :code-point code)))

(defun %utf8-sequence-length (first)
  "Return the UTF-8 sequence length selected by FIRST, or NIL when invalid."
  (cond
    ((<= #xC2 first #xDF) 2)
    ((<= #xE0 first #xEF) 3)
    ((<= #xF0 first #xF4) 4)
    (t nil)))

(defun %utf8-min-code-point (sequence-length)
  (ecase sequence-length
    (2 #x80)
    (3 #x800)
    (4 #x10000)))

(defun %utf8-validate-code-point (index first code-point min-code-point)
  "Signal a structured error when CODE-POINT (already fully assembled from
FIRST and its continuation octets) violates a UTF-8 or Unicode invariant.
There is no separate F4-leading-byte overflow check: for a 4-byte sequence
whose leading byte is F4, any second octet above #x8F already assembles a
CODE-POINT above #x10FFFF, so the general upper-bound check below already
covers it."
  (when (< code-point min-code-point)
    (%signal-invalid-utf8-sequence index first :overlong-sequence))
  (when (<= #xD800 code-point #xDFFF)
    (%signal-invalid-utf8-sequence index first :surrogate-half))
  (when (> code-point #x10FFFF)
    (%signal-invalid-utf8-sequence index first :code-point-too-large)))

(defun %utf8-decode-multibyte (vector index length first)
  "Decode one validated multibyte sequence without allocating continuation lists."
  (let ((sequence-length (%utf8-sequence-length first)))
    (unless sequence-length
      (%signal-invalid-utf8-sequence index first :invalid-leading-byte))
    (when (> (+ index sequence-length) length)
      (%signal-invalid-utf8-sequence index first :truncated-sequence))
    (flet ((continuation (offset)
             (let* ((octet-index (+ index offset))
                    (octet (%utf8-octet-at vector octet-index)))
               (unless (%utf8-continuation-octet-p octet)
                 (%signal-invalid-utf8-sequence octet-index octet
                                                :invalid-continuation-byte))
               octet)))
      (let* ((second (continuation 1))
             (code-point
               (case sequence-length
                 (2
                  (logior (ash (logand first #x1F) 6)
                          (logand second #x3F)))
                 (3
                  (let ((third (continuation 2)))
                    (logior (ash (logand first #x0F) 12)
                            (ash (logand second #x3F) 6)
                            (logand third #x3F))))
                 (4
                  (let ((third (continuation 2))
                        (fourth (continuation 3)))
                    (logior (ash (logand first #x07) 18)
                            (ash (logand second #x3F) 12)
                            (ash (logand third #x3F) 6)
                            (logand fourth #x3F)))))))
        (%utf8-validate-code-point index
                                   first
                                   code-point
                                   (%utf8-min-code-point sequence-length))
        (values (%utf8-emit-code-point code-point)
                (+ index sequence-length))))))

(defun %utf8-decode-at (vector index length)
  (let ((first (%utf8-octet-at vector index)))
    (if (< first #x80)
        (values (%utf8-emit-code-point first) (1+ index))
        (%utf8-decode-multibyte vector index length first))))

(defun %utf8-write-decoded-octets (vector stream)
  "Decode VECTOR to STREAM without constructing an intermediate string."
  (loop with index = 0
        with limit = (length vector)
        while (< index limit)
        do (multiple-value-bind (char next-index)
               (%utf8-decode-at vector index limit)
             (write-char char stream)
             (setf index next-index))))

(defun %utf8-octets-to-string (vector)
  (with-output-to-string (stream)
    (%utf8-write-decoded-octets vector stream)))

(defun %octet-input-p (input)
  "Return true when INPUT should be decoded as UTF-8 octets, not characters.
Both `(unsigned-byte 8)` vectors and general vectors whose elements are integers
(such as the literal #(97 98 99)) count as octet input; strings and character
vectors do not."
  (and (vectorp input)
       (not (stringp input))
       (or (subtypep (array-element-type input) '(unsigned-byte 8))
           (and (plusp (length input))
                (integerp (aref input 0))))))

(defun %coerce-character-vector (input)
  "Coerce a non-octet vector INPUT to a string when every element is a
character. Signals when INPUT is a vector containing a non-character element,
or is not a vector at all -- the shared fallback for %INPUT->STRING and
%DECODER-DECODE-CHUNK-STRING once STRINGP and %OCTET-INPUT-P have both
declined it."
  (cond
    ((vectorp input)
     (unless (loop for index below (length input)
                   always (characterp (aref input index)))
       (error "Unsupported input vector element in ~S." input))
     (coerce input 'string))
    (t
     (error "Unsupported input type: ~S" (type-of input)))))

(defun %utf8-incomplete-tail-start (vector)
  "Return the start index of an incomplete trailing UTF-8 multibyte sequence in
VECTOR, or NIL when VECTOR ends on a character boundary. Only a genuinely
truncated final sequence is reported; complete or invalid bytes end the scan so
the caller decodes (and validates) them normally."
  (let ((length (length vector)))
    (loop for index from (1- length) downto (max 0 (- length 3))
          for octet = (%utf8-octet-at vector index)
          do (cond
               ((< octet #x80)
                (return nil))
               ((%utf8-continuation-octet-p octet))
               (t
                (let ((sequence-length (%utf8-sequence-length octet)))
                  (return
                    (when (and sequence-length
                               (< (- length index) sequence-length))
                      index)))))
          finally (return nil))))

(defun %utf8-decode-prefix (vector)
  "Decode the complete UTF-8 prefix of octet VECTOR.
Return two values: the decoded string and a fresh octet vector holding any
incomplete trailing multibyte sequence (empty when VECTOR ends on a boundary).
Genuinely invalid octets in the prefix still signal INVALID-UTF8-SEQUENCE."
  (let ((tail (%utf8-incomplete-tail-start vector)))
    (if tail
        (values (%utf8-octets-to-string (subseq vector 0 tail))
                (subseq vector tail))
        (values (%utf8-octets-to-string vector)
                (make-array 0 :element-type (array-element-type vector))))))
