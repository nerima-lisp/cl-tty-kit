(defpackage #:cl-tty-kit/weave-property-tests
  (:use #:cl)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
                #:expect #:it #:it-property
                #:gen-integer #:gen-string #:gen-vector #:gen-character
                #:run-all)
  (:export #:run-tests))

(in-package #:cl-tty-kit/weave-property-tests)

;;; Advanced usage of nerima-lisp/cl-weave: property-based fuzzing of the two
;;; decoders that consume attacker-controlled PTY bytes, plus regression
;;; coverage for contrib/cl-prolog-kit-csi-grammar.lisp's DCG recognizer. Every
;;; decoder property below encodes the same contract each decoder already
;;; documents: malformed input signals a CL-TTY-KIT condition, never an
;;; unrelated Lisp error escaping from array indexing or type mismatches.

(defparameter +csi-final-bytes+
  (coerce (loop for code from #x40 to #x7E collect (code-char code)) 'string)
  "Every ECMA-48 CSI final byte (0x40-0x7E), as a GEN-CHARACTER alphabet.")

(describe "cl-prolog-kit DCG: ECMA-48 CSI grammar (contrib/cl-prolog-kit-csi-grammar.lisp)"
  (it "accepts a bare final byte"
    (expect (tty-csi-grammar:csi-sequence-valid-p "H")))
  (it "accepts a parameter plus a final byte"
    (expect (tty-csi-grammar:csi-sequence-valid-p "1;1H")))
  (it "accepts SGR-style multi-parameter sequences"
    (expect (tty-csi-grammar:csi-sequence-valid-p "38;5;196m")))
  (it "accepts a private-marker parameter prefix"
    (expect (tty-csi-grammar:csi-sequence-valid-p "?25h")))
  (it "rejects an empty body"
    (expect (not (tty-csi-grammar:csi-sequence-valid-p ""))))
  (it "rejects a body with no final byte"
    (expect (not (tty-csi-grammar:csi-sequence-valid-p "1;1"))))
  (it "rejects trailing bytes after the final byte"
    (expect (not (tty-csi-grammar:csi-sequence-valid-p "1H2"))))

  (it-property "any digit/semicolon run followed by one final byte is a valid CSI body"
      ((param-run (gen-string :min-length 0 :max-length 12 :alphabet "0123456789;"))
       (final (gen-character :alphabet +csi-final-bytes+)))
    (expect (tty-csi-grammar:csi-sequence-valid-p
             (concatenate 'string param-run (string final))))))

(describe "src/utf8.lisp: decoder robustness under arbitrary octets"
  (it-property "the internal octet decoder only ever signals a documented condition"
      ((octets (gen-vector (gen-integer :min 0 :max 255) :min-length 0 :max-length 16)))
    (expect (handler-case
                (progn (cl-tty-kit::%utf8-octets-to-string
                        (coerce octets '(vector (unsigned-byte 8))))
                       t)
              (cl-tty-kit:tty-kit-error () t)
              (error () nil)))))

(describe "cl-tty-kit:decode-input: public decoder robustness under arbitrary octets"
  (it-property "malformed octet input never escapes as an undocumented Lisp error"
      ((octets (gen-vector (gen-integer :min 0 :max 255) :min-length 0 :max-length 24)))
    (expect (handler-case
                (progn (cl-tty-kit:decode-input
                        (coerce octets '(vector (unsigned-byte 8))))
                       t)
              (cl-tty-kit:tty-kit-error () t)
              (error () nil)))))

(defun run-tests ()
  "Run every DESCRIBE/IT-PROPERTY block registered above and return true iff
all of them passed."
  (run-all :reporter :spec))
