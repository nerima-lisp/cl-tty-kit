(in-package #:cl-tty-kit)

(defun %incomplete-escape-sequence-p (string index)
  (when (char= (aref string index) #\Esc)
    (let ((limit (length string)))
      (cond
        ((>= (1+ index) limit) t)
        ((char= (aref string (1+ index)) #\[)
         (let ((body-start (+ index 2)))
           (if (>= body-start limit)
               t
               (loop for final-index from body-start below limit
                     for final = (aref string final-index)
                     unless (or (digit-char-p final) (char= final #\;))
                       do (return nil)
                     finally (return t)))))
        ((char= (aref string (1+ index)) #\O)
         (>= (+ index 2) limit))
        (t nil)))))

(defun %paste-marker-event-p (event marker)
  (and (eq :special (key-event-type event))
       (eq marker (key-event-code event))))

(defun %make-paste-event (payload)
  (make-key-event :type :paste :code payload :modifiers nil))

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

(defun %append-paste-string (pending-paste chunk)
  (concatenate 'string pending-paste chunk))

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
  (multiple-value-bind (flushed-events pending-string)
      (%collect-plain-events
       (%fallback-paste-source (input-decoder-pending-paste decoder) suffix)
       :eof t)
    (declare (ignore pending-string))
    (setf (input-decoder-pending-paste decoder) nil)
    flushed-events))

(defun %apply-paste-transition-action (decoder events action)
  (ecase (first action)
    (:append-paste
     (setf (input-decoder-pending-paste decoder)
           (%append-paste-string (input-decoder-pending-paste decoder)
                                 (second action)))
     events)
    (:emit
     (cons (second action) events))
    (:finish-paste
     (push (%make-paste-event (input-decoder-pending-paste decoder)) events)
     (setf (input-decoder-pending-paste decoder) nil)
     events)
    (:flush-paste
     (nconc events
            (%flush-pending-paste-events decoder (second action))))
    (:start-paste
     (setf (input-decoder-pending-paste decoder) "")
     events)))

(defun %collect-paste-events (decoder string eof)
  (let ((events '())
        (index 0)
        (limit (length string)))
    (loop
      (when (>= index limit)
        (when (and eof (input-decoder-pending-paste decoder))
          (setf events (nconc events (%flush-pending-paste-events decoder ""))))
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

