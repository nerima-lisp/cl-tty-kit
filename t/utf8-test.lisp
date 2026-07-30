(in-package #:cl-tty-kit/test)

(defun %u8 (&rest octets)
  (coerce octets '(vector (unsigned-byte 8))))

(defun %assert-invalid-utf8 (octets expected-reason &key (position 0) octet)
  (signals (invalid-utf8-sequence condition)
      (cl-tty-kit::%utf8-octets-to-string octets)
    (is (= position (invalid-utf8-sequence-position condition)))
    (is (eq expected-reason
            (invalid-utf8-sequence-reason condition)))
    (when octet
      (is (= octet (invalid-utf8-sequence-octet condition))))))

(defun %assert-octets= (expected actual)
  (is (equalp expected actual)))

(defun test-utf8 ()
  (is (string= "abc"
               (cl-tty-kit::%utf8-octets-to-string (%u8 97 98 99))))
  (is (string= "¢"
               (cl-tty-kit::%utf8-octets-to-string (%u8 #xC2 #xA2))))
  (is (string= "あ"
               (cl-tty-kit::%utf8-octets-to-string (%u8 #xE3 #x81 #x82))))
  (is (string= "😀"
               (cl-tty-kit::%utf8-octets-to-string (%u8 #xF0 #x9F #x98 #x80))))
  (%assert-octets= (%u8 97 98 99)
                   (cl-tty-kit::%string-to-utf8-octets "abc"))
  (%assert-octets= (%u8 #xC2 #xA2)
                   (cl-tty-kit::%string-to-utf8-octets "¢"))
  (%assert-octets= (%u8 #xE3 #x81 #x82)
                   (cl-tty-kit::%string-to-utf8-octets "あ"))
  (%assert-octets= (%u8 #xF0 #x9F #x98 #x80)
                   (cl-tty-kit::%string-to-utf8-octets "😀"))
  (%assert-invalid-utf8 #(256) :non-octet :octet 256)
  (%assert-invalid-utf8 (%u8 #xC2) :truncated-sequence :octet #xC2)
  (%assert-invalid-utf8 (%u8 #xE3 #x81) :truncated-sequence :octet #xE3)
  (%assert-invalid-utf8 (%u8 #xF0 #x9F #x98) :truncated-sequence :octet #xF0)
  (%assert-invalid-utf8 (%u8 #xC2 #x20) :invalid-continuation-byte
                        :position 1
                        :octet #x20)
  (%assert-invalid-utf8 (%u8 #xE0 #x80 #x80) :overlong-sequence
                        :octet #xE0)
  (%assert-invalid-utf8 (%u8 #xED #xA0 #x80) :surrogate-half
                        :octet #xED)
  (%assert-invalid-utf8 (%u8 #xF0 #x80 #x80 #x80) :overlong-sequence
                        :octet #xF0)
  (%assert-invalid-utf8 (%u8 #xF4 #x90 #x80 #x80) :code-point-too-large
                        :octet #xF4)
  (%assert-invalid-utf8 (%u8 #x80) :invalid-leading-byte :octet #x80)
  (%assert-invalid-utf8 (%u8 #xC0) :invalid-leading-byte :octet #xC0)
  (%assert-invalid-utf8 (%u8 #xC1) :invalid-leading-byte :octet #xC1)
  (%assert-invalid-utf8 (%u8 #xF5) :invalid-leading-byte :octet #xF5)
  (signals (invalid-utf8-sequence condition)
      (cl-tty-kit::%utf8-decode-prefix #(97 :not-an-octet))
    (is (= 1 (invalid-utf8-sequence-position condition)))
    (is (eq :non-octet (invalid-utf8-sequence-reason condition))))
  (let ((octets (%u8 97 #xC2 #xA2)))
    (multiple-value-bind (string leftover)
        (cl-tty-kit::%utf8-decode-prefix octets)
      (is (string= "a¢" string))
      (is (zerop (length leftover)))
      (is (typep leftover '(vector (unsigned-byte 8))))
      (is (not (eq octets leftover)))))
  (let ((octets (%u8 97 #xC2)))
    (multiple-value-bind (string leftover)
        (cl-tty-kit::%utf8-decode-prefix octets)
      (is (string= "a" string))
      (setf (aref octets 1) #xA2)
      (%assert-octets= (%u8 #xC2) leftover)))
  ;; %OCTET-INPUT-P's own contract, verified directly: a string is never
  ;; octet input regardless of being a vector, nor is a character vector;
  ;; only a vector of integers (or one typed (UNSIGNED-BYTE 8)) is. Neither
  ;; caller of this predicate (%INPUT->STRING, %DECODER-DECODE-CHUNK-STRING)
  ;; reaches it with a string -- both check STRINGP first -- so this is the
  ;; only place the string case is exercised at all.
  (is (null (cl-tty-kit::%octet-input-p "abc")))
  (is (null (cl-tty-kit::%octet-input-p (coerce (list #\a #\b) 'vector))))
  (is (cl-tty-kit::%octet-input-p (%u8 97 98 99))))
