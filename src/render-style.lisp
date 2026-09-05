(in-package #:cl-tty-kit)

(defparameter +style-sgr-keywords+ '((:bold . "1")
    (:dim . "2")
    (:italic . "3")
    (:underline . "4")
    (:double-underline . "4:2")
    (:curly-underline . "4:3")
    (:dotted-underline . "4:4")
    (:dashed-underline . "4:5")
    (:blink . "5")
    (:reverse . "7")
    (:hidden . "8")
    (:strikethrough . "9")
    (:overline . "53")))

(progn
  (defun cell-blank-p (cell)
    "Return true when CELL is a space that renders no visible styling.
This is the same emptiness test RENDER-DIFF uses to decide a cell can be cleared
rather than repainted: the character is a space and the style emits no SGR codes
(an unsupported-only style still counts as blank)."
    (let ((cell (%assert-cell cell)))
      (and (char= (cell-char cell) #\Space) (null (%cell-style-sequence cell)))))
  (declaim (inline %write-style-sgr-number))
  (defun %write-style-sgr-number (number stream)
    (write number :stream stream :escape nil :base 10 :radix nil))
  (defun %write-style-sgr-code (style stream wrote-p)
    (cond
      ((keywordp style)
       (let ((code (cdr (assoc style +style-sgr-keywords+))))
         (when code
           (when wrote-p
             (write-char #\; stream))
           (write-string code stream)
           t)))
      ((consp style)
       (destructuring-bind (channel &rest values) style
         (let ((prefix (case channel
                         (:fg "38")
                         (:bg "48")
                         (:underline-color "58")
                         (otherwise nil))))
           (let ((value-count (length values)))
             (declare (type fixnum value-count))
             (when (and prefix (or (= value-count 1) (= value-count 3)))
               (when wrote-p
                 (write-char #\; stream))
               (write-string prefix stream)
               (write-char #\; stream)
               (case value-count
                 (1
                  (write-char #\5 stream)
                  (write-char #\; stream)
                  (%write-style-sgr-number (first values) stream))
                 (3
                  (write-char #\2 stream)
                  (dolist (value values)
                    (write-char #\; stream)
                    (%write-style-sgr-number value stream))))
               t)))))
      (t nil)))
  (defun %style-sgr-sequence (style-list)
    (let ((wrote-p nil))
      (let ((sequence
            (with-output-to-string (stream)
              (write-char +escape+ stream)
              (write-char #\[ stream)
              (dolist (style style-list)
                (when (%write-style-sgr-code style stream wrote-p)
                  (setf wrote-p t)))
              (when wrote-p
                (write-char #\m stream)))))
        (and wrote-p sequence)))))

(defun style-ansi (&rest style)
  "Return the SGR escape string for STYLE, or an empty string if it emits none.
STYLE is any mix of modifier keywords and color entries accepted by MAKE-STYLE
(for example :BOLD, (STYLE-FG 208), or (STYLE-BG 0 0 0)); it is normalized the
same way a cell's style is, so ambiguous or duplicate entries collapse before
the escape is built. Callers that render their own text -- outside the SCREEN
grid -- can prefix a run with this and terminate it with ANSI-RESET-STYLE."
  (or (%style-sgr-sequence (%normalize-cell-style style)) ""))

(progn
  (defvar *style-sgr-sequence-cache* nil)

  (defvar *style-sgr-sequence-cache-enabled-p* nil)

  (defmacro %with-style-sgr-sequence-cache (&body body)
    `(let ((*style-sgr-sequence-cache* nil)
           (*style-sgr-sequence-cache-enabled-p* t))
       ,@body))

  (defun %cell-style-sequence (cell)
    (if (cell-style-sequence-ready-p cell)
        (cell-style-sequence cell)
        (let* ((style (cell-raw-style cell))
               (sequence
                 (and style
                      (if *style-sgr-sequence-cache-enabled-p*
                          (let ((cache
                                  (or *style-sgr-sequence-cache*
                                      (setf *style-sgr-sequence-cache*
                                            (make-hash-table :test (function equal))))))
                            (multiple-value-bind (cached present-p)
                                (gethash style cache)
                              (if present-p
                                  cached
                                  (setf (gethash style cache)
                                        (%style-sgr-sequence style)))))
                          (%style-sgr-sequence style)))))
          (setf (cell-style-sequence cell) sequence
                (cell-style-sequence-ready-p cell) t)
          sequence))))

(defun %render-safe-cell-character (char)
  (if (%terminal-control-character-p char) #\Space
    char))

(defun %cell-rendered-length (cell)
  (let ((prefix (%cell-style-sequence cell)))
    (+
      1
      (if prefix (+ (length prefix) +ansi-reset-style-length+)
        0))))

(progn
  (defun %write-cell (cell stream)
    (let ((prefix (%cell-style-sequence cell)))
      (when prefix
        (write-string prefix stream))
      (write-char (%render-safe-cell-character (cell-char cell)) stream)
      (when prefix
        (%write-ansi-reset-style stream)))
    stream)

  (defun %same-style-sgr-sequence-p (left right)
    (or (eq left right)
        (and left right (string= left right))))

  (defun %write-cell-range (cells start end stream)
    "Write CELLS in [START, END), emitting SGR transitions only when needed."
    (declare (type simple-vector cells)
             (type fixnum start end))
    (let ((active-prefix nil))
      (do ((index start (1+ index)))
          ((>= index end)
           (when active-prefix
             (%write-ansi-reset-style stream))
           stream)
        (declare (type fixnum index))
        (let* ((cell (aref cells index))
               (prefix (%cell-style-sequence cell)))
          (unless (%same-style-sgr-sequence-p active-prefix prefix)
            (when active-prefix
              (%write-ansi-reset-style stream))
            (when prefix
              (write-string prefix stream))
            (setf active-prefix prefix))
          (write-char (%render-safe-cell-character (cell-char cell)) stream)))))

  (defun %cell-range-rendered-length (cells start end)
    "Return the byte count %WRITE-CELL-RANGE emits for CELLS in [START, END)."
    (declare (type simple-vector cells)
             (type fixnum start end))
    (let ((active-prefix nil)
          (output-length 0))
      (declare (type fixnum output-length))
      (do ((index start (1+ index)))
          ((>= index end)
           (when active-prefix
             (incf output-length +ansi-reset-style-length+))
           output-length)
        (declare (type fixnum index))
        (let* ((cell (aref cells index))
               (prefix (%cell-style-sequence cell)))
          (unless (%same-style-sgr-sequence-p active-prefix prefix)
            (when active-prefix
              (incf output-length +ansi-reset-style-length+))
            (when prefix
              (incf output-length (length prefix)))
            (setf active-prefix prefix))
          (incf output-length))))))
