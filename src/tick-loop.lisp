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

(defmacro %tick-loop-advance (state advance render)
  "Run one tick and return (VALUES NEW-STATE FRAME OUTPUT-WRITTEN-P
OUTPUT-KNOWN-P). RENDER (if supplied) receives the next state. Both TICK-LOOP-RUN and
TICK-LOOP-RUN-REALTIME call this for every tick, so the two modes can never
disagree about what a tick does."
  `(let ((state ,state) (advance ,advance) (render ,render))
     (let ((new-state (funcall advance state)))
       (if render
           (multiple-value-bind (frame output-written-p output-known-p)
               (funcall render new-state)
             (values new-state frame output-written-p output-known-p))
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

(defmacro %tick-loop-sleep-remainder (tick-start-time interval)
  "Sleep the portion of INTERVAL seconds not already spent since
TICK-START-TIME (an INTERNAL-TIME-UNITS-PER-SECOND-scaled timestamp), so a
slow tick shortens the following sleep instead of accumulating drift across
many frames. A tick that already ran longer than INTERVAL sleeps not at all."
  `(let* ((tick-start-time ,tick-start-time)
          (interval ,interval)
          (elapsed (/ (- (get-internal-real-time) tick-start-time)
                      internal-time-units-per-second))
          (remaining (- interval elapsed)))
     (when (plusp remaining)
       (sleep remaining))))

(defun tick-loop-run-realtime (state advance render stop
                               &key (stream *standard-output*) (interval 1/30)
                                 poll)
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
state contract. STOP is a
function of one argument (the current state) returning true once the loop
should quit (e.g. a quit-key flag an ADVANCE function set from a decoded
KEY-EVENT). INTERVAL is the target seconds between ticks (default 1/30);
%TICK-LOOP-SLEEP-REMAINDER holds that pace without drifting when a tick runs
long. STOP is checked after each tick is advanced and rendered, so the loop
always emits the frame that caused it to stop before returning."
  (%assert-tick-loop-function :advance advance)
  (%assert-tick-loop-function :render render)
  (%assert-tick-loop-function :stop stop)
  (%assert-tick-loop-optional-function :poll poll)
  (%assert-tick-loop-interval interval)
  (loop
    (let ((tick-start-time (get-internal-real-time)))
      (when poll
        (setf state (funcall poll state)))
      (multiple-value-bind (new-state frame output-written-p output-known-p)
          (%tick-loop-advance state advance render)
        (setf state new-state)
        (let ((wrote-output-p
                (cond
                  ((null frame) nil)
                  ((eq frame stream)
                   (if output-known-p output-written-p t))
                  (t
                   (write-string frame stream)
                   (plusp (length frame))))))
          (when wrote-output-p
            (finish-output stream)))
        (when (funcall stop state)
          (return state))
        (%tick-loop-sleep-remainder tick-start-time interval)))))
