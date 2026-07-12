(in-package #:cl-tty-kit)

(defun %csi-modifiers (number)
  (modifiers-from-csi-number number))

(defun %lookup-event-code (key table &key (test #'eql))
  (cdr (assoc key table :test test)))

(defun %csi-event (final modifiers)
  (%key-event :special
              (or (%lookup-event-code final +csi-final-events+ :test #'char=)
                  final)
              modifiers))

(defun %code-point-character (code)
  (let ((char (code-char code)))
    (unless char
      (error 'unsupported-code-point :code-point code))
    char))

(defun %csi-tilde-event (code modifiers)
  (%key-event :special
              (or (%lookup-event-code code +csi-tilde-events+)
                  code)
              modifiers))

(defun %kitty-function-key (code)
  (%lookup-event-code code +kitty-function-keys+))

(defun %plain-key-event (ch)
  (values (%key-event :character ch nil) 1))

(defun %esc-o-event (final)
  (%lookup-event-code final +esc-o-events+ :test #'char=))

(defun %parse-esc-prefixed (string start)
  (let ((limit (length string)))
    (when (< (1+ start) limit)
      (let ((prefix (aref string (1+ start))))
        (cond
          ((char= prefix #\[)
           (let ((final-index (1- limit)))
             (when (<= (+ start 2) final-index)
               (let ((final (aref string final-index)))
                 (handler-case
                     (multiple-value-bind (code modifier validp)
                         (%parse-csi-body string (+ start 2) final-index)
                       (when validp
                         (values (%decode-csi-event code modifier final)
                                 limit)))
                   (unsupported-code-point ()
                     (values nil nil)))))))
          ((char= prefix #\O)
           (let ((final-index (+ start 2)))
             (when (< final-index limit)
               (let ((final (aref string final-index)))
                 (let ((code (%esc-o-event final)))
                   (when code
                     (values (%key-event :special code nil)
                             (1+ final-index))))))))
          (t
           (%plain-key-event prefix)))))))

(defun %csi-u-event (code modifier)
  (let* ((modifiers (%csi-modifiers modifier))
         (special (%kitty-function-key code)))
    (cond
      (special
       (%key-event :special special modifiers))
      ((<= 0 code #x10FFFF)
       (%key-event :character (%code-point-character code) modifiers))
      (t
       (error 'unsupported-code-point :code-point code)))))

(defun %parse-csi-integer (string start end)
  (when (< start end)
    (when (loop for index from start below end
                for ch = (aref string index)
                always (digit-char-p ch))
      (parse-integer string :start start :end end :junk-allowed t))))

(defun %parse-csi-body (string start end)
  (let* ((separator (position #\; string :start start :end end))
         (extra-separator (and separator
                               (position #\; string
                                         :start (1+ separator)
                                         :end end))))
    (cond
      ((= start end)
       (values nil nil t))
      (extra-separator
       (values nil nil nil))
      (separator
       (let* ((code-end separator)
              (modifier-start (1+ separator))
              (code (%parse-csi-integer string start code-end))
              (modifier (%parse-csi-integer string
                                            modifier-start
                                            end)))
         (values code modifier (and code modifier))))
      (t
       (let ((code (%parse-csi-integer string start end)))
         (values code nil (not (null code))))))))

(defun %csi-paste-marker-event (code final)
  (when (char= final #\~)
    (case code
      (200 (%key-event :special :paste-start))
      (201 (%key-event :special :paste-end))
      (otherwise nil))))

(defun %decode-csi-event (code modifier final)
  (or (%csi-paste-marker-event code final)
      (cond
        ((char= final #\~)
         (%csi-tilde-event code (%csi-modifiers modifier)))
        ((char= final #\u)
         (%csi-u-event code modifier))
        ((and code modifier)
         (%csi-event final (%csi-modifiers modifier)))
        (t
         (%csi-event final nil)))))
