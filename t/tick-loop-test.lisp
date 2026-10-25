(in-package #:cl-tty-kit/test)

(describe "tick-loop-run"
  (it "calls advance exactly N times and returns the final state"
    (let ((calls 0))
      (multiple-value-bind (final-state frames)
          (tick-loop-run 0 (lambda (state) (incf calls) (1+ state)) 5)
        (expect calls :to-be 5)
        (expect final-state :to-be 5)
        (expect frames :to-be nil))))
  (it "performs no advance calls and returns state unchanged for zero ticks"
    (let ((calls 0))
      (multiple-value-bind (final-state frames)
          (tick-loop-run :initial (lambda (state) (incf calls) state) 0)
        (expect calls :to-be 0)
        (expect final-state :to-be :initial)
        (expect frames :to-equal nil))))
  (it "collects one rendered frame per tick, in tick order, from the post-tick state"
    (multiple-value-bind (final-state frames)
        (tick-loop-run 0 #'1+ 3 :render (lambda (state) (format nil "s~D" state)))
      (expect final-state :to-be 3)
      (expect frames :to-equal '("s1" "s2" "s3"))))
  (it "threads each new state into the next advance call"
    (multiple-value-bind (final-state frames)
        (tick-loop-run '() (lambda (state) (cons (length state) state)) 4
                       :render #'copy-list)
      (declare (ignore frames))
      (expect final-state :to-equal '(3 2 1 0))))
  (it "signals a non-type-error for malformed arguments"
    (expect-non-type-error (tick-loop-run 0 :not-a-function 1))
    (expect-non-type-error (tick-loop-run 0 #'1+ 1 :render :not-a-function))
    (expect-non-type-error (tick-loop-run 0 #'1+ -1))
    (expect-non-type-error (tick-loop-run 0 #'1+ :bad))))

(describe "tick-loop-run-realtime"
  (it "advances, renders, and writes each frame to :stream until :stop is true"
    (let ((stream (make-string-output-stream))
          (timings '()))
      (let ((final-state
              (tick-loop-run-realtime
               0
               #'1+
               (lambda (state) (format nil "<~D>" state))
               (lambda (state) (>= state 3))
               :stream stream
               :interval 1/1000
               :on-timing (lambda (event tick-number value)
                            (push (list event tick-number value) timings)))))
        (expect final-state :to-be 3)
        (expect (get-output-stream-string stream) :to-equal "<1><2><3>")
        (setf timings (nreverse timings))
        (let ((phase-timings
                (remove-if-not
                 (lambda (timing)
                   (member (first timing)
                           '(:deadline-sleep :wake-overshoot :advance :render
                             :write-string :finish-output)))
                 timings)))
          (expect (mapcar #'first phase-timings)
                  :to-equal
                  '(:deadline-sleep :wake-overshoot :advance :render
                    :write-string :finish-output
                    :deadline-sleep :wake-overshoot :advance :render
                    :write-string :finish-output
                    :deadline-sleep :wake-overshoot :advance :render
                    :write-string :finish-output))
          (expect (mapcar #'second phase-timings)
                  :to-equal '(1 1 1 1 1 1 2 2 2 2 2 2 3 3 3 3 3 3))
          (expect (every (lambda (timing)
                           (and (realp (third timing))
                                (>= (third timing) 0)))
                         phase-timings)
                  :to-be t)))))
  (it "checks :stop only after advancing and rendering, so it always emits the stopping frame"
    (let* ((stream (make-string-output-stream))
           (rendered '()))
      (tick-loop-run-realtime
       0
       #'1+
       (lambda (state) (push state rendered) (format nil "~D" state))
       (lambda (state) (= state 1))
       :stream stream
       :interval 1/1000)
      (expect (nreverse rendered) :to-equal '(1))
      (expect (get-output-stream-string stream) :to-equal "1")))
  (it "returns the final state, matching what was rendered and streamed last"
    (let ((stream (make-string-output-stream)))
      (let ((final-state
              (tick-loop-run-realtime
               10
               (lambda (state) (- state 1))
               (lambda (state) (format nil "~D" state))
               (lambda (state) (<= state 7))
               :stream stream
               :interval 1/1000)))
        (expect final-state :to-be 7)
        (expect (get-output-stream-string stream) :to-equal "987"))))
  (it "polls before each tick and threads the polled state into advance"
    (let ((poll-count 0)
          (advance-count 0)
          (stream (make-string-output-stream)))
      (let ((final-state
              (tick-loop-run-realtime
               0
               (lambda (state)
                 (incf advance-count)
                 (1+ state))
               (lambda (state) (format nil "~D" state))
               (lambda (state) (= state 2))
               :stream stream
               :interval 1/1000
               :poll (lambda (state)
                       (incf poll-count)
                       state))))
        (expect final-state :to-be 2)
        (expect poll-count :to-be 2)
        (expect advance-count :to-be 2)
        (expect (get-output-stream-string stream) :to-equal "12"))))
  (it "allows a render function to suppress output or write directly to the stream"
    (let ((stream (make-string-output-stream))
          (render-count 0)
          (timings '()))
      (tick-loop-run-realtime
       0 #'1+
       (lambda (state)
         (incf render-count)
         (cond
           ((= state 1) nil)
           ((= state 2)
            (write-string "direct" stream)
            (values stream t))
           (t "framed")))
       (lambda (state) (= state 3))
       :stream stream
       :interval 1/1000
       :on-timing (lambda (event tick-number value)
                    (push (list event tick-number value) timings)))
      (expect render-count :to-be 3)
      (expect (get-output-stream-string stream) :to-equal "directframed")
      (setf timings (nreverse timings))
      (let ((output-timings
              (remove-if-not
               (lambda (timing)
                 (member (first timing) '(:write-string :finish-output)))
               timings)))
        (expect (mapcar #'first output-timings)
                :to-equal '(:finish-output :write-string :finish-output))
        (expect (mapcar #'second output-timings) :to-equal '(2 3 3)))))
  (it "signals a non-type-error for malformed arguments"
    (expect-non-type-error
     (tick-loop-run-realtime 0 :not-a-function (lambda (s) (declare (ignore s)) "") (lambda (s) t)))
    (expect-non-type-error
     (tick-loop-run-realtime 0 #'1+ :not-a-function (lambda (s) t)))
    (expect-non-type-error
     (tick-loop-run-realtime 0 #'1+ (lambda (s) (declare (ignore s)) "") :not-a-function))
    (expect-non-type-error
     (tick-loop-run-realtime 0 #'1+
                             (lambda (s) (declare (ignore s)) "")
                             (lambda (s) (declare (ignore s)) t)
                             :interval 0))
    (expect-non-type-error
     (tick-loop-run-realtime 0 #'1+ (lambda (s) (declare (ignore s)) "")
                             (lambda (s) t) :poll :not-a-function))
    (expect-non-type-error
     (tick-loop-run-realtime 0 #'1+ (lambda (s) (declare (ignore s)) "")
                             (lambda (s) t) :on-timing :not-a-function))
    (let ((observer-error-propagated-p nil))
      (handler-case
          (tick-loop-run-realtime
           0 #'1+
           (lambda (state) (declare (ignore state)) nil)
           (lambda (state) (declare (ignore state)) t)
           :interval 1/1000
           :on-timing (lambda (event tick-number value)
                        (declare (ignore event tick-number value))
                        (error 'program-error)))
        (program-error ()
          (setf observer-error-propagated-p t)))
      (expect observer-error-propagated-p :to-be t)))
  (it "does not accumulate repeated scheduler wake overshoot"
    (let ((now 0)
          (starts '())
          (timings '())
          (stream (make-string-output-stream))
          (units internal-time-units-per-second))
      (let ((cl-tty-kit::*tick-loop-clock* (lambda () now))
            (cl-tty-kit::*tick-loop-spin-window* 0)
            (cl-tty-kit::*tick-loop-sleeper*
              (lambda (seconds)
                (incf now (+ (round (* seconds units)) 2)))))
        (let ((final-state
                (tick-loop-run-realtime
                 0
                 (lambda (state) (push now starts) (1+ state))
                 (lambda (state) (declare (ignore state)) nil)
                 (lambda (state) (= state 4))
                 :stream stream
                 :interval (/ 10 units)
                 :on-timing (lambda (event tick-number value)
                              (push (list event tick-number value) timings)))))
          (expect final-state :to-be 4)
          (expect (nreverse starts) :to-equal '(0 12 22 32))
          (setf timings (nreverse timings))
          (let ((sleep-timings
                  (remove-if-not
                   (lambda (timing)
                     (eq (first timing) :deadline-sleep))
                   timings))
                (overshoot-timings
                  (remove-if-not
                   (lambda (timing)
                     (eq (first timing) :wake-overshoot))
                   timings)))
            (expect (mapcar #'second sleep-timings)
                    :to-equal '(1 2 3 4))
            (expect (mapcar #'third sleep-timings)
                    :to-equal (list 0 (/ 10 units) (/ 8 units) (/ 8 units)))
            (expect (mapcar #'second overshoot-timings)
                    :to-equal '(1 2 3 4))
            (expect (mapcar #'third overshoot-timings)
                    :to-equal (list 0 (/ 2 units) (/ 2 units) (/ 2 units))))))))
  (it "caps the spin phase at one millisecond"
    (let* ((units internal-time-units-per-second)
           (spin-limit (floor units 1000))
           (deadline (* 2 spin-limit))
           (now 0)
           (sleep-requests (list))
           (spin-windows (list)))
      (let ((cl-tty-kit::*tick-loop-clock* (lambda () now))
            (cl-tty-kit::*tick-loop-spin-window* (* 2 spin-limit))
            (cl-tty-kit::*tick-loop-sleeper*
              (lambda (seconds)
                (push seconds sleep-requests)
                (incf now (round (* seconds units)))))
            (cl-tty-kit::*tick-loop-spinner*
              (lambda (target)
                (push (- target now) spin-windows)
                (setf now target))))
        (cl-tty-kit::%tick-loop-sleep-until deadline)
        (if (plusp spin-limit)
            (progn
              (expect (nreverse sleep-requests)
                      :to-equal (list (/ spin-limit units)))
              (expect (nreverse spin-windows) :to-equal (list spin-limit)))
            (progn
              (expect sleep-requests :to-equal (list))
              (expect spin-windows :to-equal (list))))
        (expect now :to-be deadline))))
  (it "resynchronizes after a frame overrun without a catch-up burst"
    (let ((now 0)
          (starts '())
          (timings '())
          (stream (make-string-output-stream))
          (units internal-time-units-per-second))
      (let ((cl-tty-kit::*tick-loop-clock* (lambda () now))
            (cl-tty-kit::*tick-loop-spin-window* 0)
            (cl-tty-kit::*tick-loop-sleeper*
              (lambda (seconds)
                (incf now (round (* seconds units))))))
        (let ((final-state
                (tick-loop-run-realtime
                 0
                 (lambda (state)
                   (push now starts)
                   (when (zerop state)
                     (incf now 25))
                   (1+ state))
                 (lambda (state) (declare (ignore state)) nil)
                 (lambda (state) (= state 3))
                 :stream stream
                 :interval (/ 10 units)
                 :on-timing (lambda (event tick-number value)
                              (push (list event tick-number value) timings)))))
          (expect final-state :to-be 3)
          (expect (nreverse starts) :to-equal '(0 25 35))
          (setf timings (nreverse timings))
          (expect (remove-if-not
                   (lambda (timing)
                     (member (first timing) '(:deadline-miss :frame-drop)))
                   timings)
                  :to-equal
                  (list (list :deadline-miss 1 (/ 15 units))
                        (list :frame-drop 1 2)))))))
  (it "does not report skipped frames when stop terminates the loop"
    (let ((now 0)
          (timings (list))
          (stream (make-string-output-stream))
          (units internal-time-units-per-second))
      (let ((cl-tty-kit::*tick-loop-clock* (lambda () now)))
        (let ((final-state
                (tick-loop-run-realtime
                 0
                 (lambda (state)
                   (setf now 25)
                   (1+ state))
                 (lambda (state) (declare (ignore state)) nil)
                 (lambda (state)
                   (declare (ignore state))
                   t)
                 :stream stream
                 :interval (/ 10 units)
                 :on-timing (lambda (event tick-number value)
                              (push (list event tick-number value) timings)))))
          (expect final-state :to-be 1)
          (expect (remove-if-not
                   (lambda (timing)
                     (member (first timing) (list :deadline-miss :frame-drop)))
                   timings)
                  :to-equal nil))))))
