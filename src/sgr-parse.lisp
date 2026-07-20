(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Reverse SGR parsing
;;;
;;; DECODE-SGR is the inverse of STYLE-ANSI: an SGR escape becomes a normalized
;;; style list. PARSE-STYLED-STRING walks a whole string, recovering the text and
;;; the style in force for each run -- the read counterpart to writing styled
;;; runs with STYLE-ANSI.
;;; --------------------------------------------------------------------------

(defun %sgr-parameter-body (string)
  "Return the parameter substring of an SGR escape STRING (between `[' and the
trailing `m'), or STRING itself when it is already a bare parameter body."
  (let ((open (position #\[ string))
        (close (position #\m string :from-end t)))
    (if (and open close (< open close))
        (subseq string (1+ open) close)
        string)))

(defun %split-semicolons (string)
  (let ((parts '())
        (start 0)
        (length (length string)))
    (loop for position = (position #\; string :start start)
          do (push (subseq string start (or position length)) parts)
             (if position
                 (setf start (1+ position))
                 (return)))
    (nreverse parts)))

(defun %sgr-basic-color-item (code)
  (cond
    ((<= 30 code 37) (list :fg (- code 30)))
    ((<= 90 code 97) (list :fg (+ 8 (- code 90))))
    ((<= 40 code 47) (list :bg (- code 40)))
    ((<= 100 code 107) (list :bg (+ 8 (- code 100))))
    (t nil)))

(defun %sgr-modifier-for (token)
  (car (rassoc token +style-sgr-keywords+ :test #'string=)))

(defconstant +max-sgr-parameter-digits+ 12)

(defun %sgr-integer (token)
  (when (and (plusp (length token))
             (<= (length token) +max-sgr-parameter-digits+)
             (every #'digit-char-p token))
    (parse-integer token)))

(defun %sgr-byte (token)
  (let ((value (%sgr-integer token)))
    (and value (<= 0 value 255) value)))

(defun decode-sgr (string)
  "Parse an SGR escape STRING into (VALUES STYLE RESET-P).
STRING may be a full `ESC[...m' sequence or just its `;'-separated parameter
body. STYLE is a normalized style list (the inverse of STYLE-ANSI); RESET-P is
true when a reset parameter (0 or empty) was present. Recognized: the text
attributes (bold, dim, italic, the underline styles, blink, reverse, hidden,
strikethrough, overline), 30-37/90-97 and 40-47/100-107 basic colors, and 38/48/58
with a 5;N (indexed) or 2;R;G;B (truecolor) argument. 39/49/59 drop the matching
color; unknown parameters are ignored."
  (let* ((tokens (coerce (%split-semicolons (%sgr-parameter-body string)) 'vector))
         (count (length tokens))
         (items '())
         (reset-p nil)
         (index 0))
    (loop while (< index count)
          do (let* ((token (aref tokens index))
                    (code (%sgr-integer token)))
               (cond
                 ((or (string= token "0") (string= token ""))
                  (setf items '() reset-p t)
                  (incf index))
                 ((member token '("38" "48" "58") :test #'string=)
                  (let ((channel (cond ((string= token "38") :fg)
                                       ((string= token "48") :bg)
                                       (t :underline-color)))
                        (kind (and (< (1+ index) count) (aref tokens (1+ index)))))
                    (cond
                      ((and kind (string= kind "5") (< (+ index 2) count))
                       (let ((color (%sgr-byte (aref tokens (+ index 2)))))
                         (when color
                           (push (list channel color) items)))
                       (incf index 3))
                      ((and kind (string= kind "2") (< (+ index 4) count))
                       (let ((red (%sgr-byte (aref tokens (+ index 2))))
                             (green (%sgr-byte (aref tokens (+ index 3))))
                             (blue (%sgr-byte (aref tokens (+ index 4)))))
                         (when (and red green blue)
                           (push (list channel red green blue) items)))
                       (incf index 5))
                      (t (incf index)))))
                 ((and code (member code '(39 49 59)))
                  (let ((channel (case code (39 :fg) (49 :bg) (t :underline-color))))
                    (setf items (remove channel items
                                        :key (lambda (item)
                                               (and (consp item) (first item))))))
                  (incf index))
                 ((%sgr-modifier-for token)
                  (push (%sgr-modifier-for token) items)
                  (incf index))
                 ((and code (%sgr-basic-color-item code))
                  (push (%sgr-basic-color-item code) items)
                  (incf index))
                 (t
                  (incf index)))))
    (values (apply #'make-style (nreverse items)) reset-p)))

(defun parse-styled-string (string)
  "Parse STRING containing SGR escapes into a list of (TEXT . STYLE) segments.
STYLE is the normalized style in force over TEXT (NIL when unstyled); consecutive
SGR sequences accumulate (via STYLE-MERGE) until a reset. Non-SGR escape
sequences are dropped. This recovers the text and styling written with STYLE-ANSI
or the ANSI-* attribute builders."
  (let ((segments '())
        (current-style nil)
        (index 0)
        (limit (length string))
        (run (make-string-output-stream)))
    (flet ((flush ()
             (let ((text (get-output-stream-string run)))
               (when (plusp (length text))
                 (push (cons text current-style) segments)))))
      (loop while (< index limit)
            do (let ((char (char string index)))
                 (cond
                   ((and (char= char #\Esc)
                         (< (1+ index) limit)
                         (char= (char string (1+ index)) #\[))
                    (let ((final (%csi-final-index string (+ index 2) limit)))
                      (cond
                        ((null final) (setf index limit))
                        ((char= (char string final) #\m)
                         (flush)
                         (multiple-value-bind (style reset-p)
                             (decode-sgr (subseq string index (1+ final)))
                           (setf current-style (if reset-p
                                                   style
                                                   (style-merge current-style style))))
                         (setf index (1+ final)))
                        (t (setf index (1+ final))))))
                   ((char= char #\Esc)
                    (setf index (%skip-escape-sequence string index limit)))
                   (t
                    (write-char char run)
                    (incf index)))))
      (flush))
    (nreverse segments)))
