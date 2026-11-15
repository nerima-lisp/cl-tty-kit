(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Terminal capability requests and their reply decoders
;;;
;;; XTVERSION, DECRQM/DECRPM, and the kitty keyboard-flags query. Decoders
;;; follow keys-decode.lisp: string or octet input, &KEY START, values ending
;;; in CONSUMED, and all-NIL plus 0 for anything that is not a complete report.
;;; --------------------------------------------------------------------------
(defun ansi-request-terminal-version ()
  "Return the XTVERSION query `ESC [ > 0 q'. The terminal replies with
`ESC P > | NAME(VERSION) ST', which DECODE-TERMINAL-VERSION parses."
  (format nil "~C[>0q" +escape+))

(defun ansi-request-mode (mode &key (private t))
  "Return the DECRQM query for MODE: `ESC [ ? MODE $ p' for a private (DEC)
mode, or `ESC [ MODE $ p' when PRIVATE is NIL. MODE is a non-negative integer.
The terminal replies with a DECRPM report that DECODE-MODE-REPORT parses."
  (format nil "~C[~:[~;?~]~D$p" +escape+ private (%validate-csi-numeric-parameter mode)))

(defun ansi-request-keyboard-enhancements ()
  "Return the kitty keyboard protocol query `ESC [ ? u'. A supporting terminal
replies with `ESC [ ? FLAGS u', which DECODE-KEYBOARD-ENHANCEMENTS-REPORT parses."
  (format nil "~C[?u" +escape+))

(defun %digit-run-end (string start limit)
  (or (position-if-not #'digit-char-p string :start start :end limit) limit))

(defun %report-start-p (string start limit prefix)
  "True when STRING holds ESC and PREFIX at START with at least one character
after them, so callers may read index (+ START 1 (LENGTH PREFIX)) unchecked."
  (and (integerp start)
       (<= 0 start)
       (< (+ start 1 (length prefix)) limit)
       (char= (char string start) +escape+)
       (string= prefix string :start2 (1+ start) :end2 (+ start 1 (length prefix)))))

(defun decode-terminal-version (input &key (start 0))
  "Decode an XTVERSION reply `ESC P > | TEXT ESC \\\\' from INPUT at START.
Returns (VALUES TEXT CONSUMED), or (VALUES NIL 0) when INPUT at START is not a
complete reply. Only the ESC backslash terminator is accepted (the reply is a
DCS string), and a TEXT containing control characters is rejected. Pairs with
ANSI-REQUEST-TERMINAL-VERSION."
  (let* ((string (%input->string input))
         (limit (length string)))
    (block nil
      (unless (%report-start-p string start limit "P>|")
        (return (values nil 0)))
      (let* ((text-start (+ start 4))
             (text-end (position-if #'%terminal-control-character-p string
                                    :start text-start :end limit)))
        (if (and text-end
                 (char= (char string text-end) +escape+)
                 (< (1+ text-end) limit)
                 (char= (char string (1+ text-end)) #\\))
            (values (subseq string text-start text-end) (- (+ text-end 2) start))
            (values nil 0))))))

(defparameter +mode-report-states+
  #(:not-recognized :set :reset :permanently-set :permanently-reset))

(defun decode-mode-report (input &key (start 0))
  "Decode a DECRPM report `ESC [ ? MODE ; STATE $ y' (private mode) or
`ESC [ MODE ; STATE $ y' (ANSI mode) from INPUT at START. Returns (VALUES MODE
STATE PRIVATE-P CONSUMED), where STATE is :NOT-RECOGNIZED (0), :SET (1),
:RESET (2), :PERMANENTLY-SET (3), or :PERMANENTLY-RESET (4). Returns (VALUES NIL
NIL NIL 0) when INPUT at START is not a complete report, including an unknown
STATE value. Pairs with ANSI-REQUEST-MODE."
  (let* ((string (%input->string input))
         (limit (length string)))
    (block nil
      (unless (%report-start-p string start limit "[")
        (return (values nil nil nil 0)))
      (let* ((private-p (char= (char string (+ start 2)) #\?))
             (mode-start (if private-p (+ start 3) (+ start 2)))
             (mode-end (%digit-run-end string mode-start limit))
             (state-start (1+ mode-end))
             (state-end (%digit-run-end string (min state-start limit) limit))
             (final (1+ state-end)))
        (unless (and (< final limit)
                     (char= (char string mode-end) #\;)
                     (char= (char string state-end) #\$)
                     (char= (char string final) #\y))
          (return (values nil nil nil 0)))
        (let ((mode (%parse-mouse-uint string mode-start mode-end))
              (state (%parse-mouse-uint string state-start state-end)))
          (if (and mode state (< state (length +mode-report-states+)))
              (values mode (aref +mode-report-states+ state) private-p (- (1+ final) start))
              (values nil nil nil 0)))))))

(defun decode-keyboard-enhancements-report (input &key (start 0))
  "Decode the kitty keyboard protocol flags report `ESC [ ? FLAGS u' from INPUT
at START. Returns (VALUES FLAGS CONSUMED), or (VALUES NIL 0) when INPUT at START
is not a complete report. Pairs with ANSI-REQUEST-KEYBOARD-ENHANCEMENTS."
  (let* ((string (%input->string input))
         (limit (length string)))
    (block nil
      (unless (%report-start-p string start limit "[?")
        (return (values nil 0)))
      (let* ((flags-start (+ start 3))
             (flags-end (%digit-run-end string flags-start limit))
             (flags (%parse-mouse-uint string flags-start flags-end)))
        (if (and flags (< flags-end limit) (char= (char string flags-end) #\u))
            (values flags (- (1+ flags-end) start))
            (values nil 0))))))
