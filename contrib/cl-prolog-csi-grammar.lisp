(defpackage #:cl-tty-kit/cl-prolog-csi-grammar
  (:use #:cl)
  (:import-from #:cl-prolog #:make-rulebase #:def-dcg-rule #:dcg-star #:phrase)
  (:nicknames #:tty-csi-grammar)
  (:documentation
   "Advanced usage of nerima-lisp/cl-prolog: a DCG recognizer for the ECMA-48 CSI
(Control Sequence Introducer) byte-class grammar. `src/input-decode.lisp`
already decodes CSI sequences imperatively for the render loop's hot path;
this module instead gives that same sequence shape a declarative grammar
built from cl-prolog's `def-dcg-rule`/`phrase`, useful for validating or
documenting the shape independently of the hand-written decoder.

A CSI sequence body (the bytes after ESC [) is, per ECMA-48 section 5.4:
zero or more parameter bytes (0x30-0x3F: digits, `;`, `:`, `<`, `=`, `>`,
`?`), then zero or more intermediate bytes (0x20-0x2F), then exactly one
final byte (0x40-0x7E).")
  (:export #:csi-sequence-valid-p
           #:tokenize-csi-body
           #:*csi-grammar*))

(in-package #:cl-tty-kit/cl-prolog-csi-grammar)

(defun %csi-byte-kind (char)
  "Classify CHAR into an ECMA-48 CSI byte class, or NIL if it fits none."
  (let ((code (char-code char)))
    (cond ((<= #x30 code #x3F) :param)
          ((<= #x20 code #x2F) :intermediate)
          ((<= #x40 code #x7E) :final)
          (t nil))))

(defun tokenize-csi-body (string)
  "Classify each character of STRING into a DCG token stream of
`(:param | :intermediate | :final . CHAR)` conses.

Returns (VALUES TOKENS VALID-P). VALID-P is false when STRING contains a
byte outside the three CSI byte ranges; TOKENS then holds only the
classified prefix up to (not including) the offending character."
  (let ((tokens '()))
    (loop for char across string
          for kind = (%csi-byte-kind char)
          unless kind
            do (return-from tokenize-csi-body (values (nreverse tokens) nil))
          do (push (cons kind char) tokens))
    (values (nreverse tokens) t)))

(defparameter *csi-grammar*
  (make-rulebase
   :clauses
   (list (def-dcg-rule csi-param-byte (terminal :param))
         (def-dcg-rule csi-intermediate-byte (terminal :intermediate))
         (def-dcg-rule csi-final-byte (terminal :final))
         (def-dcg-rule csi-parameter-bytes (dcg-star csi-param-byte))
         (def-dcg-rule csi-intermediate-bytes (dcg-star csi-intermediate-byte))
         (def-dcg-rule csi-sequence
           csi-parameter-bytes
           csi-intermediate-bytes
           csi-final-byte)))
  "The ECMA-48 CSI-body grammar: PARAMETER-BYTES* INTERMEDIATE-BYTES* FINAL-BYTE.")

(defun csi-sequence-valid-p (string)
  "Return true when STRING is exactly one structurally valid ECMA-48 CSI
sequence body: zero or more parameter bytes, then zero or more
intermediate bytes, then exactly one final byte. STRING excludes the
leading ESC [ that introduces the sequence."
  (multiple-value-bind (tokens valid-chars-p) (tokenize-csi-body string)
    (and valid-chars-p
         tokens
         (multiple-value-bind (remainder matched-p)
             (phrase *csi-grammar* 'csi-sequence tokens)
           ;; PHRASE succeeds on the first (possibly partial) parse, so a
           ;; sequence with trailing bytes past its final byte -- e.g. "1H2"
           ;; -- would otherwise read as valid with "2" left in REMAINDER.
           (and matched-p (null remainder))))))
