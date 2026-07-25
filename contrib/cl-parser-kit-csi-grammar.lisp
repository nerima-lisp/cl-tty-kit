(defpackage #:cl-tty-kit/cl-parser-kit-csi-grammar
  (:use #:cl)
  (:import-from #:cl-parser-kit
                #:make-token #:type-token #:many #:seq #:end-of-input
                #:parse-tokens)
  (:nicknames #:tty-csi-parser-kit-grammar)
  (:documentation
   "Advanced usage of nerima-lisp/cl-parser-kit: a parser-combinator
recognizer for the same ECMA-48 CSI (Control Sequence Introducer) byte-class
grammar contrib/cl-prolog-csi-grammar.lisp recognizes via cl-prolog's DCG
support. src/input-decode.lisp already decodes CSI sequences imperatively
for the render loop's hot path; this module is a second, independent
declarative specification of that same sequence shape -- zero or more
parameter bytes, then zero or more intermediate bytes, then exactly one
final byte -- built from cl-parser-kit's SEQ/MANY/TYPE-TOKEN combinators
instead of Prolog relations.")
  (:export #:csi-sequence-valid-p))

(in-package #:cl-tty-kit/cl-parser-kit-csi-grammar)

(defun %csi-byte-kind (char)
  "Classify CHAR into an ECMA-48 CSI byte class, or NIL if it fits none."
  (let ((code (char-code char)))
    (cond ((<= #x30 code #x3F) :param)
          ((<= #x20 code #x2F) :intermediate)
          ((<= #x40 code #x7E) :final)
          (t nil))))

(defun %tokenize-csi-body (string)
  "Classify each character of STRING into a CL-PARSER-KIT token vector.
Returns (VALUES TOKENS VALID-P). VALID-P is false when STRING contains a
byte outside the three CSI byte ranges."
  (let ((tokens '()))
    (loop for char across string
          for kind = (%csi-byte-kind char)
          unless kind
            do (return-from %tokenize-csi-body (values #() nil))
          do (push (make-token :type kind :text (string char) :value char) tokens))
    (values (coerce (nreverse tokens) 'vector) t)))

(defparameter *csi-sequence-parser*
  (seq (many (type-token :param))
       (many (type-token :intermediate))
       (type-token :final)
       (end-of-input))
  "The ECMA-48 CSI-body grammar: PARAMETER-BYTES* INTERMEDIATE-BYTES* FINAL-BYTE.
The trailing END-OF-INPUT rejects a sequence with bytes past its final byte
-- e.g. \"1H2\" -- the way PHRASE's remainder check does for the DCG version.")

(defun csi-sequence-valid-p (string)
  "Return true when STRING is exactly one structurally valid ECMA-48 CSI
sequence body: zero or more parameter bytes, then zero or more intermediate
bytes, then exactly one final byte. STRING excludes the leading ESC [ that
introduces the sequence."
  (multiple-value-bind (tokens valid-chars-p) (%tokenize-csi-body string)
    (and valid-chars-p
         (nth-value 0 (parse-tokens *csi-sequence-parser* tokens)))))
