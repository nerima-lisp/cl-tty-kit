(in-package #:cl-tty-kit)

(defparameter +style-sgr-keywords+
  '((:bold . "1")
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

(defun %keyword-style-sgr-codes (style)
  (let ((code (cdr (assoc style +style-sgr-keywords+))))
    (and code (list code))))

(defun %color-style-sgr-codes (style)
  (destructuring-bind (channel &rest values) style
    (let ((prefix (case channel
                    (:fg "38")
                    (:bg "48")
                    (:underline-color "58")
                    (otherwise nil))))
      (when prefix
        (case (length values)
          (1 (list prefix "5" (write-to-string (first values))))
          (3 (list prefix "2"
                   (write-to-string (first values))
                   (write-to-string (second values))
                   (write-to-string (third values))))
          (otherwise nil))))))

(defun %style-sgr-codes (style)
  (cond
    ((keywordp style)
     (%keyword-style-sgr-codes style))
    ((consp style)
     (%color-style-sgr-codes style))
    (t nil)))

(defun %style-list-sgr-codes (style-list)
  (loop for style in style-list
        append (%style-sgr-codes style)))

(defun %supported-cell-style-codes (cell)
  (%style-list-sgr-codes (cell-style cell)))

(defun cell-blank-p (cell)
  "Return true when CELL is a space that renders no visible styling.
This is the same emptiness test RENDER-DIFF uses to decide a cell can be cleared
rather than repainted: the character is a space and the style emits no SGR codes
(an unsupported-only style still counts as blank)."
  (and (char= (cell-char cell) #\Space)
       (null (%supported-cell-style-codes cell))))

(defun style-ansi (&rest style)
  "Return the SGR escape string for STYLE, or an empty string if it emits none.
STYLE is any mix of modifier keywords and color entries accepted by MAKE-STYLE
(for example :BOLD, (STYLE-FG 208), or (STYLE-BG 0 0 0)); it is normalized the
same way a cell's style is, so ambiguous or duplicate entries collapse before
the escape is built. Callers that render their own text -- outside the SCREEN
grid -- can prefix a run with this and terminate it with ANSI-RESET-STYLE."
  (let ((codes (%style-list-sgr-codes (%normalize-cell-style style))))
    (if codes
        (format nil "~C[~{~A~^;~}m" +escape+ codes)
        "")))

(defparameter *cell-style-sequence-cache* (make-hash-table :test 'equal)
  "Memoizes the SGR escape string built for a cell's (already-normalized)
style list. A real screen has a small, bounded set of distinct styles in
use at once but many cells sharing each one, and the render/diff/length
passes each rebuild the same style's escape string independently, so
caching by style list turns repeat lookups into an O(1) hash hit.")

(defun %cell-style-sequence (cell)
  (let ((style (cell-style cell)))
    (multiple-value-bind (cached foundp)
        (gethash style *cell-style-sequence-cache*)
      (if foundp
          cached
          (setf (gethash style *cell-style-sequence-cache*)
                (let ((codes (%supported-cell-style-codes cell)))
                  (when codes
                    (format nil "~C[~{~A~^;~}m" +escape+ codes))))))))

(defun %cell-render-parts (cell)
  (let ((prefix (%cell-style-sequence cell))
        (char (string (cell-char cell))))
    (if prefix
        (list prefix char (ansi-reset-style))
        (list char))))

(defun %write-cell (cell stream)
  (dolist (part (%cell-render-parts cell) stream)
    (write-string part stream)))

