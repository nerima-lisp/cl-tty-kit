(in-package #:cl-tty-kit/test)

(defmacro with-fresh-input-decoder ((decoder &key collect-bracketed-paste) &body body)
  `(let ((,decoder
        (make-input-decoder :collect-bracketed-paste ,collect-bracketed-paste)))
    ,@body))

(defun %subseq-input (input start end)
  (etypecase input
    (string (subseq input start end))
    (vector (subseq input start end))))

(defun %event-signatures-of (events)
  (mapcar #'%key-event-signature events))

(defun %chunk-eof-flags (chunks eof)
  (let ((flags (copy-list eof)))
    (append
      flags
      (make-list (max 0 (- (length chunks) (length flags))) :initial-element nil))))

(defun %decode-input-streaming-signatures (input splits &key collect-bracketed-paste)
  (with-fresh-input-decoder
    (decoder :collect-bracketed-paste collect-bracketed-paste)
    (let ((index 0)
          (events '()))
      (dolist (split splits)
        (let ((next-index (+ index split)))
          (setf events (nconc
              events
              (decode-input-chunk
                decoder
                (%subseq-input input index next-index)
                :eof
                (= next-index (length input)))))
          (setf index next-index)))
      (%event-signatures-of events))))

(defun %decode-input-single-chunk-signatures (input &key collect-bracketed-paste)
  (%event-signatures-of
    (decode-input-chunk
      (make-input-decoder :collect-bracketed-paste collect-bracketed-paste)
      input
      :eof
      t)))

(defun %assert-streaming-decode-equivalent (input splits &key collect-bracketed-paste)
  (let ((expected
        (%decode-input-single-chunk-signatures
          input
          :collect-bracketed-paste
          collect-bracketed-paste))
        (actual
        (%decode-input-streaming-signatures
          input
          splits
          :collect-bracketed-paste
          collect-bracketed-paste)))
    (is
      (equal actual expected)
      (format
        nil
        "Streaming decode should match one-shot decode for ~S with splits ~S"
        input
        splits))))

(defun %assert-all-two-way-streaming-splits (input &key collect-bracketed-paste)
  (loop for split from 1 below (length input)
        do (%assert-streaming-decode-equivalent
      input
      (list split (- (length input) split))
      :collect-bracketed-paste
      collect-bracketed-paste)))

(defun %assert-event-signatures= (events expected message)
  (is (equal (%event-signatures-of events) expected) message))

(defun %assert-example-signatures= (example-file expected message)
  (let* ((example (symbol-function (load-example-symbol example-file)))
         (events (funcall example)))
    (is (equal (mapcar #'%key-event-signature events) expected) message)))

(defun %decode-input-chunks (chunks &key collect-bracketed-paste eof)
  (with-fresh-input-decoder
    (decoder :collect-bracketed-paste collect-bracketed-paste)
    (let ((events '()))
      (loop for chunk in chunks
            for chunk-eof in (%chunk-eof-flags chunks eof)
            do (setf events (nconc events (decode-input-chunk decoder chunk :eof chunk-eof))))
      (values events decoder))))

(defun %assert-decode-input-case (input expected message)
  (%assert-event-signatures= (decode-input input) expected message))

(defun %assert-chunk-case (chunks expected message &key collect-bracketed-paste eof)
  (multiple-value-bind (events) (%decode-input-chunks
      chunks
      :collect-bracketed-paste
      collect-bracketed-paste
      :eof
      eof)
    (%assert-event-signatures= events expected message)))

(defun %assert-flush-case (chunks expected message &key collect-bracketed-paste)
  (multiple-value-bind (events decoder) (%decode-input-chunks chunks :collect-bracketed-paste collect-bracketed-paste)
    (%assert-event-signatures=
      (nconc events (flush-input-decoder decoder))
      expected
      message)))

(defun %assert-invalid-utf8-case (thunk expected-position expected-reason message)
  (handler-case (progn
      (funcall thunk)
      (is nil message))
    (invalid-utf8-sequence (condition)
      (is (= expected-position (invalid-utf8-sequence-position condition)) message)
      (is (eq expected-reason (invalid-utf8-sequence-reason condition)) message))))

(defun %test-basic-input-cases ()
  (do-test-case-bind
    (case +basic-input-cases+
      (input
        expected
        message))
    (%assert-decode-input-case input expected message)))

(defun %test-decoder-smoke-cases ()
  (let ((condition (make-condition 'unsupported-code-point :code-point #x110000)))
    (is (= #x110000 (unsupported-code-point-code-point condition)))
    (is
      (search "Unsupported Unicode code point 1114112" (format nil "~A" condition))))
  (%assert-invalid-utf8-case
    (lambda ()
      (decode-input #(227 40 130)))
    1
    :invalid-continuation-byte
    "Invalid continuation bytes should report the failing position.")
  (let ((decoder (make-input-decoder)))
    (is (null (decode-input-chunk decoder "")))
    (is (null (decode-input-chunk decoder #())))
    (is (null (flush-input-decoder decoder))))
  (signals (error c) (make-input-decoder :max-pending -1) (is c))
  (signals (error c) (make-input-decoder :max-pending 1.5) (is c))
  (progn
    (let ((decoder (make-input-decoder :collect-bracketed-paste t :max-pending 8)))
      (decode-input-chunk decoder (%esc "[200~"))
      (signals
        (cl-tty-kit::input-buffer-exceeded condition)
        (decode-input-chunk decoder "0123456789")
        (is (= 8 (cl-tty-kit::input-buffer-exceeded-limit condition)))
        (is (= 10 (cl-tty-kit::input-buffer-exceeded-size condition)))
        (is
          (string=
            "Input decoder buffer of 10 units exceeds the 8 unit limit."
            (format nil "~A" condition)))))
    (let ((decoder (make-input-decoder :collect-bracketed-paste t :max-pending 4)))
      (decode-input-chunk decoder (%esc "[200~ab"))
      (signals
        (cl-tty-kit::input-buffer-exceeded condition)
        (decode-input-chunk decoder (%esc "[2"))
        (is (= 4 (cl-tty-kit::input-buffer-exceeded-limit condition)))
        (is (= 5 (cl-tty-kit::input-buffer-exceeded-size condition))))))
  (let ((decoder (make-input-decoder :max-pending 2)))
    (is (null (decode-input-chunk decoder #(227 129))))
    (signals
      (cl-tty-kit::input-buffer-exceeded condition)
      (decode-input-chunk decoder #(130))
      (is (= 2 (cl-tty-kit::input-buffer-exceeded-limit condition)))
      (is (= 3 (cl-tty-kit::input-buffer-exceeded-size condition)))))
  (let ((decoder (make-input-decoder :max-pending 4)))
    (is (null (decode-input-chunk decoder (%esc "["))))
    (signals
      (cl-tty-kit::input-buffer-exceeded condition)
      (decode-input-chunk decoder "123")
      (is (= 4 (cl-tty-kit::input-buffer-exceeded-limit condition)))
      (is (= 5 (cl-tty-kit::input-buffer-exceeded-size condition)))))
  (let ((decoder (make-input-decoder :collect-bracketed-paste t))
        (payload (make-string 128 :initial-element #\x)))
    (decode-input-chunk decoder (%esc "[200~"))
    (loop repeat 32
          do (decode-input-chunk decoder "xxxx"))
    (%assert-event-signatures=
      (decode-input-chunk decoder (%esc "[201~") :eof t)
      `((:paste ,payload nil))
      "Split bracketed paste payloads should emit the accumulated text once."))
  (progn
    (let ((decoder
          (make-input-decoder :collect-bracketed-paste t :normalize-paste-line-endings t)))
      (%assert-event-signatures=
        (decode-input-chunk
          decoder
          (%esc
            "[200~"
            "line1"
            (string #\Return)
            (string #\Newline)
            "line2"
            (string #\Return)
            "line3"
            (string #\Esc)
            "[201~")
          :eof
          t)
        `((:paste ,(format nil "line1~%line2~%line3") nil))
        "NORMALIZE-PASTE-LINE-ENDINGS should convert CRLF and lone CR to LF."))
    (let ((payload (format nil "line1~%line2")))
      (is
        (eq payload (cl-tty-kit::%normalize-paste-line-endings payload))
        "LF-only paste normalization should reuse the copied payload.")))
  (let ((decoder (make-input-decoder :collect-bracketed-paste t)))
    (%assert-event-signatures=
      (decode-input-chunk
        decoder
        (%esc
          "[200~"
          "a"
          (string #\Return)
          (string #\Newline)
          "b"
          (string #\Esc)
          "[201~")
        :eof
        t)
      `((:paste ,(concatenate 'string "a" (string #\Return) (string #\Newline) "b") nil))
      "Without NORMALIZE-PASTE-LINE-ENDINGS, CR is preserved verbatim."))
  (let* ((decoder (make-input-decoder :max-pending 2048))
         (input (%esc "[" (make-string 1025 :initial-element #\1))))
    (is (decode-input-chunk decoder input))
    (is (null (flush-input-decoder decoder))))
  (let ((decoder (make-input-decoder)))
    (is (null (decode-input-chunk decoder #(227 129))))
    (%assert-event-signatures=
      (decode-input-chunk decoder "x")
      (quote ((:character #\x nil)))
      "A string chunk fed while UTF-8 octets are still pending should decode normally, leaving the incomplete octets buffered.")
    (is (= 2 (length (cl-tty-kit::input-decoder-pending-octets decoder)))
        "A non-final string chunk must leave the incomplete octet tail intact.")
    (%assert-event-signatures=
      (decode-input-chunk decoder #(130) :eof t)
      `((:character ,(code-char #x3042) nil))
      "Completing the pending octets afterward should recover the buffered character."))
  (let ((decoder (make-input-decoder)))
    (is (null (decode-input-chunk decoder #(227 129))))
    (%assert-invalid-utf8-case
      (lambda ()
        (decode-input-chunk decoder "x" :eof t))
      0
      :truncated-sequence
      "A final string chunk should force any pending octets through the truncated-sequence fallback."))
  (let ((decoder (make-input-decoder))
        (first-chunk
        (make-array 2 :element-type '(unsigned-byte 8) :initial-contents '(227 129)))
        (second-chunk
        (make-array 2 :element-type '(unsigned-byte 8) :initial-contents '(130 120))))
    (is (null (decode-input-chunk decoder first-chunk)))
    (%assert-event-signatures=
      (decode-input-chunk decoder second-chunk :eof t)
      `((:character ,(code-char #x3042) nil) (:character #\x nil))
      "Specialized octet chunks should preserve split UTF-8 streaming behavior.")))

(defun %test-streaming-input-cases ()
  (do-test-case-bind
    (case +streaming-input-cases+
      (chunks
        expected
        message
        &key
        collect-bracketed-paste))
    (%assert-chunk-case
      chunks
      expected
      message
      :collect-bracketed-paste
      collect-bracketed-paste)))

(defun %test-flush-and-error-cases ()
  (%assert-flush-case
    (list (string #\Esc))
    '((:special :escape nil))
    "Flushing a pending escape should emit an escape event.")
  (let ((decoder (make-input-decoder)))
    (is (null (decode-input-chunk decoder (%esc "["))))
    (let ((events (decode-input-chunk decoder "x" :eof t)))
      (is
        (equal
          (%event-signatures-of events)
          (%event-signatures-of (decode-input (%esc "[x")))))))
  (let ((decoder (make-input-decoder)))
    (is (null (decode-input-chunk decoder #(227 129))))
    (%assert-invalid-utf8-case
      (lambda ()
        (flush-input-decoder decoder))
      0
      :truncated-sequence
      "Flushing a partial UTF-8 sequence should signal truncation."))
  (%assert-invalid-utf8-case
    (lambda ()
      (decode-input #(255 97)))
    0
    :invalid-leading-byte
    "Invalid leading bytes should fail immediately.")
  (signals (error c) (decode-input #(#\a 1)) (is c))
  (signals (error c) (decode-input 42) (is c))
  (let ((decoder (make-input-decoder)))
    (signals (error c) (decode-input-chunk decoder #(#\a 1)) (is c)))
  (let ((decoder (make-input-decoder)))
    (signals (error c) (decode-input-chunk decoder 42) (is c)))
  (%assert-flush-case
    (list (%esc "[200~ab"))
    `((:special :paste-start nil) (:character ,#\a nil) (:character ,#\b nil))
    "Flushing an unterminated paste should fall back to ordinary decoding."
    :collect-bracketed-paste
    t)
  (%assert-flush-case
    (list (concatenate 'string "x" (%esc "[200~ab")))
    `((:character ,#\x nil)
      (:special :paste-start nil)
      (:character ,#\a nil)
      (:character ,#\b nil))
    "Flushing an unterminated paste should retain preceding event order."
    :collect-bracketed-paste
    t)
  (%assert-chunk-case
    (list (%esc "[200~abc" (string #\Esc) "[2") "0" "1" "~z")
    `((:paste "abc" nil) (:character ,#\z nil))
    "Incremental paste terminator detection should preserve following input."
    :collect-bracketed-paste
    t)
  (let* ((input (%esc "[200~abc" (string #\Esc) "[2"))
         (decoder (make-input-decoder :collect-bracketed-paste t)))
    (%assert-event-signatures=
      (decode-input-chunk decoder input :eof t)
      (%event-signatures-of (decode-input input))
      "EOF during a partial paste terminator should fall back to ordinary decoding.")))

(defun %test-streaming-equivalence-cases ()
  (do-test-case-bind
    (case +streaming-equivalence-cases+
      (input options))
    (apply #'%assert-all-two-way-streaming-splits input options))
  (%assert-streaming-decode-equivalent
    (%esc "[200~hello" (string #\Esc) "[201~x")
    '(1 1 2 3 4 2 2 1 1 1)
    :collect-bracketed-paste
    t))

(defparameter +input-example-cases+ `(("examples/key-decoding.lisp"
      ((:character #\a nil)
        (:special :control-c nil)
        (:special :up nil)
        (:character #\i (:control :shift))
        (:special :paste-start nil)
        (:special :paste-end nil)
        (:special :backtab nil)
        (:special :menu (:alt))
        (:special :up nil)
        (:character #\x (:alt)))
      "The key-decoding example should stay stable as a complete event trace.")
    ("examples/streaming-paste.lisp"
      ((:paste "hello" nil))
      "The streaming-paste example should produce a single paste event.")
    ("examples/event-loop.lisp"
      ((:character #\j nil)
        (:special :up nil)
        (:paste "hello" nil)
        (:character #\q nil))
      "The event-loop example should preserve the documented trace.")))

(defun %assert-input-example-case (example-file expected message)
  (%assert-example-signatures= example-file expected message))

(defun %test-input-examples ()
  (do-test-case-bind
    (case +input-example-cases+
      (example-file
        expected
        message))
    (%assert-input-example-case example-file expected message)))

(defun test-input ()
  (%test-basic-input-cases)
  (%test-decoder-smoke-cases)
  (%test-streaming-input-cases)
  (%test-flush-and-error-cases)
  (%test-streaming-equivalence-cases)
  (%test-input-examples))
