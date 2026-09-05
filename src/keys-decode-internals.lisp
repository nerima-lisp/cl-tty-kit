(in-package #:cl-tty-kit)

(defmacro %csi-modifiers (number)
  `(modifiers-from-csi-number ,number))

(defun %lookup-event-code (key table &key (test #'eql))
  (cdr (assoc key table :test test)))

(defmacro %event-kind (event)
  "Map a kitty CSI-u event-type number to a KEY-EVENT kind keyword.
1 (or NIL, the default) is :PRESS, 2 is :REPEAT, 3 is :RELEASE."
  `(case ,event
     (2 :repeat)
     (3 :release)
     (otherwise :press)))

(defun %csi-event (final modifiers &optional (kind :press))
  (%key-event :special
              (or (%lookup-event-code final +csi-final-events+ :test #'char=)
                  :unknown-csi)
              modifiers
              kind))

(defmacro %code-point-character (code)
  "Return the character for CODE, an integer in [0, #x10FFFF] (the only range
%CSI-U-EVENT calls this with). On SBCL this never signals in practice:
CHAR-CODE-LIMIT is #x110000, one past #x10FFFF, so CODE-CHAR always succeeds
for every value CODE can hold here -- the signal exists as a portability
guard against a CL implementation whose CODE-CHAR is stricter."
  `(let* ((code ,code)
          (char (code-char code)))
     (unless char
       (error 'unsupported-code-point :code-point code))
     char))

(defun %csi-tilde-event (code modifiers &optional (kind :press))
  (%key-event :special
              (or (%lookup-event-code code +csi-tilde-events+)
                  :unknown-csi)
              modifiers
              kind))

(defmacro %kitty-function-key (code)
  `(%lookup-event-code ,code +kitty-function-keys+))

(defun %plain-key-event (ch &optional modifiers)
  "Decode a single non-escape character CH into a KEY-EVENT plus consumed count.
Control bytes map to their named special keys (:ENTER, :TAB, :BACKSPACE, ...) or
Ctrl-letter events (:CONTROL-A ... :CONTROL-Z); everything else becomes a
:CHARACTER event. MODIFIERS are attached to the resulting event."
  (let* ((code (char-code ch))
         (special (or (%lookup-event-code code +control-key-codes+)
                      (%lookup-event-code code +control-letter-events+))))
    (if special
        (values (%key-event :special special modifiers) 1)
        (values (%key-event :character ch modifiers) 1))))

(defmacro %esc-o-event (final)
  `(%lookup-event-code ,final +esc-o-events+ :test #'char=))

(defmacro %parse-esc-o-prefixed (string start limit)
  "Parse the `ESC O X' SS3 form (an application-keypad/F1-F4 report)
starting at START, mirroring %PARSE-CSI-PREFIXED's shape for its `ESC [ ...'
sibling. Returns (VALUES EVENT CONSUMED), or NIL when the sequence is
incomplete or its final byte is unrecognized."
  `(let ((string ,string) (start ,start) (limit ,limit))
     (let ((final-index (+ start 2)))
       (when (< final-index limit)
         (let* ((final (aref string final-index))
                (code (%esc-o-event final)))
           (when code
             (values (%key-event :special code nil)
                     (- (1+ final-index) start))))))))

(defmacro %parse-esc-prefixed (string start)
  `(let ((string ,string) (start ,start))
     (let ((limit (length string)))
       (when (< (1+ start) limit)
         (let ((prefix (aref string (1+ start))))
           (cond
             ((char= prefix #\[)
              (if (and (< (+ start 2) limit)
                       (char= (aref string (+ start 2)) #\<))
                  ;; `ESC [ <' is the SGR mouse prefix; hand it to the mouse
                  ;; decoder, which yields a MOUSE-EVENT alongside key events or
                  ;; NIL (falling through to the :ESCAPE fallback) on a fragment.
                  (decode-mouse-sequence string :start start)
                  (%parse-csi-prefixed string start limit)))
             ((char= prefix #\O)
              (%parse-esc-o-prefixed string start limit))
             (t
              (values (nth-value 0 (%plain-key-event prefix '(:alt)))
                      2))))))))

(defmacro %parse-csi-prefixed (string start limit)
  `(let ((string ,string) (start ,start) (limit ,limit))
     (let ((final-index (%csi-final-index string (+ start 2) limit)))
       (when final-index
         (let ((final (aref string final-index)))
           (handler-case
               (multiple-value-bind (code modifier validp event text shifted base)
                   (%parse-csi-body string (+ start 2) final-index)
                 (when validp
                   (values (%decode-csi-event code modifier final event text
                                              shifted base)
                           (- (1+ final-index) start))))
             (unsupported-code-point ()
               (values nil nil))))))))

(defun %csi-u-event (code modifier &optional (kind :press) text shifted base)
  ;; An empty CSI-u parameter body (e.g. the sequence `ESC [ u`) yields a NIL
  ;; CODE. Return NIL so the caller falls back to ordinary decoding instead of
  ;; letting a comparison against NIL raise an uncaught TYPE-ERROR on untrusted
  ;; input.
  (let* ((modifiers (%csi-modifiers modifier))
         (special (and (integerp code) (%kitty-function-key code)))
         (shifted-char (%safe-code-char shifted))
         (base-char (%safe-code-char base)))
    (cond
      (special
       (make-key-event :type :special :code special :modifiers modifiers
                       :kind kind :text text
                       :shifted-key shifted-char :base-key base-char))
      ((and (integerp code) (<= 0 code #x10FFFF))
       (make-key-event :type :character :code (%code-point-character code)
                       :modifiers modifiers :kind kind :text text
                       :shifted-key shifted-char :base-key base-char))
      ((integerp code)
       (error 'unsupported-code-point :code-point code))
      (t
       nil))))

(defmacro %csi-paste-marker-event (code final)
  `(when (char= ,final #\~)
     (case ,code
       (200 (%key-event :special :paste-start))
       (201 (%key-event :special :paste-end))
       (otherwise nil))))

(defun %decode-csi-event (code modifier final &optional event text shifted base)
  (let ((kind (%event-kind event)))
    (or (%csi-paste-marker-event code final)
      (cond
        ((char= final #\~)
         (%csi-tilde-event code (%csi-modifiers modifier) kind))
        ((char= final #\u)
         (%csi-u-event code modifier kind text shifted base))
        ((and code modifier)
         (%csi-event final (%csi-modifiers modifier) kind))
        (t
         (%csi-event final nil))))))
