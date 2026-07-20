(in-package #:cl-tty-kit)

(defconstant +escape+ #\Esc)

(defmacro define-ansi-function (name lambda-list docstring format-string &rest format-args)
  `(defun ,name ,lambda-list
     ,docstring
     (format nil ,format-string +escape+ ,@format-args)))

(define-ansi-function ansi-clear-screen (&optional (mode 2))
    "Return the ANSI sequence that clears the screen."
  "~C[~DJ"
  mode)

(define-ansi-function ansi-clear-line (&optional (mode 2))
    "Return the ANSI sequence that clears a line."
  "~C[~DK"
  mode)

(define-ansi-function ansi-move-cursor (row col)
    "Return the ANSI sequence that moves the cursor to ROW and COL."
  "~C[~D;~DH"
  row
  col)

(define-ansi-function ansi-hide-cursor ()
    "Return the ANSI sequence that hides the cursor."
  "~C[?25l")

(define-ansi-function ansi-show-cursor ()
    "Return the ANSI sequence that shows the cursor."
  "~C[?25h")

(define-ansi-function ansi-enter-alternate-screen ()
    "Return the ANSI sequence that enters the alternate screen buffer."
  "~C[?1049h")

(define-ansi-function ansi-exit-alternate-screen ()
    "Return the ANSI sequence that exits the alternate screen buffer."
  "~C[?1049l")

(define-ansi-function ansi-enable-bracketed-paste ()
    "Return the ANSI sequence that enables bracketed paste mode."
  "~C[?2004h")

(define-ansi-function ansi-disable-bracketed-paste ()
    "Return the ANSI sequence that disables bracketed paste mode."
  "~C[?2004l")

(define-ansi-function ansi-request-device-attributes ()
    "Return the Primary Device Attributes (DA1) query `ESC [ c'.
The terminal replies with `ESC [ ? ... c' listing the features it supports, which
DECODE-DEVICE-ATTRIBUTES parses."
  "~C[c")

(define-ansi-function ansi-request-cursor-position ()
    "Return the DSR sequence that asks the terminal for the cursor position.
The terminal replies with `ESC [ row ; col R', which DECODE-CURSOR-POSITION-REPORT
parses. (That reply is not folded into DECODE-INPUT because it is ambiguous with a
modified F3 key, so decode it explicitly after issuing this request.)"
  "~C[6n")

(define-ansi-function ansi-enable-focus-reporting ()
    "Return the ANSI sequence that enables focus-in/focus-out reporting.
The terminal then emits `ESC [ I' on focus and `ESC [ O' on blur, which
DECODE-INPUT surfaces as :FOCUS-IN and :FOCUS-OUT special key events."
  "~C[?1004h")

(define-ansi-function ansi-disable-focus-reporting ()
    "Return the ANSI sequence that disables focus-in/focus-out reporting."
  "~C[?1004l")

(define-ansi-function ansi-set-keyboard-enhancements (flags &optional (mode 1))
    "Return the CSI u sequence that sets keyboard enhancement FLAGS.

MODE follows the kitty keyboard progressive enhancement protocol:
1 replaces the current flags, 2 sets bits, and 3 resets bits."
  "~C[=~D;~Du"
  flags
  mode)

(define-ansi-function ansi-push-keyboard-enhancements (flags)
    "Return the CSI u sequence that pushes keyboard enhancement FLAGS."
  "~C[>~Du"
  flags)

(define-ansi-function ansi-pop-keyboard-enhancements (&optional (count 1))
    "Return the CSI u sequence that pops COUNT keyboard enhancement scopes."
  "~C[<~Du"
  count)

(define-ansi-function ansi-bold ()
    "Return the ANSI sequence that enables bold text."
  "~C[1m")

(define-ansi-function ansi-dim ()
    "Return the ANSI sequence that enables dim (faint) text."
  "~C[2m")

(define-ansi-function ansi-italic ()
    "Return the ANSI sequence that enables italic text."
  "~C[3m")

(define-ansi-function ansi-underline ()
    "Return the ANSI sequence that enables underlined text."
  "~C[4m")

(define-ansi-function ansi-blink ()
    "Return the ANSI sequence that enables blinking text."
  "~C[5m")

(define-ansi-function ansi-reverse ()
    "Return the ANSI sequence that enables reverse-video text."
  "~C[7m")

(define-ansi-function ansi-hidden ()
    "Return the ANSI sequence that enables hidden (concealed) text."
  "~C[8m")

(define-ansi-function ansi-strikethrough ()
    "Return the ANSI sequence that enables strikethrough text."
  "~C[9m")

(define-ansi-function ansi-default-foreground ()
    "Return the SGR sequence that resets the foreground to the default color."
  "~C[39m")

(define-ansi-function ansi-default-background ()
    "Return the SGR sequence that resets the background to the default color."
  "~C[49m")

(define-ansi-function ansi-reset-style ()
    "Return the ANSI sequence that resets all styles."
  "~C[0m")

(defun ansi-bell (&optional (count 1))
  "Return a string of COUNT BEL (^G) characters that ring the terminal bell."
  (make-string (max 0 count) :initial-element (code-char 7)))

(define-ansi-function ansi-reset-terminal ()
    "Return the RIS sequence that resets the terminal to its initial state."
  "~Cc")

(define-ansi-function ansi-begin-synchronized-update ()
    "Return the sequence that begins a synchronized (atomic) screen update.
Terminals supporting DEC private mode 2026 buffer output until the matching
ANSI-END-SYNCHRONIZED-UPDATE, so a full repaint or a RENDERER-RENDER shows without
tearing."
  "~C[?2026h")

(define-ansi-function ansi-end-synchronized-update ()
    "Return the sequence that ends a synchronized screen update and presents it."
  "~C[?2026l")

(defun ansi-sgr (&rest codes)
  "Return an SGR escape sequence combining CODES into a single `ESC[...m'.
Each element of CODES is an integer or already-formatted string SGR parameter;
they are joined with semicolons in order. With no CODES the result is the bare
`ESC[m' reset. This is the general builder the named emitters like ANSI-BOLD and
ANSI-UNDERLINE specialize."
  (format nil "~C[~{~A~^;~}m" +escape+ codes))

;;; --------------------------------------------------------------------------
;;; Cursor movement and positioning
;;; --------------------------------------------------------------------------

(define-ansi-function ansi-cursor-up (&optional (count 1))
    "Return the ANSI sequence that moves the cursor up COUNT rows (CUU)."
  "~C[~DA"
  count)

(define-ansi-function ansi-cursor-down (&optional (count 1))
    "Return the ANSI sequence that moves the cursor down COUNT rows (CUD)."
  "~C[~DB"
  count)

(define-ansi-function ansi-cursor-forward (&optional (count 1))
    "Return the ANSI sequence that moves the cursor forward COUNT columns (CUF)."
  "~C[~DC"
  count)

(define-ansi-function ansi-cursor-back (&optional (count 1))
    "Return the ANSI sequence that moves the cursor back COUNT columns (CUB)."
  "~C[~DD"
  count)

(define-ansi-function ansi-cursor-column (&optional (column 1))
    "Return the ANSI sequence that moves the cursor to absolute COLUMN (CHA)."
  "~C[~DG"
  column)

(define-ansi-function ansi-cursor-row (&optional (row 1))
    "Return the ANSI sequence that moves the cursor to absolute ROW (VPA)."
  "~C[~Dd"
  row)

(define-ansi-function ansi-save-cursor ()
    "Return the DECSC sequence that saves the cursor position and attributes."
  "~C7")

;;; --------------------------------------------------------------------------
;;; In-place line and character editing (CSI editing functions)
;;; --------------------------------------------------------------------------

(define-ansi-function ansi-insert-line (&optional (count 1))
    "Return the ANSI sequence that inserts COUNT blank lines at the cursor (IL),
pushing lines below down within the scroll region."
  "~C[~DL"
  count)

(define-ansi-function ansi-delete-line (&optional (count 1))
    "Return the ANSI sequence that deletes COUNT lines at the cursor (DL),
pulling lines below up within the scroll region."
  "~C[~DM"
  count)

(define-ansi-function ansi-insert-char (&optional (count 1))
    "Return the ANSI sequence that inserts COUNT blank characters at the cursor
(ICH), shifting the rest of the line right."
  "~C[~D@"
  count)

(define-ansi-function ansi-delete-char (&optional (count 1))
    "Return the ANSI sequence that deletes COUNT characters at the cursor (DCH),
shifting the rest of the line left."
  "~C[~DP"
  count)

(define-ansi-function ansi-erase-char (&optional (count 1))
    "Return the ANSI sequence that erases COUNT characters from the cursor (ECH),
replacing them with blanks without shifting the line."
  "~C[~DX"
  count)

(define-ansi-function ansi-repeat (&optional (count 1))
    "Return the ANSI sequence that repeats the preceding character COUNT times
(REP)."
  "~C[~Db"
  count)

(define-ansi-function ansi-restore-cursor ()
    "Return the DECRC sequence that restores the saved cursor state."
  "~C8")

;;; --------------------------------------------------------------------------
;;; Scrolling and scroll regions
;;; --------------------------------------------------------------------------

(define-ansi-function ansi-scroll-up (&optional (count 1))
    "Return the ANSI sequence that scrolls the display up COUNT lines (SU)."
  "~C[~DS"
  count)

(define-ansi-function ansi-scroll-down (&optional (count 1))
    "Return the ANSI sequence that scrolls the display down COUNT lines (SD)."
  "~C[~DT"
  count)

(define-ansi-function ansi-set-scroll-region (top bottom)
    "Return the DECSTBM sequence that restricts scrolling to rows TOP..BOTTOM.
Rows are 1-based and inclusive; the cursor is homed to the top of the region."
  "~C[~D;~Dr"
  top
  bottom)

(define-ansi-function ansi-reset-scroll-region ()
    "Return the DECSTBM sequence that resets the scroll region to the full
screen."
  "~C[r")

(defun ansi-set-mode (mode &key (private t))
  "Return the sequence that sets terminal MODE (an integer), turning it on.
By default MODE is a DEC private mode -- `ESC [ ? MODE h', e.g. 25 (cursor), 1049
(alternate screen), 2004 (bracketed paste), 1000-1006 (mouse). With PRIVATE NIL
it is an ANSI mode -- `ESC [ MODE h'. This is the general primitive the specific
ANSI-ENABLE-* helpers specialize; use it to toggle a mode this library does not
wrap."
  (format nil "~C[~:[~;?~]~Dh" +escape+ private mode))

(defun ansi-reset-mode (mode &key (private t))
  "Return the sequence that resets terminal MODE (an integer), turning it off.
The reset counterpart of ANSI-SET-MODE: `ESC [ ? MODE l' for a DEC private mode
(the default) or `ESC [ MODE l' when PRIVATE is NIL."
  (format nil "~C[~:[~;?~]~Dl" +escape+ private mode))

;;; --------------------------------------------------------------------------
;;; Window title, cursor shape, and mouse reporting
;;; --------------------------------------------------------------------------

(defun ansi-hyperlink (uri text)
  "Return TEXT wrapped in an OSC 8 hyperlink pointing at URI.
Terminals that support OSC 8 render TEXT as a clickable link; those that do not
show TEXT unchanged. The link is opened and closed with `ESC ] 8 ; ; ... ST'
using the ST (`ESC \\') terminator."
  (format nil "~C]8;;~A~C\\~A~C]8;;~C\\"
          +escape+ uri +escape+ text +escape+ +escape+))

(defparameter +base64-alphabet+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

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
  (format nil "~C]52;~A;~A~C\\"
          +escape+ target
          (%base64-encode-octets
           (sb-ext:string-to-octets text :external-format :utf-8))
          +escape+))

(defun %rgb-hex-pair (value)
  (format nil "~2,'0X" value))

(defun ansi-set-palette-color (index red green blue)
  "Return an OSC 4 sequence redefining palette entry INDEX to RGB RED GREEN BLUE.
Each channel is 0-255. Requires terminal OSC 4 support (query CANCHANGECOLOR)."
  (format nil "~C]4;~D;rgb:~A/~A/~A~C\\"
          +escape+ index
          (%rgb-hex-pair red) (%rgb-hex-pair green) (%rgb-hex-pair blue)
          +escape+))

(defun ansi-reset-palette (&optional index)
  "Return an OSC 104 sequence resetting palette entry INDEX, or the whole palette
when INDEX is NIL, to the terminal defaults."
  (if index
      (format nil "~C]104;~D~C\\" +escape+ index +escape+)
      (format nil "~C]104~C\\" +escape+ +escape+)))

(defun ansi-request-foreground-color ()
  "Return the OSC 10 query asking the terminal for its default foreground color.
The reply (`ESC]10;rgb:RRRR/GGGG/BBBB ST') is parsed by DECODE-COLOR-REPORT."
  (format nil "~C]10;?~C\\" +escape+ +escape+))

(defun ansi-request-background-color ()
  "Return the OSC 11 query asking the terminal for its default background color.
The reply is parsed by DECODE-COLOR-REPORT."
  (format nil "~C]11;?~C\\" +escape+ +escape+))

(define-ansi-function ansi-enable-line-wrap ()
    "Return the sequence that enables line wrapping at the right margin (DECAWM)."
  "~C[?7h")

(define-ansi-function ansi-disable-line-wrap ()
    "Return the sequence that disables line wrapping at the right margin (DECAWM)."
  "~C[?7l")

(define-ansi-function ansi-cursor-next-line (&optional (count 1))
    "Return the sequence moving the cursor COUNT lines down to column 1 (CNL)."
  "~C[~DE"
  count)

(define-ansi-function ansi-cursor-previous-line (&optional (count 1))
    "Return the sequence moving the cursor COUNT lines up to column 1 (CPL)."
  "~C[~DF"
  count)

(defun ansi-set-window-title (title)
  "Return the OSC sequence that sets the terminal window TITLE.
The payload is emitted as `ESC ] 0 ; TITLE BEL', the widely supported form."
  (format nil "~C]0;~A~C" +escape+ title (code-char 7)))

(defparameter +cursor-style-codes+
  '((:default . 0)
    (:blinking-block . 1)
    (:steady-block . 2)
    (:blinking-underline . 3)
    (:steady-underline . 4)
    (:blinking-bar . 5)
    (:steady-bar . 6))
  "Maps DECSCUSR cursor-shape keywords to their numeric parameters.")

(defun ansi-set-cursor-style (style)
  "Return the DECSCUSR sequence that selects the cursor shape STYLE.
STYLE is one of :DEFAULT, :BLINKING-BLOCK, :STEADY-BLOCK, :BLINKING-UNDERLINE,
:STEADY-UNDERLINE, :BLINKING-BAR, or :STEADY-BAR."
  (let ((code (cdr (assoc style +cursor-style-codes+))))
    (unless code
      (error "Unknown cursor style ~S; expected one of ~S."
             style
             (mapcar #'car +cursor-style-codes+)))
    (format nil "~C[~D q" +escape+ code)))

(defparameter +mouse-tracking-modes+
  '((:normal . 1000)
    (:button . 1002)
    (:any . 1003))
  "Maps mouse-tracking keywords to their DEC private-mode parameters: :NORMAL
reports press/release, :BUTTON adds motion while a button is held, and :ANY
reports all motion.")

(defun %mouse-tracking-code (mode)
  (or (cdr (assoc mode +mouse-tracking-modes+))
      (error "Unknown mouse tracking mode ~S; expected one of ~S."
             mode
             (mapcar #'car +mouse-tracking-modes+))))

(defun ansi-enable-mouse (&optional (mode :button))
  "Return the sequence that enables mouse reporting in tracking MODE.
MODE is :NORMAL, :BUTTON (the default), or :ANY. SGR extended coordinates
(mode 1006) are always enabled too so DECODE-MOUSE-SEQUENCE can parse the
reports regardless of terminal size."
  (format nil "~C[?~Dh~C[?1006h" +escape+ (%mouse-tracking-code mode) +escape+))

(defun ansi-disable-mouse (&optional (mode :button))
  "Return the sequence that disables mouse reporting enabled with MODE.
It resets SGR extended coordinates and the tracking mode selected by
ANSI-ENABLE-MOUSE, in reverse order."
  (format nil "~C[?1006l~C[?~Dl" +escape+ +escape+ (%mouse-tracking-code mode)))
