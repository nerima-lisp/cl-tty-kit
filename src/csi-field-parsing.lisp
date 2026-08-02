(in-package #:cl-tty-kit)

(defmacro %csi-final-index (string start limit)
  "Return the index of the CSI final byte (0x40-0x7E) at or after START.
Parameter and intermediate bytes precede it; NIL means the CSI sequence has no
terminating byte within [START, LIMIT), i.e. it is still incomplete."
  `(let ((string ,string) (start ,start) (limit ,limit))
     (loop for index from start below limit
           when (<= #x40 (char-code (aref string index)) #x7E)
             do (return index)
           finally (return nil))))

(defparameter +max-csi-parameter-digits+ 18
  "Maximum digit run %PARSE-CSI-INTEGER accepts. No real CSI parameter needs
more than a few digits; capping this keeps an attacker-controlled multi-
megabyte digit run from being parsed into an arbitrarily large bignum.")

(defmacro %parse-csi-integer (string start end)
  `(let ((string ,string) (start ,start) (end ,end))
     (when (and (< start end)
                (<= (- end start) +max-csi-parameter-digits+))
       (when (loop for index from start below end
                   for ch = (aref string index)
                   always (digit-char-p ch))
         (parse-integer string :start start :end end :junk-allowed t)))))

(defmacro %parse-csi-modifier-field (string start end)
  "Parse a CSI modifier field, which the kitty protocol may write as
MODIFIER:EVENT-TYPE. Returns (VALUES MODIFIER EVENT), each an integer or NIL."
  `(let ((string ,string) (start ,start) (end ,end))
     (let ((colon (position #\: string :start start :end end)))
       (if colon
           (values (%parse-csi-integer string start colon)
                   (%parse-csi-integer string (1+ colon) end))
           (values (%parse-csi-integer string start end) nil)))))

(defmacro %parse-csi-field1 (string start end)
  "Parse a CSI-u first field UNICODE[:SHIFTED[:BASE]] into (VALUES PRIMARY SHIFTED
BASE), each an integer code point or NIL. The kitty protocol reports the shifted
and base-layout key alternates after the primary key."
  `(let ((string ,string) (start ,start) (end ,end))
     (let* ((colon1 (position #\: string :start start :end end))
            (colon2 (and colon1 (position #\: string :start (1+ colon1) :end end))))
       (values (%parse-csi-integer string start (or colon1 end))
               (and colon1 (%parse-csi-integer string (1+ colon1) (or colon2 end)))
               (and colon2 (%parse-csi-integer string (1+ colon2) end))))))

(defmacro %safe-code-char (code)
  "Return (CODE-CHAR CODE) when CODE is a valid code point, else NIL."
  `(let ((code ,code))
     (and (integerp code) (<= 0 code #x10FFFF) (code-char code))))

(defun %parse-csi-text (string start end)
  "Parse a kitty CSI-u text field -- a `:'-separated list of code points -- into
a string, or NIL when it is empty or malformed."
  (if (>= start end)
      nil
      (let ((characters '())
            (field-start start))
        (loop
          (let* ((colon (position #\: string :start field-start :end end))
                 (field-end (or colon end))
                 (code (%parse-csi-integer string field-start field-end)))
            (if (and code (<= 0 code #x10FFFF) (code-char code))
                (push (code-char code) characters)
                (return-from %parse-csi-text nil))
            (if colon
                (setf field-start (1+ colon))
                (return))))
        (coerce (nreverse characters) 'string))))

(defmacro %parse-csi-body (string start end)
  `(let ((string ,string) (start ,start) (end ,end))
     (let* ((sep1 (position #\; string :start start :end end))
            (sep2 (and sep1 (position #\; string :start (1+ sep1) :end end)))
            (sep3 (and sep2 (position #\; string :start (1+ sep2) :end end))))
       (cond
         ((= start end)
          (values nil nil t nil nil nil nil))
         ;; More than three `;'-separated fields is not a form we decode.
         (sep3
          (values nil nil nil nil nil nil nil))
         (sep1
          (multiple-value-bind (code shifted base)
              (%parse-csi-field1 string start sep1)
            (multiple-value-bind (modifier event)
                (%parse-csi-modifier-field string (1+ sep1) (or sep2 end))
              (values code modifier (and code modifier) event
                      (and sep2 (%parse-csi-text string (1+ sep2) end))
                      shifted base))))
         (t
          (let ((code (%parse-csi-integer string start end)))
            (values code nil (not (null code)) nil nil nil nil)))))))
