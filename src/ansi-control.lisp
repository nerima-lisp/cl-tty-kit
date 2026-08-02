(in-package #:cl-tty-kit)

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
  (format nil "~C[~:[~;?~]~Dh" +escape+ private
          (%validate-csi-numeric-parameter mode)))

(defun ansi-reset-mode (mode &key (private t))
  "Return the sequence that resets terminal MODE (an integer), turning it off.
The reset counterpart of ANSI-SET-MODE: `ESC [ ? MODE l' for a DEC private mode
(the default) or `ESC [ MODE l' when PRIVATE is NIL."
  (format nil "~C[~:[~;?~]~Dl" +escape+ private
          (%validate-csi-numeric-parameter mode)))

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

(defmacro %mouse-tracking-code (mode)
  `(let ((mode ,mode))
     (or (cdr (assoc mode +mouse-tracking-modes+))
         (error "Unknown mouse tracking mode ~S; expected one of ~S."
                mode
                (mapcar #'car +mouse-tracking-modes+)))))

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
