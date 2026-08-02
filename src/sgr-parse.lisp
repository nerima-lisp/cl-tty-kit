(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Reverse SGR parsing
;;;
;;; DECODE-SGR is the inverse of STYLE-ANSI: an SGR escape becomes a normalized
;;; style list. PARSE-STYLED-STRING walks a whole string, recovering the text and
;;; the style in force for each run -- the read counterpart to writing styled
;;; runs with STYLE-ANSI.
;;; --------------------------------------------------------------------------

(defmacro %sgr-parameter-body (string)
  "Return the parameter substring of an SGR escape STRING (between `[' and the
trailing `m'), or STRING itself when it is already a bare parameter body."
  `(let ((string ,string))
     (let ((open (position #\[ string))
           (close (position #\m string :from-end t)))
       (if (and open close (< open close))
           (subseq string (1+ open) close)
           string))))

(defmacro %sgr-basic-color-item (code)
  `(let ((code ,code))
     (cond
       ((<= 30 code 37) (list :fg (- code 30)))
       ((<= 90 code 97) (list :fg (+ 8 (- code 90))))
       ((<= 40 code 47) (list :bg (- code 40)))
       ((<= 100 code 107) (list :bg (+ 8 (- code 100))))
       (t nil))))

(defmacro %sgr-modifier-for (token)
  `(car (rassoc ,token +style-sgr-keywords+ :test #'string=)))

(defmacro %sgr-color-reset-channel (code)
  "Return the style channel keyword the SGR color-reset parameter CODE clears.
CODE is 39 (foreground), 49 (background), or 59 (underline color)."
  `(case ,code (39 :fg) (49 :bg) (t :underline-color)))

(defmacro %sgr-extended-color-item (tokens index count)
  "Parse an extended-color SGR parameter (38/48/58 at TOKENS[INDEX]) into
5;N (indexed) or 2;R;G;B (truecolor) form.
Returns (VALUES ITEM NEXT-INDEX): ITEM is the parsed style item, or NIL when
the parameter is malformed, truncated, or an unrecognized subtype; NEXT-INDEX
is how far the caller should advance past the whole parameter."
  `(let ((tokens ,tokens) (index ,index) (count ,count))
     (let ((channel (cond ((string= (aref tokens index) "38") :fg)
                          ((string= (aref tokens index) "48") :bg)
                          (t :underline-color)))
           (kind (and (< (1+ index) count) (aref tokens (1+ index)))))
       (cond
         ((and kind (string= kind "5") (< (+ index 2) count))
          (let ((color (%sgr-byte (aref tokens (+ index 2)))))
            (values (and color (list channel color)) (+ index 3))))
         ((and kind (string= kind "2") (< (+ index 4) count))
          (let ((red (%sgr-byte (aref tokens (+ index 2))))
                (green (%sgr-byte (aref tokens (+ index 3))))
                (blue (%sgr-byte (aref tokens (+ index 4)))))
            (values (and red green blue (list channel red green blue)) (+ index 5))))
         (t (values nil (1+ index)))))))

(defconstant +max-sgr-parameter-digits+ 12)

(defmacro %sgr-integer (token)
  `(let ((token ,token))
     (when (and (plusp (length token))
                (<= (length token) +max-sgr-parameter-digits+)
                (every #'digit-char-p token))
       (parse-integer token))))

(defmacro %sgr-byte (token)
  `(let ((value (%sgr-integer ,token)))
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
  (let* ((tokens (coerce (%split-on-char (%sgr-parameter-body string) #\;) 'vector))
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
                  (multiple-value-bind (item next-index)
                      (%sgr-extended-color-item tokens index count)
                    (when item (push item items))
                    (setf index next-index)))
                 ((and code (member code '(39 49 59)))
                  (let ((channel (%sgr-color-reset-channel code)))
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
