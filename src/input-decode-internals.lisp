(in-package #:cl-tty-kit)

(defconstant +max-incomplete-escape-length+ 1024
  "Maximum bytes retained for an escape sequence that has not reached a final byte.")

(defun %incomplete-escape-sequence-p (string index)
  (when (char= (aref string index) #\Esc)
    (let ((limit (length string)))
      (and (<= (- limit index) +max-incomplete-escape-length+)
           (cond
             ((>= (1+ index) limit) t)
             ((char= (aref string (1+ index)) #\[)
              (let ((body-start (+ index 2)))
                (if (>= body-start limit)
                    t
                    ;; A CSI runs until its final byte (0x40-0x7E); every earlier
                    ;; byte is a parameter or intermediate. Treating anything before
                    ;; that byte as still-incomplete keeps a split parameter list --
                    ;; including an SGR mouse report's `<Cb;Cx;Cy' -- buffered
                    ;; instead of being decoded as a bare ESC.
                    (loop for final-index from body-start below limit
                          when (<= #x40 (char-code (aref string final-index)) #x7E)
                            do (return nil)
                          finally (return t)))))
             ((char= (aref string (1+ index)) #\O)
              (>= (+ index 2) limit))
             (t nil))))))

(defun %paste-marker-event-p (event marker)
  (and (eq :special (key-event-type event))
       (eq marker (key-event-code event))))

(defun %make-paste-event (payload)
  (make-key-event :type :paste :code payload :modifiers nil))

(defun %make-paste-buffer ()
  (make-array 0
              :element-type 'character
              :fill-pointer 0
              :adjustable t))

(defun %copy-paste-buffer-string (pending-paste)
  (copy-seq pending-paste))

(defun %normalize-paste-line-endings (string)
  "Convert CRLF and lone CR line endings in STRING to LF.
A terminal that sends CR-terminated (or CRLF-terminated) lines inside a
bracketed paste would otherwise leave a raw CR in a collected :PASTE event's
payload, which most callers treating it as ordinary LF-delimited buffer text
do not want."
  (with-output-to-string (out)
    (loop with limit = (length string)
          with index = 0
          while (< index limit)
          for ch = (char string index)
          do (cond
               ((char= ch #\Return)
                (write-char #\Newline out)
                (incf index)
                (when (and (< index limit) (char= (char string index) #\Newline))
                  (incf index)))
               (t
                (write-char ch out)
                (incf index))))))

(defun %assert-decoder-buffer-size (decoder size)
  "Signal when SIZE would exceed DECODER's retained-state bound."
  (when (> size (input-decoder-max-pending decoder))
    (error 'input-buffer-exceeded
           :limit (input-decoder-max-pending decoder)
           :size size))
  size)

(defun %decode-next-event (string index)
  (multiple-value-bind (event consumed)
      (decode-key-sequence string :start index)
    (values event (max 1 consumed))))

(declaim (notinline %collect-plain-events
                    %collect-paste-events
                    %decode-string-events-with-paste))

(defun %pending-escape-fragment (string index eof)
  (and (not eof)
       (%incomplete-escape-sequence-p string index)
       (subseq string index)))

(defun %collect-plain-events (string eof)
  (loop with events = '()
        with index = 0
        with limit = (length string)
        do (when (>= index limit)
             (return (values (nreverse events) "")))
           (let ((pending (%pending-escape-fragment string index eof)))
             (when pending
               (return (values (nreverse events) pending))))
           (multiple-value-bind (event consumed)
               (%decode-next-event string index)
             (push event events)
             (setf index (+ index consumed)))))

(defun %append-paste-string (decoder pending-paste chunk)
  (let* ((old-length (length pending-paste))
         (chunk-length (length chunk))
         (new-length (+ old-length chunk-length))
         (capacity (array-dimension pending-paste 0)))
    (%assert-decoder-buffer-size decoder new-length)
    (when (> new-length capacity)
      (setf pending-paste
            (adjust-array pending-paste
                          (max new-length (* 2 (max 1 capacity)))
                          :fill-pointer old-length)))
    (setf (fill-pointer pending-paste) new-length)
    (replace pending-paste chunk :start1 old-length))
  pending-paste)

(defun %fallback-paste-source (pending-paste suffix)
  (concatenate 'string
               +bracketed-paste-start-sequence+
               pending-paste
               suffix))

(defun %bracketed-paste-suffix-length (rest eof)
  (if eof
      0
      (loop for size from
              (min (length rest)
                   (1- (length +bracketed-paste-end-sequence+)))
            downto 1
            when (string= rest
                          +bracketed-paste-end-sequence+
                          :start1 (- (length rest) size)
                          :start2 0
                          :end2 size)
              do (return size)
            finally (return 0))))

(defun %plan-open-paste-transition (string index eof)
  (let ((end-index (search +bracketed-paste-end-sequence+ string :start2 index)))
    (if end-index
        (%make-transition
         :next-index (+ end-index (length +bracketed-paste-end-sequence+))
         :pending-string nil
         :actions (list (list :append-paste (subseq string index end-index))
                        '(:finish-paste)))
        (let* ((rest (subseq string index))
               (suffix-length (%bracketed-paste-suffix-length rest eof))
               (payload-end (- (length rest) suffix-length)))
          (if eof
              (%make-transition
               :next-index (length string)
               :pending-string nil
               :actions (list (list :flush-paste rest)))
              (%make-transition
               :next-index nil
               :pending-string (subseq rest payload-end)
               :actions (list (list :append-paste
                                    (subseq rest 0 payload-end)))))))))

(defun %plan-plain-transition (string index eof)
  (let ((pending (%pending-escape-fragment string index eof)))
    (if pending
        (%make-transition :next-index nil
                          :pending-string pending
                          :actions nil)
        (multiple-value-bind (event consumed)
            (%decode-next-event string index)
          (if (%paste-marker-event-p event :paste-start)
              (%make-transition :next-index (+ index consumed)
                                :pending-string nil
                                :actions '((:start-paste)))
              (%make-transition :next-index (+ index consumed)
                                :pending-string nil
                                :actions (list (list :emit event))))))))

(defun %decoder-transition (decoder string index eof)
  (with-input-decoder-state (decoder)
    (if pending-paste
        (%plan-open-paste-transition string index eof)
        (%plan-plain-transition string index eof))))

(defun %flush-pending-paste-events (decoder suffix)
  "Fall back to ordinary decoding of an unterminated paste, clearing the buffer.
Events are returned in reverse order so callers can prepend them onto the
reverse-order accumulator that %COLLECT-PASTE-EVENTS threads through the loop."
  (multiple-value-bind (flushed-events pending-string)
      (%collect-plain-events
       (%fallback-paste-source (input-decoder-pending-paste decoder) suffix)
       t)
    (declare (ignore pending-string))
    (setf (input-decoder-pending-paste decoder) nil)
    (nreverse flushed-events)))

(defun %apply-paste-transition-action (decoder events action)
  (ecase (first action)
    (:append-paste
     (setf (input-decoder-pending-paste decoder)
           (%append-paste-string decoder
                                 (input-decoder-pending-paste decoder)
                                 (second action)))
     events)
    (:emit
     (cons (second action) events))
    (:finish-paste
     (let ((text (%copy-paste-buffer-string (input-decoder-pending-paste decoder))))
       (push (%make-paste-event
              (if (input-decoder-normalize-paste-line-endings-p decoder)
                  (%normalize-paste-line-endings text)
                  text))
             events))
     (setf (input-decoder-pending-paste decoder) nil)
     events)
    (:flush-paste
     (nconc (%flush-pending-paste-events decoder (second action))
            events))
    (:start-paste
     (setf (input-decoder-pending-paste decoder) (%make-paste-buffer))
     events)))

(defun %collect-paste-events (decoder string eof)
  (let ((events '())
        (index 0)
        (limit (length string)))
    (loop
      (when (>= index limit)
        (when (and eof (input-decoder-pending-paste decoder))
          (setf events (nconc (%flush-pending-paste-events decoder "") events)))
        (return (values (nreverse events) "")))
      (let ((transition (%decoder-transition decoder string index eof)))
        (dolist (action (input-transition-actions transition))
          (setf events (%apply-paste-transition-action decoder events action)))
        (if (input-transition-pending-string transition)
            (return (values (nreverse events)
                            (input-transition-pending-string transition)))
            (setf index (input-transition-next-index transition)))))))

(defun %decode-string-events-with-paste (decoder string &key eof)
  (%collect-paste-events decoder string eof))
