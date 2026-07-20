(in-package #:cl-tty-kit)

(defun %input->string (input)
  (cond
    ((stringp input)
     input)
    ((%octet-input-p input)
     (%utf8-octets-to-string input))
    ((vectorp input)
     (coerce input 'string))
    (t
     (error "Unsupported input type: ~S" (type-of input)))))

(defun decode-key-sequence (input &key (start 0))
  "Decode a single key sequence from INPUT starting at START.
Returns two values: a KEY-EVENT and the number of consumed characters."
  ;; This function parses untrusted terminal input, so it keeps full safety:
  ;; bounds and type checks must stay enabled to turn any malformed sequence
  ;; into a signaled condition rather than undefined behavior.
  (let* ((string (%input->string input))
         (length (length string)))
    (when (< start length)
      (let ((ch (aref string start)))
        (cond
          ((char= ch #\Esc)
           (multiple-value-bind (event consumed)
               (%parse-esc-prefixed string start)
             (if event
                 (values event consumed)
                 (values (%key-event :special :escape nil) 1))))
          ((char= ch #\Rubout)
           (values (%key-event :special :backspace nil) 1))
          (t (%plain-key-event ch)))))))

(defun decode-device-attributes (input &key (start 0))
  "Decode a Device Attributes report `ESC [ [?|>] p1 ; p2 ; ... c' from INPUT at
START. Returns (VALUES PARAMS CONSUMED) where PARAMS is the list of integer
parameters (empty for a bare `ESC [ c'), or (VALUES NIL 0) when INPUT at START is
not a complete report. Pairs with ANSI-REQUEST-DEVICE-ATTRIBUTES."
  (let* ((string (%input->string input))
         (limit (length string)))
    (block nil
      (unless (and (< (1+ start) limit)
                   (char= (char string start) #\Esc)
                   (char= (char string (1+ start)) #\[))
        (return (values nil 0)))
      (let ((position (+ start 2)))
        (when (and (< position limit)
                   (member (char string position) '(#\? #\>) :test #'char=))
          (incf position))
        (let ((final (position #\c string :start position :end limit)))
          (unless final
            (return (values nil 0)))
          (let ((params '())
                (field-start position))
            (loop
              (let* ((separator (position #\; string :start field-start :end final))
                     (field-end (or separator final))
                     (value (%parse-mouse-uint string field-start field-end)))
                (when value (push value params))
                (if separator
                    (setf field-start (1+ separator))
                    (return))))
            (values (nreverse params) (- (1+ final) start))))))))

(defun %scale-hex-to-byte (string start end)
  "Parse the hex field [START, END) of STRING and scale it to a byte in [0, 255]
by its digit width, so a 2- or 4-hex-digit OSC color component maps correctly."
  (when (and (< start end)
             (loop for index from start below end
                   always (digit-char-p (char string index) 16)))
    (let* ((digits (- end start))
           (value (parse-integer string :start start :end end :radix 16))
           (maximum (1- (expt 16 digits))))
      (if (zerop maximum) 0 (round (* value 255) maximum)))))

(defun %color-report-terminator (string start limit)
  "Return (VALUES POSITION LENGTH) of the ST terminating an OSC reply at or after
START -- BEL (length 1) or ESC backslash (length 2) -- or (VALUES NIL NIL)."
  (loop for index from start below limit
        do (cond
             ((char= (char string index) (code-char 7))
              (return (values index 1)))
             ((and (char= (char string index) #\Esc)
                   (< (1+ index) limit)
                   (char= (char string (1+ index)) #\\))
              (return (values index 2))))
        finally (return (values nil nil))))

(defun decode-color-report (input &key (start 0))
  "Decode an OSC 10/11 color report `ESC ] {10|11} ; rgb:RR../GG../BB.. ST' from
INPUT at START. Returns (VALUES R G B CONSUMED), each channel scaled to [0, 255],
or (VALUES NIL NIL NIL 0) when INPUT at START is not a complete report. The
terminator ST may be BEL or ESC backslash. Pairs with the OSC 10/11 request
builders ANSI-REQUEST-FOREGROUND-COLOR / ANSI-REQUEST-BACKGROUND-COLOR."
  (let* ((string (%input->string input))
         (limit (length string)))
    (block nil
      (unless (and (< (1+ start) limit)
                   (char= (char string start) #\Esc)
                   (char= (char string (1+ start)) #\]))
        (return (values nil nil nil 0)))
      (let ((rgb-position (search "rgb:" string :start2 (+ start 2) :end2 limit)))
        (unless rgb-position
          (return (values nil nil nil 0)))
        (let ((body-start (+ rgb-position 4)))
          (multiple-value-bind (terminator terminator-length)
              (%color-report-terminator string body-start limit)
            (unless terminator
              (return (values nil nil nil 0)))
            (let* ((slash1 (position #\/ string :start body-start :end terminator))
                   (slash2 (and slash1 (position #\/ string
                                                 :start (1+ slash1)
                                                 :end terminator))))
              (unless (and slash1 slash2)
                (return (values nil nil nil 0)))
              (let ((r (%scale-hex-to-byte string body-start slash1))
                    (g (%scale-hex-to-byte string (1+ slash1) slash2))
                    (b (%scale-hex-to-byte string (1+ slash2) terminator)))
                (if (and r g b)
                    (values r g b (- (+ terminator terminator-length) start))
                    (values nil nil nil 0))))))))))

(defun decode-cursor-position-report (input &key (start 0))
  "Decode a cursor position report `ESC [ row ; col R' from INPUT at START.
Returns (VALUES ROW COL CONSUMED) with 0-based ROW and COL, converted from the
terminal's 1-based reply, or (VALUES NIL NIL 0) when INPUT at START is not a
complete report. Because a bare `ESC [ r ; c R' is ambiguous with a modified F3
key, this is a standalone decoder to call after ANSI-REQUEST-CURSOR-POSITION,
rather than being folded into DECODE-INPUT."
  (let* ((string (%input->string input))
         (limit (length string)))
    (if (and (< (+ start 2) limit)
             (char= (char string start) #\Esc)
             (char= (char string (1+ start)) #\[))
        (let ((final (loop for index from (+ start 2) below limit
                           when (char= (char string index) #\R)
                             do (return index)
                           finally (return nil))))
          (if final
              (let ((separator (position #\; string :start (+ start 2) :end final)))
                (if separator
                    (let ((row (%parse-mouse-uint string (+ start 2) separator))
                          (col (%parse-mouse-uint string (1+ separator) final)))
                      (if (and row col)
                          (values (max 0 (1- row))
                                  (max 0 (1- col))
                                  (- (1+ final) start))
                          (values nil nil 0)))
                    (values nil nil 0)))
              (values nil nil 0)))
        (values nil nil 0))))
