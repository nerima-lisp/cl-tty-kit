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

(defun %decode-input-chunks (chunks &key collect-bracketed-paste eof)
  (with-fresh-input-decoder
    (decoder :collect-bracketed-paste collect-bracketed-paste)
    (let ((events '()))
      (loop for chunk in chunks
            for chunk-eof in (%chunk-eof-flags chunks eof)
            do (setf events (nconc events (decode-input-chunk decoder chunk :eof chunk-eof))))
      (values events decoder))))

(defmacro %expect-invalid-utf8 (form expected-position expected-reason)
  "The shared assertion for a FORM that must signal INVALID-UTF8-SEQUENCE at
EXPECTED-POSITION with EXPECTED-REASON: every invalid-UTF-8 case in this file
checks both of those slots, never just that some error was signaled."
  `(expect (lambda () ,form)
           :to-throw (lambda (condition)
                       (and (typep condition 'invalid-utf8-sequence)
                            (= ,expected-position (invalid-utf8-sequence-position condition))
                            (eq ,expected-reason (invalid-utf8-sequence-reason condition))))))

(describe "decode-input over basic ASCII/UTF-8/control/paste-marker input"
  (dolist (case +basic-input-cases+)
    (destructuring-bind (input expected message) case
      (it message
        (expect (%event-signatures-of (decode-input input)) :to-equal expected)))))

(describe "decode-input accepts general octet vectors"
  (it "decodes a general vector of octets"
    (expect (%event-signatures-of (decode-input #(97 98 99)))
            :to-equal '((:character #\a nil)
                        (:character #\b nil)
                        (:character #\c nil))))
  (it "decodes a general vector of octets in streaming mode"
    (let ((decoder (make-input-decoder)))
      (expect (%event-signatures-of (decode-input-chunk decoder #(97 98 99) :eof t))
              :to-equal '((:character #\a nil)
                          (:character #\b nil)
                          (:character #\c nil))))))

(describe "unsupported-code-point condition"
  (it "stores the code point and reports it in the condition message"
    (let ((condition (make-condition 'unsupported-code-point :code-point #x110000)))
      (expect (unsupported-code-point-code-point condition) :to-be #x110000)
      (expect (search "Unsupported Unicode code point 1114112" (format nil "~A" condition))
              :to-be-truthy))))

(describe "invalid UTF-8 sequence detection in decode-input"
  (it "invalid continuation bytes report the failing position"
    (%expect-invalid-utf8 (decode-input #(227 40 130)) 1 :invalid-continuation-byte)))

(describe "input-decoder handling of empty chunks and constructor validation"
  (it "returns no events for empty string/vector chunks and an empty flush"
    (let ((decoder (make-input-decoder)))
      (expect (decode-input-chunk decoder "") :to-be-falsy)
      (expect (decode-input-chunk decoder #()) :to-be-falsy)
      (expect (flush-input-decoder decoder) :to-be-falsy)))
  (it "preserves pending escape storage across non-final empty chunks" (let ((decoder (make-input-decoder))) (expect (decode-input-chunk decoder (string #\Esc)) :to-be-falsy) (let ((pending (cl-tty-kit::input-decoder-pending-string decoder))) (expect (decode-input-chunk decoder "") :to-be-falsy) (expect (cl-tty-kit::input-decoder-pending-string decoder) :to-be pending) (expect (decode-input-chunk decoder #()) :to-be-falsy) (expect (cl-tty-kit::input-decoder-pending-string decoder) :to-be pending) (expect (%event-signatures-of (decode-input-chunk decoder "[A" :eof t)) :to-equal '((:special :up nil))))))
  (it "rejects a negative :max-pending"
    (expect (lambda () (make-input-decoder :max-pending -1)) :to-throw 'error))
  (it "rejects a fractional :max-pending"
    (expect (lambda () (make-input-decoder :max-pending 1.5)) :to-throw 'error)))

(describe "stream input poller"
  (it "drains available characters and preserves split escape sequences"
    (let* ((stream (make-string-input-stream (concatenate 'string
                                                           (string #\Esc)
                                                           "[A")))
           (poll (make-stream-input-poller stream :limit 2)))
      (expect (funcall poll nil 0.1) :to-be-falsy)
      (expect (%event-signatures-of (funcall poll nil 0.1))
              :to-equal '((:special :up nil)))))
  (it "rejects a non-input stream, an invalid decoder, and an invalid limit"
    (expect (lambda () (make-stream-input-poller (make-string-output-stream)))
            :to-throw 'error)
    (expect (lambda () (make-stream-input-poller (make-string-input-stream "x")
                                                  :decoder :not-a-decoder))
            :to-throw 'error)
    (expect (lambda () (make-stream-input-poller (make-string-input-stream "x")
                                                  :limit 0))
            :to-throw 'error)))

(describe "input decoder buffer overflow (:max-pending)"
  (it "reports the exceeded limit and size when a bracketed-paste payload overflows a small buffer"
    (let ((decoder (make-input-decoder :collect-bracketed-paste t :max-pending 8)))
      (decode-input-chunk decoder (%esc "[200~"))
      (expect (lambda () (decode-input-chunk decoder "0123456789"))
              :to-throw (lambda (condition)
                          (and (typep condition 'cl-tty-kit::input-buffer-exceeded)
                               (= 8 (cl-tty-kit::input-buffer-exceeded-limit condition))
                               (= 10 (cl-tty-kit::input-buffer-exceeded-size condition))
                               (string= "Input decoder buffer of 10 units exceeds the 8 unit limit."
                                        (format nil "~A" condition)))))))
  (it "reports the exceeded limit and size for a paste already holding two bytes (max-pending 4)"
    (let ((decoder (make-input-decoder :collect-bracketed-paste t :max-pending 4)))
      (decode-input-chunk decoder (%esc "[200~ab"))
      (expect (lambda () (decode-input-chunk decoder (%esc "[2")))
              :to-throw (lambda (condition)
                          (and (typep condition 'cl-tty-kit::input-buffer-exceeded)
                               (= 4 (cl-tty-kit::input-buffer-exceeded-limit condition))
                               (= 5 (cl-tty-kit::input-buffer-exceeded-size condition)))))))
  (it "overflows on split UTF-8 octets accumulating past max-pending 2"
    (let ((decoder (make-input-decoder :max-pending 2)))
      (expect (decode-input-chunk decoder #(227 129)) :to-be-falsy)
      (expect (lambda () (decode-input-chunk decoder #(130)))
              :to-throw (lambda (condition)
                          (and (typep condition 'cl-tty-kit::input-buffer-exceeded)
                               (= 2 (cl-tty-kit::input-buffer-exceeded-limit condition))
                               (= 3 (cl-tty-kit::input-buffer-exceeded-size condition)))))))
  (it "overflows on a pending ESC[ prefix accumulating past max-pending 4"
    (let ((decoder (make-input-decoder :max-pending 4)))
      (expect (decode-input-chunk decoder (%esc "[")) :to-be-falsy)
      (expect (lambda () (decode-input-chunk decoder "123"))
              :to-throw (lambda (condition)
                          (and (typep condition 'cl-tty-kit::input-buffer-exceeded)
                               (= 4 (cl-tty-kit::input-buffer-exceeded-limit condition))
                               (= 5 (cl-tty-kit::input-buffer-exceeded-size condition))))))))

(describe "bracketed paste payload accumulation across chunks"
  (it "aggregates a payload split across many small chunks into a single paste event"
    (let ((decoder (make-input-decoder :collect-bracketed-paste t))
          (payload (make-string 128 :initial-element #\x)))
      (decode-input-chunk decoder (%esc "[200~"))
      (loop repeat 32
            do (decode-input-chunk decoder "xxxx"))
      (expect (%event-signatures-of (decode-input-chunk decoder (%esc "[201~") :eof t))
              :to-equal `((:paste ,payload nil))))))

