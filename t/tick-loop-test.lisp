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
    (let ((stream (make-string-output-stream)))
      (let ((final-state
              (tick-loop-run-realtime
               0
               #'1+
               (lambda (state) (format nil "<~D>" state))
               (lambda (state) (>= state 3))
               :stream stream
               :interval 1/1000)))
        (expect final-state :to-be 3)
        (expect (get-output-stream-string stream) :to-equal "<1><2><3>"))))
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
                             :interval 0))))
