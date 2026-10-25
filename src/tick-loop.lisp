(in-package #:cl-tty-kit)

(define-simple-assert %assert-tick-loop-function (name value)
  (functionp value)
  "Tick loop ~A ~S must be a function." name value)

(define-simple-assert %assert-tick-loop-optional-function (name value)
  (or (null value) (functionp value))
  "Tick loop ~A ~S must be NIL or a function." name value)

(define-simple-assert %assert-tick-loop-ticks (ticks)
  (and (integerp ticks) (>= ticks 0))
  "Tick count ~S must be a non-negative integer." ticks)

(define-simple-assert %assert-tick-loop-interval (interval)
  (and (realp interval) (plusp interval))
  "Tick interval ~S must be a positive real number of seconds." interval)

(defmacro %tick-loop-advance (state advance render
                              &optional on-timing tick-number)
  "Run one tick and return (VALUES NEW-STATE FRAME OUTPUT-WRITTEN-P
OUTPUT-KNOWN-P). RENDER (if supplied) receives the next state. Both TICK-LOOP-RUN and
TICK-LOOP-RUN-REALTIME call this for every tick, so the two modes can never
disagree about what a tick does. When ON-TIMING is supplied, report ADVANCE
and RENDER durations after each call."
  `(let ((state ,state)
         (advance ,advance)
         (render ,render)
         (on-timing ,on-timing)
         (tick-number ,tick-number))
     (let* ((advance-start (when on-timing (%tick-loop-now)))
            (new-state (funcall advance state))
            (advance-end (when on-timing (%tick-loop-now))))
       (when on-timing
         (funcall on-timing :advance tick-number
                  (/ (- advance-end advance-start)
                     internal-time-units-per-second)))
       (if render
           (let ((render-start (when on-timing (%tick-loop-now))))
             (multiple-value-bind (frame output-written-p output-known-p)
                 (funcall render new-state)
               (let ((render-end (when on-timing (%tick-loop-now))))
                 (when on-timing
                   (funcall on-timing :render tick-number
                            (/ (- render-end render-start)
                               internal-time-units-per-second)))
                 (values new-state frame output-written-p output-known-p))))
           (values new-state nil nil t)))))

(defun tick-loop-run (state advance ticks &key render)
  "Call ADVANCE on STATE exactly TICKS times, threading each result into the
next call, and return (VALUES FINAL-STATE FRAMES).

ADVANCE is a function of one argument (the current state) returning the next
state; it must be pure enough to make repeated runs with the same STATE and
TICKS reproducible, since this is the mode a downstream app's tests rely on
for determinism. RENDER, when supplied, is a function of one argument (a
state) returning a frame (typically a string from RENDER-SCREEN or
RENDER-DIFF); FRAMES is the list of its results in tick order, or NIL when
RENDER is not supplied. A TICKS of 0 performs no ADVANCE calls and returns
STATE unchanged with an empty FRAMES list."
  (%assert-tick-loop-function :advance advance)
  (%assert-tick-loop-optional-function :render render)
  (%assert-tick-loop-ticks ticks)
  (let ((frames '()))
    (dotimes (i ticks)
      (multiple-value-bind (new-state frame) (%tick-loop-advance state advance render)
        (setf state new-state)
        (when render
          (push frame frames))))
    (values state (nreverse frames))))

;; Internal bindings make deadline behavior deterministic in tests without
;; adding clock injection to the public tick-loop API.
(defvar *tick-loop-clock* (function get-internal-real-time))
(defvar *tick-loop-sleeper* (function sleep))

(defun %tick-loop-now ()
  (funcall *tick-loop-clock*))

(defun %tick-loop-sleep-until (deadline)
  (let ((remaining (/ (- deadline (%tick-loop-now))
                      internal-time-units-per-second)))
    (when (plusp remaining)
      (funcall *tick-loop-sleeper* remaining))))

(defun tick-loop-run-realtime (state advance render stop
                               &key (stream *standard-output*) (interval 1/30)
                                 poll on-timing)
  "Repeatedly advance STATE via ADVANCE (as TICK-LOOP-RUN does), writing each
tick's (FUNCALL RENDER STATE) to STREAM, until (FUNCALL STOP STATE) is true.
Returns the final state.

ADVANCE and RENDER have the same contract as in TICK-LOOP-RUN; RENDER is
mandatory here since a real-time loop exists to produce output. RENDER may
return NIL to suppress a frame, or return STREAM when it wrote the frame
directly to STREAM. In the latter form, the second and third return values may
be used to explicitly report whether output was written and whether that fact
is known. POLL, when supplied, is called with the current state before each
advance and its return value is threaded into ADVANCE's existing one-argument
state contract. STOP is a function of one argument (the current state)
returning true once the loop should quit (e.g. a quit-key flag an ADVANCE
function set from a decoded KEY-EVENT). INTERVAL is the target seconds between
ticks (default 1/30). Pacing uses monotonic internal-time deadlines, so
scheduler wake overshoot does not accumulate as drift. If a frame finishes
past the next deadline, the loop resynchronizes that deadline to the current
time rather than producing a burst of catch-up frames. STOP is checked after
each tick is advanced and rendered, so the loop always emits the frame that
caused it to stop before returning.

ON-TIMING, when supplied, is called as (FUNCALL ON-TIMING EVENT TICK-NUMBER
VALUE); TICK-NUMBER is one-based. The :ADVANCE, :RENDER, :WRITE-STRING,
:FINISH-OUTPUT, :DEADLINE-SLEEP, and :WAKE-OVERSHOOT events report seconds.
The deadline-sleep value is elapsed wait up to the scheduled deadline;
wake-overshoot is excess time after that deadline. Deadline-sleep and
wake-overshoot are reported on every tick, including zero values. Write-string
and finish-output are reported only when those operations run. A render function
that writes directly to STREAM includes that work in :RENDER and emits no
:WRITE-STRING; :FINISH-OUTPUT is still reported when the loop flushes. When completed
tick work passes its next scheduled deadline, :DEADLINE-MISS reports lateness
in seconds and :FRAME-DROP reports the integer number of scheduled tick slots
skipped by resynchronization. ON-TIMING is disabled by default. The callback
runs after each measured operation returns, without an internal lock held, and
its errors propagate."
  (%assert-tick-loop-function :advance advance)
  (%assert-tick-loop-function :render render)
  (%assert-tick-loop-function :stop stop)
  (%assert-tick-loop-optional-function :poll poll)
  (%assert-tick-loop-optional-function :on-timing on-timing)
  (%assert-tick-loop-interval interval)
  (let ((next-deadline (%tick-loop-now))
        (tick-number 0))
    (loop
      (incf tick-number)
      (let ((sleep-start (when on-timing (%tick-loop-now))))
        (%tick-loop-sleep-until next-deadline)
        (when on-timing
          (let* ((wake-time (%tick-loop-now))
                 (deadline-wait
                   (max 0 (min (- wake-time sleep-start)
                               (- next-deadline sleep-start))))
                 (wake-overshoot (max 0 (- wake-time next-deadline))))
            (funcall on-timing :deadline-sleep tick-number
                     (/ deadline-wait internal-time-units-per-second))
            (funcall on-timing :wake-overshoot tick-number
                     (/ wake-overshoot internal-time-units-per-second))))
      (when poll
        (setf state (funcall poll state)))
      (multiple-value-bind (new-state frame output-written-p output-known-p)
          (%tick-loop-advance state advance render on-timing tick-number)
        (setf state new-state)
        (let ((wrote-output-p
                (cond
                  ((null frame) nil)
                  ((eq frame stream)
                   (if output-known-p output-written-p t))
                  (t
                   (if on-timing
                       (let ((write-start (%tick-loop-now)))
                         (write-string frame stream)
                         (funcall on-timing :write-string tick-number
                                  (/ (- (%tick-loop-now) write-start)
                                     internal-time-units-per-second)))
                       (write-string frame stream))
                   (plusp (length frame))))))
          (when wrote-output-p
            (if on-timing
                (let ((flush-start (%tick-loop-now)))
                  (finish-output stream)
                  (funcall on-timing :finish-output tick-number
                           (/ (- (%tick-loop-now) flush-start)
                              internal-time-units-per-second)))
                (finish-output stream)))))
      (let ((stop-p (funcall stop state)))
        (when (not stop-p)
          (incf next-deadline (* interval internal-time-units-per-second))
          (let ((now (%tick-loop-now)))
            (when (> now next-deadline)
              (when on-timing
                (let* ((lateness (- now next-deadline))
                       (frame-slots-skipped
                         (ceiling lateness
                                  (* interval internal-time-units-per-second))))
                  (funcall on-timing :deadline-miss tick-number
                           (/ lateness internal-time-units-per-second))
                  (funcall on-timing :frame-drop tick-number
                           frame-slots-skipped)))
              (setf next-deadline now))))
        (when stop-p
          (return state)))))))
