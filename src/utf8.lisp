(in-package #:cl-tty-kit)

;;; UTF-8 decoding delegates to CL-CODEC-KIT; this file is now a translating
;;; adapter, not an implementation. Two things CL-CODEC-KIT does not itself
;;; provide are kept here because this library's own public contract
;;; (INVALID-UTF8-SEQUENCE, tested by t/utf8-test.lisp) predates it and must
;;; not change shape for existing callers:
;;;
;;;   1. %VALIDATE-OCTET-VECTOR rejects a non-(INTEGER 0 255) element with
;;;      :NON-OCTET before decoding -- CL-CODEC-KIT assumes its input already
;;;      satisfies that type and has no such guard of its own.
;;;   2. %TRANSLATE-CODEC-ERROR re-signals a CL-CODEC-KIT decode error as
;;;      INVALID-UTF8-SEQUENCE. Every CL-CODEC-KIT:DECODE-ERROR's POSITION
;;;      names where the failing character *starts* (see
;;;      cl-codec-kit/src/conditions.lisp), which already matches this
;;;      library's own POSITION for every reason except
;;;      :INVALID-CONTINUATION-BYTE -- INVALID-UTF8-SEQUENCE has always
;;;      pinned that one case to the specific offending byte's own index
;;;      instead, so %CONTINUATION-BYTE-OFFSET re-derives it.

(defun %validate-octet-vector (octets)
  (loop for i from 0 below (length octets)
        for element = (aref octets i)
        unless (typep element '(integer 0 255))
          do (%signal-invalid-utf8-sequence i element :non-octet)))

(defun %continuation-byte-offset (octets sequence-start)
  "Return the index of the first byte after SEQUENCE-START that is not a
valid UTF-8 continuation byte (80-BF)."
  (loop for i from (1+ sequence-start) below (length octets)
        unless (<= #x80 (aref octets i) #xBF)
          return i
        finally (return (length octets))))

(defun %translate-codec-error (condition octets)
  (let ((position (cl-codec-kit:decode-error-position condition)))
    (etypecase condition
      (cl-codec-kit:invalid-continuation-byte
       (let ((offset (%continuation-byte-offset octets position)))
         (%signal-invalid-utf8-sequence offset (aref octets offset) :invalid-continuation-byte)))
      (cl-codec-kit:invalid-leading-byte
       (%signal-invalid-utf8-sequence position (aref octets position) :invalid-leading-byte))
      (cl-codec-kit:overlong-sequence
       (%signal-invalid-utf8-sequence position (aref octets position) :overlong-sequence))
      (cl-codec-kit:surrogate-code-point
       (%signal-invalid-utf8-sequence position (aref octets position) :surrogate-half))
      (cl-codec-kit:code-point-too-large
       (%signal-invalid-utf8-sequence position (aref octets position) :code-point-too-large))
      (cl-codec-kit:truncated-sequence
       (%signal-invalid-utf8-sequence position (aref octets position) :truncated-sequence)))))

(defun %utf8-octets-to-string (octets)
  (%validate-octet-vector octets)
  (handler-case (cl-codec-kit:octets-to-string octets :encoding :utf-8)
    (cl-codec-kit:decode-error (c) (%translate-codec-error c octets))))

(defun %utf8-decode-prefix (octets)
  "Decode the complete UTF-8 prefix of octet VECTOR.
Return two values: the decoded string and a fresh octet vector holding any
incomplete trailing multibyte sequence (empty when VECTOR ends on a
boundary). Genuinely invalid octets in the prefix still signal
INVALID-UTF8-SEQUENCE."
  (%validate-octet-vector octets)
  (handler-case (cl-codec-kit:decode-prefix octets :encoding :utf-8)
    (cl-codec-kit:decode-error (c) (%translate-codec-error c octets))))

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
