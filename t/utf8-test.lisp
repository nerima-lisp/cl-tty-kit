(in-package #:cl-tty-kit/test)

(defun %u8 (&rest octets)
  (coerce octets '(vector (unsigned-byte 8))))

(defun %invalid-utf8-matcher (expected-reason position octet)
  (lambda (condition)
    (and (typep condition 'invalid-utf8-sequence)
         (= position (invalid-utf8-sequence-position condition))
         (eq expected-reason (invalid-utf8-sequence-reason condition))
         (or (null octet) (= octet (invalid-utf8-sequence-octet condition))))))

(defmacro expect-invalid-utf8 (octets expected-reason &key (position 0) octet)
  `(expect (lambda () (cl-tty-kit::%utf8-octets-to-string ,octets))
           :to-throw
           (%invalid-utf8-matcher ,expected-reason ,position ,octet)))

(describe "decoding UTF-8 octets to a string"
  (it "decodes plain ASCII"
    (expect (cl-tty-kit::%utf8-octets-to-string (%u8 97 98 99)) :to-equal "abc"))
  (it "decodes a general octet vector"
    (expect (cl-tty-kit::%utf8-octets-to-string #(97 98 99)) :to-equal "abc"))
  (it "decodes a 2-byte sequence"
    (expect (cl-tty-kit::%utf8-octets-to-string (%u8 #xC2 #xA2)) :to-equal "¢"))
  (it "decodes a 3-byte sequence"
    (expect (cl-tty-kit::%utf8-octets-to-string (%u8 #xE3 #x81 #x82)) :to-equal "あ"))
  (it "decodes a 4-byte sequence"
    (expect (cl-tty-kit::%utf8-octets-to-string (%u8 #xF0 #x9F #x98 #x80)) :to-equal "😀")))

(describe "rejecting malformed UTF-8"
  (it "rejects a non-octet element outright"
    (expect-invalid-utf8 #(256) :non-octet :octet 256))
  (it "rejects a 2-byte sequence truncated after its leading byte"
    (expect-invalid-utf8 (%u8 #xC2) :truncated-sequence :octet #xC2))
  (it "rejects a 3-byte sequence truncated after one continuation byte"
    (expect-invalid-utf8 (%u8 #xE3 #x81) :truncated-sequence :octet #xE3))
  (it "rejects a 4-byte sequence truncated after two continuation bytes"
    (expect-invalid-utf8 (%u8 #xF0 #x9F #x98) :truncated-sequence :octet #xF0))
  (it "rejects a continuation byte that isn't in 80-BF"
    (expect-invalid-utf8 (%u8 #xC2 #x20) :invalid-continuation-byte
                         :position 1 :octet #x20))
  (it "rejects a 3-byte overlong encoding"
    (expect-invalid-utf8 (%u8 #xE0 #x80 #x80) :overlong-sequence :octet #xE0))
  (it "rejects a UTF-16 surrogate half encoded as UTF-8"
    (expect-invalid-utf8 (%u8 #xED #xA0 #x80) :surrogate-half :octet #xED))
  (it "rejects a 4-byte overlong encoding"
    (expect-invalid-utf8 (%u8 #xF0 #x80 #x80 #x80) :overlong-sequence :octet #xF0))
  (it "rejects a code point beyond U+10FFFF"
    (expect-invalid-utf8 (%u8 #xF4 #x90 #x80 #x80) :code-point-too-large :octet #xF4))
  (it "rejects a bare continuation byte as a leading byte"
    (expect-invalid-utf8 (%u8 #x80) :invalid-leading-byte :octet #x80))
  (it "rejects the overlong-only leading byte 0xC0"
    (expect-invalid-utf8 (%u8 #xC0) :invalid-leading-byte :octet #xC0))
  (it "rejects the overlong-only leading byte 0xC1"
    (expect-invalid-utf8 (%u8 #xC1) :invalid-leading-byte :octet #xC1))
  (it "rejects a leading byte beyond the valid U+10FFFF range"
    (expect-invalid-utf8 (%u8 #xF5) :invalid-leading-byte :octet #xF5)))

(describe "%utf8-decode-prefix"
  (it "signals invalid-utf8-sequence for a non-octet element"
    (expect (lambda () (cl-tty-kit::%utf8-decode-prefix #(97 :not-an-octet)))
            :to-throw (%invalid-utf8-matcher :non-octet 1 nil)))
  (it "decodes every complete character and returns an empty leftover"
    (let ((octets (%u8 97 #xC2 #xA2)))
      (multiple-value-bind (string leftover) (cl-tty-kit::%utf8-decode-prefix octets)
        (expect string :to-equal "a¢")
        (expect (zerop (length leftover)))
        (expect (typep leftover '(vector (unsigned-byte 8))))
        (expect (not (eq octets leftover))))))
  (it "leaves a trailing incomplete sequence in the returned leftover, independent of the input"
    (let ((octets (%u8 97 #xC2)))
      (multiple-value-bind (string leftover) (cl-tty-kit::%utf8-decode-prefix octets)
        (expect string :to-equal "a")
        (setf (aref octets 1) #xA2)
        (expect leftover :to-equalp (%u8 #xC2))))))

(describe "%octet-input-p"
  ;; %OCTET-INPUT-P's own contract, verified directly: a string is never
  ;; octet input regardless of being a vector, nor is a character vector;
  ;; only a vector of integers (or one typed (UNSIGNED-BYTE 8)) is. Neither
  ;; caller of this predicate (%INPUT->STRING, %DECODER-DECODE-CHUNK-STRING)
  ;; reaches it with a string -- both check STRINGP first -- so this is the
  ;; only place the string case is exercised at all.
  (it "rejects a string even though it is a vector"
    (expect (cl-tty-kit::%octet-input-p "abc") :to-be-falsy))
  (it "rejects a character vector"
    (expect (cl-tty-kit::%octet-input-p (coerce (list #\a #\b) 'vector)) :to-be-falsy))
  (it "accepts a vector of octets"
    (expect (cl-tty-kit::%octet-input-p (%u8 97 98 99)) :to-be-truthy)))
