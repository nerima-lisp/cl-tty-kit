(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Public input decoding entry points
;;;
;;; DECODE-INPUT is the one-shot decoder. MAKE-INPUT-DECODER, DECODE-INPUT-CHUNK,
;;; and FLUSH-INPUT-DECODER add incremental decoding that buffers partial UTF-8
;;; sequences (as octets) and partial escape/paste fragments (as a string) across
;;; read boundaries, so split reads never emit spurious ESC or invalid-UTF-8
;;; errors until the caller flushes.
;;; --------------------------------------------------------------------------

(defun decode-input (input)
  "Decode INPUT, a string or octet vector, into a list of KEY-EVENT objects.
Bracketed paste markers stay visible as :PASTE-START and :PASTE-END events.
Malformed UTF-8 signals INVALID-UTF8-SEQUENCE."
  (values (%collect-plain-events (%input->string input) t)))

(defun make-input-decoder (&key collect-bracketed-paste normalize-paste-line-endings
                                (max-pending 4194304))
  "Create an incremental INPUT-DECODER.
When COLLECT-BRACKETED-PASTE is true, completed paste blocks are emitted as a
single :PASTE event instead of surfacing the surrounding marker events.
When NORMALIZE-PASTE-LINE-ENDINGS is also true, that :PASTE event's text has
CRLF and lone CR line endings converted to LF -- some terminals send CR-
terminated lines inside a bracketed paste, and callers that insert paste text
into an LF-delimited buffer usually want it pre-normalized rather than
re-implementing that scan themselves.
MAX-PENDING bounds the still-undecoded tail (partial UTF-8, a held escape, or an
open paste payload) the decoder will buffer across chunks, which keeps an
unterminated sequence from an untrusted source from exhausting memory; exceeding
it signals a TTY-KIT-ERROR."
  (unless (and (integerp max-pending) (not (minusp max-pending)))
    (error "MAX-PENDING must be a non-negative integer: ~S." max-pending))
  (%make-input-decoder :collect-bracketed-paste-p collect-bracketed-paste
                       :normalize-paste-line-endings-p normalize-paste-line-endings
                       :max-pending max-pending))

(defun %check-decoder-buffer (decoder)
  "Signal when DECODER's buffered, undecoded tail exceeds its MAX-PENDING bound."
  (with-input-decoder-state (decoder)
    (%assert-decoder-buffer-size
     decoder
     (+ (length pending-string)
        (length pending-octets)
        (if (stringp pending-paste) (length pending-paste) 0))))
  decoder)

(defun %decoder-collect-events (decoder string eof)
  "Run the decoder's string-level collector, returning (VALUES EVENTS PENDING)."
  (if (input-decoder-collect-bracketed-paste-p decoder)
      (%decode-string-events-with-paste decoder string :eof eof)
      (%collect-plain-events string eof)))

(defun %decoder-decode-octets (decoder octets eof)
  "Decode OCTETS for DECODER, buffering an incomplete trailing sequence.
Returns the decoded string. When EOF is true a truncated tail is not held and
its decode signals INVALID-UTF8-SEQUENCE instead."
  (let ((combined
          (if (plusp (length (input-decoder-pending-octets decoder)))
              (let ((size (+ (length (input-decoder-pending-octets decoder))
                             (length octets))))
                (%assert-decoder-buffer-size decoder size)
                (concatenate '(vector (unsigned-byte 8))
                             (input-decoder-pending-octets decoder)
                             octets))
              (coerce octets '(vector (unsigned-byte 8))))))
    (if eof
        (progn
          (setf (input-decoder-pending-octets decoder) #())
          (%utf8-octets-to-string combined))
        (multiple-value-bind (string leftover) (%utf8-decode-prefix combined)
          (setf (input-decoder-pending-octets decoder) leftover)
          string))))

(defun %decoder-decode-chunk-string (decoder input eof)
  "Reduce a raw INPUT chunk to a decoded string, updating octet buffering."
  (cond
    ((stringp input)
     (if (plusp (length (input-decoder-pending-octets decoder)))
         (concatenate 'string
                      (%decoder-decode-octets decoder #() eof)
                      input)
         input))
    ((%octet-input-p input)
     (%decoder-decode-octets decoder input eof))
    (t
     (%coerce-character-vector input))))

(defun decode-input-chunk (decoder input &key eof)
  "Feed INPUT (a string or octet vector) into DECODER, returning its events.
Trailing partial UTF-8 code units and incomplete escape or paste sequences are
buffered until a later chunk completes them or the caller flushes. EOF signals
that INPUT is the final chunk, forcing any buffered tail through the fallback
rules."
  (with-input-decoder-state (decoder)
    (let* ((decoded (%decoder-decode-chunk-string decoder input eof))
           (full (if (plusp (length pending-string))
                     (progn
                       (%assert-decoder-buffer-size
                        decoder
                        (+ (length pending-string) (length decoded)))
                       (concatenate 'string pending-string decoded))
                     decoded)))
      (setf pending-string "")
      (multiple-value-bind (events pending)
          (%decoder-collect-events decoder full eof)
        (setf pending-string (or pending ""))
        (%check-decoder-buffer decoder)
        events))))

(defun flush-input-decoder (decoder)
  "Force DECODER's buffered tail through the one-shot fallback rules.
A buffered partial UTF-8 sequence signals INVALID-UTF8-SEQUENCE with reason
:TRUNCATED-SEQUENCE; a buffered escape or paste fragment is decoded as if EOF
had been reached. Returns the flushed events and leaves DECODER empty."
  (with-input-decoder-state (decoder)
    (when (plusp (length pending-octets))
      (let ((octets pending-octets))
        (setf pending-octets #())
        (%utf8-octets-to-string octets)))
    (let ((string pending-string))
      (setf pending-string "")
      (values (%decoder-collect-events decoder string t)))))
