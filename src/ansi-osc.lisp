(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; OSC (Operating System Command) escape sequences
;;;
;;; Unlike the CSI sequences in ansi.lisp, these are framed `ESC ] ... ST' (or
;;; the BEL-terminated legacy form) and carry a string payload, so they need
;;; their own sanitization (control-byte stripping, base64) before framing.
;;; --------------------------------------------------------------------------
(defun %terminal-control-character-p (character)
  (let ((code (char-code character)))
    (or (< code #x20) (= code #x7F) (<= #x80 code #x9F))))

(defmacro %sanitize-osc-string (value)
  "Return VALUE as a string without control bytes that can break out of OSC."
  `(remove-if #'%terminal-control-character-p (princ-to-string ,value)))

(defun %osc-52-target-character-p (character)
  (let ((code (char-code character)))
    (or
      (<= (char-code #\0) code (char-code #\9))
      (<= (char-code #\A) code (char-code #\Z))
      (<= (char-code #\a) code (char-code #\z)))))

(defmacro %validate-osc-52-target (target)
  `(let ((target ,target))
    (let ((string (princ-to-string target)))
      (unless (and (plusp (length string)) (every #'%osc-52-target-character-p string))
        (error
          "OSC 52 clipboard target must be non-empty alphanumeric ASCII: ~S."
          target))
      string)))

(defun ansi-hyperlink (uri text)
  "Return TEXT wrapped in an OSC 8 hyperlink pointing at URI.
Terminals that support OSC 8 render TEXT as a clickable link; those that do not
show TEXT unchanged. The link is opened and closed with `ESC ] 8 ; ; ... ST'
using the ST (`ESC \\') terminator."
  (format
    nil
    "~C]8;;~A~C\\~A~C]8;;~C\\"
    +escape+
    (%sanitize-osc-string uri)
    +escape+
    (%sanitize-osc-string text)
    +escape+
    +escape+))

(defparameter +base64-alphabet+ "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(defun %write-base64-octets (octets out &key (start 0) (end (length octets)))
  "Write OCTETS from START (inclusive) to END (exclusive) as Base64 to OUT.
START and END must delimit a valid range within OCTETS."
  (declare (type vector octets)
           (optimize (speed 3) (safety 1)))
  (%assert (and (integerp start)
                (integerp end)
                (<= 0 start end (length octets)))
           "START and END must delimit a valid range in OCTETS, got ~S and ~S for length ~D."
           start
           end
           (length octets))
  (let* ((alphabet +base64-alphabet+)
         (complete-end (- end (mod (- end start) 3))))
    (declare (type simple-string alphabet)
             (type fixnum start end complete-end))
    (loop for index fixnum from start below complete-end by 3
          do (let ((packed (logior (ash (the (unsigned-byte 8) (aref octets index)) 16)
                                   (ash (the (unsigned-byte 8) (aref octets (1+ index))) 8)
                                   (the (unsigned-byte 8) (aref octets (+ index 2))))))
               (declare (type (unsigned-byte 24) packed))
               (write-char (schar alphabet (ldb (byte 6 18) packed)) out)
               (write-char (schar alphabet (ldb (byte 6 12) packed)) out)
               (write-char (schar alphabet (ldb (byte 6 6) packed)) out)
               (write-char (schar alphabet (ldb (byte 6 0) packed)) out)))
    (let ((remaining (- end complete-end)))
      (declare (type (integer 0 2) remaining))
      (unless (zerop remaining)
        (let* ((b0 (the (unsigned-byte 8) (aref octets complete-end)))
               (b1 (if (= remaining 2)
                       (the (unsigned-byte 8) (aref octets (1+ complete-end)))
                       0))
               (packed (logior (ash b0 16) (ash b1 8))))
          (declare (type (unsigned-byte 8) b0 b1)
                   (type (unsigned-byte 24) packed))
          (write-char (schar alphabet (ldb (byte 6 18) packed)) out)
          (write-char (schar alphabet (ldb (byte 6 12) packed)) out)
          (if (= remaining 2)
              (write-char (schar alphabet (ldb (byte 6 6) packed)) out)
              (write-char #\= out))
          (write-char #\= out))))))

(defun %base64-encode-octets (octets)
  "Return the standard base64 encoding of the octet vector OCTETS."
  (with-output-to-string (out)
    (let ((length (length octets)))
      (loop for index from 0 below length by 3
            do (let* ((b0 (aref octets index))
                      (b1 (if (< (+ index 1) length) (aref octets (+ index 1)) 0))
                      (b2 (if (< (+ index 2) length) (aref octets (+ index 2)) 0))
                      (packed (logior (ash b0 16) (ash b1 8) b2)))
                 (write-char (char +base64-alphabet+ (ldb (byte 6 18) packed)) out)
                 (write-char (char +base64-alphabet+ (ldb (byte 6 12) packed)) out)
                 (write-char (if (< (+ index 1) length)
                                 (char +base64-alphabet+ (ldb (byte 6 6) packed))
                                 #\=)
                             out)
                 (write-char (if (< (+ index 2) length)
                                 (char +base64-alphabet+ (ldb (byte 6 0) packed))
                                 #\=)
                             out))))))



(defun ansi-set-clipboard (text &key (target "c"))
  "Return an OSC 52 sequence that sets the terminal clipboard TARGET to TEXT.
TARGET selects the buffer (\"c\" clipboard, \"p\" primary); TEXT is encoded as
UTF-8 and base64 per the protocol. Requires terminal OSC 52 support."
  (let ((target (%validate-osc-52-target target)))
    (let ((octets (sb-ext:string-to-octets text :external-format :utf-8)))
      (with-output-to-string (out)
        (write-char +escape+ out)
        (write-string "]52;" out)
        (write-string target out)
        (write-char #\; out)
        (%write-base64-octets octets out)
        (write-char +escape+ out)
        (write-char #\\ out)))))
(defmacro %rgb-hex-pair (value)
  `(format nil "~2,'0X" ,value))

(defmacro %validate-ansi-byte (name value)
  `(let ((name ,name)
        (value ,value))
    (unless (typep value '(integer 0 255))
      (error "~A must be an integer in [0, 255]: ~S." name value))
    value))

(defun ansi-set-palette-color (index red green blue)
  "Return an OSC 4 sequence redefining palette entry INDEX to RGB RED GREEN BLUE.
Each channel is 0-255. Requires terminal OSC 4 support (query CANCHANGECOLOR)."
  (format
    nil
    "~C]4;~D;rgb:~A/~A/~A~C\\"
    +escape+
    (%validate-ansi-byte "Palette index" index)
    (%rgb-hex-pair (%validate-ansi-byte "Red channel" red))
    (%rgb-hex-pair (%validate-ansi-byte "Green channel" green))
    (%rgb-hex-pair (%validate-ansi-byte "Blue channel" blue))
    +escape+))

(defun ansi-reset-palette (&optional index)
  "Return an OSC 104 sequence resetting palette entry INDEX, or the whole palette
when INDEX is NIL, to the terminal defaults."
  (if index (format
      nil
      "~C]104;~D~C\\"
      +escape+
      (%validate-ansi-byte "Palette index" index)
      +escape+)
    (format nil "~C]104~C\\" +escape+ +escape+)))

(defmacro %define-osc-color-query (name osc-number docstring)
  "Define an OSC query function NAME that asks the terminal for a default color
via OSC-NUMBER (10 for foreground, 11 for background), matching the shape of
ANSI-REQUEST-FOREGROUND-COLOR and ANSI-REQUEST-BACKGROUND-COLOR, which differ
only in which OSC number they query."
  `(defun ,name ()
    ,docstring
    (format nil "~C]~D;?~C\\" +escape+ ,osc-number +escape+)))

(%define-osc-color-query
  ansi-request-foreground-color
  10
  "Return the OSC 10 query asking the terminal for its default foreground color.
The reply (`ESC]10;rgb:RRRR/GGGG/BBBB ST') is parsed by DECODE-COLOR-REPORT.")

(%define-osc-color-query
  ansi-request-background-color
  11
  "Return the OSC 11 query asking the terminal for its default background color.
The reply is parsed by DECODE-COLOR-REPORT.")

(defun ansi-set-window-title (title)
  "Return the OSC sequence that sets the terminal window TITLE.
The payload is emitted as `ESC ] 0 ; TITLE BEL', the widely supported form."
  (format nil "~C]0;~A~C" +escape+ (%sanitize-osc-string title) (code-char 7)))