(describe "bracketed paste line-ending normalization"
  (it "NORMALIZE-PASTE-LINE-ENDINGS converts CRLF and lone CR to LF"
    (let ((decoder
          (make-input-decoder :collect-bracketed-paste t :normalize-paste-line-endings t)))
      (expect
        (%event-signatures-of
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
            t))
        :to-equal
        `((:paste ,(format nil "line1~%line2~%line3") nil)))))
  (it "reuses the copied payload for LF-only paste normalization"
    (let ((payload (format nil "line1~%line2")))
      (expect (cl-tty-kit::%normalize-paste-line-endings payload) :to-be payload)))
  (it "preserves CR verbatim without NORMALIZE-PASTE-LINE-ENDINGS"
    (let ((decoder (make-input-decoder :collect-bracketed-paste t)))
      (expect
        (%event-signatures-of
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
            t))
        :to-equal
        `((:paste ,(concatenate 'string "a" (string #\Return) (string #\Newline) "b") nil))))))

(describe "large CSI parameter digit runs stay within a generous max-pending budget"
  (it "accepts a 1025-digit CSI parameter run and leaves nothing pending after flush"
    (let* ((decoder (make-input-decoder :max-pending 2048))
           (input (%esc "[" (make-string 1025 :initial-element #\1))))
      (expect (decode-input-chunk decoder input) :to-be-truthy)
      (expect (flush-input-decoder decoder) :to-be-falsy))))

(describe "UTF-8 octets split across chunks"
  (it "decodes a plain-character string chunk normally while UTF-8 octets remain pending, then recovers the buffered character once completed"
    (let ((decoder (make-input-decoder)))
      (expect (decode-input-chunk decoder #(227 129)) :to-be-falsy)
      ;; A string chunk fed while UTF-8 octets are still pending should decode
      ;; normally, leaving the incomplete octets buffered.
      (expect (%event-signatures-of (decode-input-chunk decoder "x"))
              :to-equal '((:character #\x nil)))
      ;; A non-final string chunk must leave the incomplete octet tail intact.
      (expect (length (cl-tty-kit::input-decoder-pending-octets decoder)) :to-be 2)
      ;; Completing the pending octets afterward should recover the buffered
      ;; character.
      (expect (%event-signatures-of (decode-input-chunk decoder #(130) :eof t))
              :to-equal `((:character ,(code-char #x3042) nil)))))
  (it "forces a final string chunk's pending octets through the truncated-sequence fallback"
    (let ((decoder (make-input-decoder)))
      (expect (decode-input-chunk decoder #(227 129)) :to-be-falsy)
      (%expect-invalid-utf8 (decode-input-chunk decoder "x" :eof t) 0 :truncated-sequence)))
  (it "preserves pending UTF-8 storage across a non-final empty specialized octet chunk" (let ((decoder (make-input-decoder)) (empty-chunk (make-array 0 :element-type '(unsigned-byte 8)))) (expect (decode-input-chunk decoder #(227 129)) :to-be-falsy) (let ((pending (cl-tty-kit::input-decoder-pending-octets decoder))) (expect (decode-input-chunk decoder empty-chunk) :to-be-falsy) (expect (cl-tty-kit::input-decoder-pending-octets decoder) :to-be pending) (expect (%event-signatures-of (decode-input-chunk decoder #(130) :eof t)) :to-equal `((:character ,(code-char #x3042) nil))))))
  (it "keeps EOF semantics for an empty specialized octet chunk after partial UTF-8" (let ((decoder (make-input-decoder)) (empty-chunk (make-array 0 :element-type '(unsigned-byte 8)))) (expect (decode-input-chunk decoder #(227 129)) :to-be-falsy) (%expect-invalid-utf8 (decode-input-chunk decoder empty-chunk :eof t) 0 :truncated-sequence) (expect (length (cl-tty-kit::input-decoder-pending-octets decoder)) :to-be 0)))
  (it "preserves split UTF-8 streaming behavior for specialized (unsigned-byte 8) octet chunks"
    (let ((decoder (make-input-decoder))
          (first-chunk
          (make-array 2 :element-type '(unsigned-byte 8) :initial-contents '(227 129)))
          (second-chunk
          (make-array 2 :element-type '(unsigned-byte 8) :initial-contents '(130 120))))
      (expect (decode-input-chunk decoder first-chunk) :to-be-falsy)
      (expect (%event-signatures-of (decode-input-chunk decoder second-chunk :eof t))
              :to-equal `((:character ,(code-char #x3042) nil) (:character #\x nil))))))

(describe "decode-input-chunk streaming across chunk boundaries"
  (dolist (case +streaming-input-cases+)
    (destructuring-bind (chunks expected message &key collect-bracketed-paste) case
      (it message
        (multiple-value-bind (events)
            (%decode-input-chunks chunks :collect-bracketed-paste collect-bracketed-paste)
          (expect (%event-signatures-of events) :to-equal expected))))))

(describe "flush-input-decoder and error propagation"
  (it "flushing a pending escape emits an escape event"
    (multiple-value-bind (events decoder) (%decode-input-chunks (list (string #\Esc)))
      (expect (%event-signatures-of (nconc events (flush-input-decoder decoder)))
              :to-equal '((:special :escape nil)))))
  (it "a chunk completing a pending CSI prefix at EOF matches decoding the whole sequence at once"
    (let ((decoder (make-input-decoder)))
      (expect (decode-input-chunk decoder (%esc "[")) :to-be-falsy)
      (let ((events (decode-input-chunk decoder "x" :eof t)))
        (expect (%event-signatures-of events)
                :to-equal (%event-signatures-of (decode-input (%esc "[x")))))))
  (it "flushing a partial UTF-8 sequence signals truncation"
    (let ((decoder (make-input-decoder)))
      (expect (decode-input-chunk decoder #(227 129)) :to-be-falsy)
      (%expect-invalid-utf8 (flush-input-decoder decoder) 0 :truncated-sequence)))
  (it "invalid leading bytes fail immediately"
    (%expect-invalid-utf8 (decode-input #(255 97)) 0 :invalid-leading-byte))
  (it "decode-input signals an error for a vector mixing characters and integers"
    (expect (lambda () (decode-input #(#\a 1))) :to-throw 'error))
  (it "decode-input signals an error for a non-sequence argument"
    (expect (lambda () (decode-input 42)) :to-throw 'error))
  (it "decode-input-chunk signals an error for a vector mixing characters and integers"
    (let ((decoder (make-input-decoder)))
      (expect (lambda () (decode-input-chunk decoder #(#\a 1))) :to-throw 'error)))
  (it "decode-input-chunk signals an error for a non-sequence argument"
    (let ((decoder (make-input-decoder)))
      (expect (lambda () (decode-input-chunk decoder 42)) :to-throw 'error)))
  (it "flushing an unterminated paste falls back to ordinary decoding"
    (multiple-value-bind (events decoder)
        (%decode-input-chunks (list (%esc "[200~ab")) :collect-bracketed-paste t)
      (expect (%event-signatures-of (nconc events (flush-input-decoder decoder)))
              :to-equal `((:special :paste-start nil) (:character ,#\a nil) (:character ,#\b nil)))))
  (it "flushing an unterminated paste retains preceding event order"
    (multiple-value-bind (events decoder)
        (%decode-input-chunks (list (concatenate 'string "x" (%esc "[200~ab")))
                              :collect-bracketed-paste t)
      (expect (%event-signatures-of (nconc events (flush-input-decoder decoder)))
              :to-equal `((:character ,#\x nil)
                          (:special :paste-start nil)
                          (:character ,#\a nil)
                          (:character ,#\b nil)))))
  (it "incremental paste terminator detection preserves following input"
    (multiple-value-bind (events)
        (%decode-input-chunks
          (list (%esc "[200~abc" (string #\Esc) "[2") "0" "1" "~z")
          :collect-bracketed-paste t)
      (expect (%event-signatures-of events)
              :to-equal `((:paste "abc" nil) (:character ,#\z nil)))))
  (it "EOF during a partial paste terminator falls back to ordinary decoding"
    (let* ((input (%esc "[200~abc" (string #\Esc) "[2"))
           (decoder (make-input-decoder :collect-bracketed-paste t)))
      (expect (%event-signatures-of (decode-input-chunk decoder input :eof t))
              :to-equal (%event-signatures-of (decode-input input))))))

(describe "streaming decode equivalence to single-chunk decode"
  (dolist (case +streaming-equivalence-cases+)
    (destructuring-bind (input options) case
      (loop for split from 1 below (length input)
            do (let ((splits (list split (- (length input) split))))
                 (it (format nil "matches one-shot decode for ~S with splits ~S" input splits)
                   (let ((expected (apply #'%decode-input-single-chunk-signatures input options))
                         (actual (apply #'%decode-input-streaming-signatures input splits options)))
                     (expect actual :to-equal expected)))))))
  (let ((input (%esc "[200~hello" (string #\Esc) "[201~x"))
        (splits '(1 1 2 3 4 2 2 1 1 1)))
    (it (format nil "matches one-shot decode for ~S with fixed splits ~S" input splits)
      (let ((expected (%decode-input-single-chunk-signatures input :collect-bracketed-paste t))
            (actual (%decode-input-streaming-signatures input splits :collect-bracketed-paste t)))
        (expect actual :to-equal expected)))))

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

(describe "documented example scripts produce stable event traces"
  (dolist (case +input-example-cases+)
    (destructuring-bind (example-file expected message) case
      (it message
        (let* ((example (symbol-function (load-example-symbol example-file)))
               (events (funcall example)))
          (expect (mapcar #'%key-event-signature events) :to-equal expected))))))
