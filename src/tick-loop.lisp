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
(defvar *tick-loop-spin-window* (/ internal-time-units-per-second 1000))

(progn
  (defconstant +tick-loop-wake-history-size+ 31)
  (defconstant +tick-loop-max-spin-window-growth+
    (floor internal-time-units-per-second 1000))
  (defconstant +tick-loop-max-spin-window-shrink+
    (max 1 (floor internal-time-units-per-second 4000)))

  (defstruct (%tick-loop-wake-estimator
              (:constructor %make-tick-loop-wake-estimator))
    minimum-window
    window
    (samples (make-array +tick-loop-wake-history-size+ :initial-element 0))
    (count 0)
    (next-index 0))

  (defun %tick-loop-make-wake-estimator (interval)
    (let* ((minimum-window
             (min interval (max 0 *tick-loop-spin-window*)))
           (estimator (%make-tick-loop-wake-estimator)))
      (setf (%tick-loop-wake-estimator-minimum-window estimator)
            minimum-window
            (%tick-loop-wake-estimator-window estimator)
            minimum-window)
      estimator))

  (defun %tick-loop-wake-p90 (estimator)
    (let* ((count (%tick-loop-wake-estimator-count estimator))
           (samples (%tick-loop-wake-estimator-samples estimator))
           (ordered (make-array count)))
      (dotimes (index count)
        (setf (aref ordered index) (aref samples index)))
      (aref (sort ordered #'<)
            (1- (ceiling (* count 9) 10)))))

  (defun %tick-loop-observe-sleep-wake (estimator overshoot interval)
    (let* ((samples (%tick-loop-wake-estimator-samples estimator))
           (index (%tick-loop-wake-estimator-next-index estimator)))
      (setf (aref samples index) (max 0 overshoot)
            (%tick-loop-wake-estimator-count estimator)
            (min +tick-loop-wake-history-size+
                 (1+ (%tick-loop-wake-estimator-count estimator)))
            (%tick-loop-wake-estimator-next-index estimator)
            (mod (1+ index) +tick-loop-wake-history-size+))
      (let* ((target
               (min interval
                    (max (%tick-loop-wake-estimator-minimum-window estimator)
                         (%tick-loop-wake-p90 estimator))))
             (current
               (min interval (%tick-loop-wake-estimator-window estimator)))
             (window
               (cond
                 ((> target current)
                  (min target
                       (+ current +tick-loop-max-spin-window-growth+)))
                 ((< target current)
                  (max target
                       (- current +tick-loop-max-spin-window-shrink+)))
                 (t current))))
        (setf (%tick-loop-wake-estimator-window estimator) window)
        window))))

(defun %tick-loop-now ()
  (funcall *tick-loop-clock*))
(defun %tick-loop-spin-until (deadline)
  (loop while (< (%tick-loop-now) deadline)
        do (progn)))
(defvar *tick-loop-spinner* (function %tick-loop-spin-until))

(progn
  (defvar *tick-loop-qos-getter* nil)
  (defvar *tick-loop-qos-setter* nil)
  (defvar *tick-loop-qos-warning-issued-p* nil)
  (defvar *tick-loop-qos-warning-lock*
    #+sb-thread (sb-thread:make-mutex :name "tick-loop QoS warning")
    #-sb-thread nil)

  (defun %tick-loop-warn-qos-failure-once (operation failure)
    (flet ((report ()
             (unless *tick-loop-qos-warning-issued-p*
               (setf *tick-loop-qos-warning-issued-p* t)
               (warn "Could not ~A the tick-loop thread QoS; continuing without the QoS optimization (~A)."
                     operation failure))))
      #+sb-thread
      (sb-thread:with-mutex (*tick-loop-qos-warning-lock*)
        (report))
      #-sb-thread
      (report)))

  (defun %tick-loop-try-get-qos ()
    (handler-case
        (multiple-value-bind (status qos relative-priority)
            (funcall *tick-loop-qos-getter*)
          (if (zerop status)
              (values t qos relative-priority nil)
              (values nil nil nil status)))
      (error (condition)
        (values nil nil nil condition))))

  (defun %tick-loop-try-set-qos (qos relative-priority)
    (handler-case
        (let ((status (funcall *tick-loop-qos-setter* qos relative-priority)))
          (unless (zerop status)
            status))
      (error (condition)
        condition)))

  (defun %tick-loop-call-with-user-interactive-qos (body)
    (if (and *tick-loop-qos-getter* *tick-loop-qos-setter*)
        (multiple-value-bind (read-p qos relative-priority failure)
            (%tick-loop-try-get-qos)
          (cond
            ((not read-p)
             (%tick-loop-warn-qos-failure-once "read" failure)
             (funcall body))
            ((and (= qos #x21) (zerop relative-priority))
             (funcall body))
            (t
             (let ((restore-qos (if (zerop qos) #x15 qos))
                   (restore-relative-priority
                     (if (zerop qos) 0 relative-priority)))
               (let ((failure (%tick-loop-try-set-qos #x21 0)))
                 (if failure
                     (progn
                       (%tick-loop-warn-qos-failure-once "raise" failure)
                       (funcall body))
                     (unwind-protect
                          (funcall body)
                       ;; pthread_set_qos_class_self_np cannot restore UNSPECIFIED.
                       (let ((failure
                               (%tick-loop-try-set-qos
                                restore-qos restore-relative-priority)))
                         (when failure
                           (%tick-loop-warn-qos-failure-once "restore" failure))))))))))
        (funcall body)))

  #+(and sbcl darwin)
  (progn
    ;; macOS qos_class_t values: USER_INTERACTIVE is 0x21 and DEFAULT is 0x15.
    (sb-alien:define-alien-routine ("pthread_self" %tick-loop-pthread-self)
        sb-alien:system-area-pointer)
    (sb-alien:define-alien-routine
        ("pthread_get_qos_class_np" %tick-loop-pthread-get-qos-class)
        sb-alien:int
      (thread sb-alien:system-area-pointer)
      (qos (* sb-alien:unsigned-int))
      (relative-priority (* sb-alien:int)))
    (sb-alien:define-alien-routine
        ("pthread_set_qos_class_self_np" %tick-loop-pthread-set-qos-class)
        sb-alien:int
      (qos sb-alien:unsigned-int)
      (relative-priority sb-alien:int))
    (defun %tick-loop-get-qos ()
      (sb-alien:with-alien ((qos sb-alien:unsigned-int)
                            (relative-priority sb-alien:int))
        (values (%tick-loop-pthread-get-qos-class
                 (%tick-loop-pthread-self)
                 (sb-alien:addr qos)
                 (sb-alien:addr relative-priority))
                qos relative-priority)))
    (defun %tick-loop-set-qos (qos relative-priority)
      (%tick-loop-pthread-set-qos-class qos relative-priority))
    (setf *tick-loop-qos-getter* #'%tick-loop-get-qos
          *tick-loop-qos-setter* #'%tick-loop-set-qos))

  (defmacro %with-tick-loop-user-interactive-qos (&body body)
    `(if (and *tick-loop-qos-getter* *tick-loop-qos-setter*)
         (%tick-loop-call-with-user-interactive-qos (lambda () ,@body))
         (progn ,@body))))

(defun %tick-loop-sleep-until (deadline estimator interval)
  (let* ((spin-window
           (min interval
                (max 0 (%tick-loop-wake-estimator-window estimator))))
         (observed-overshoot nil)
         (wake-time nil))
    (%with-tick-loop-user-interactive-qos
      (loop for remaining = (- deadline (%tick-loop-now))
            while (> remaining spin-window)
            do (let* ((sleep-start (%tick-loop-now))
                      (sleep-target (- deadline spin-window))
                      (sleep-request (max 0 (- sleep-target sleep-start))))
                 (when (plusp sleep-request)
                   (funcall *tick-loop-sleeper*
                            (/ sleep-request
                               internal-time-units-per-second))
                   (let ((overshoot (max 0 (- (%tick-loop-now) sleep-target))))
                     (setf observed-overshoot
                           (if observed-overshoot
                               (max observed-overshoot overshoot)
                               overshoot))))))
      (when (< (%tick-loop-now) deadline)
        (loop while (< (%tick-loop-now) deadline)
              do (funcall *tick-loop-spinner* deadline)))
      (setf wake-time (%tick-loop-now)))
    (when observed-overshoot
      (%tick-loop-observe-sleep-wake estimator observed-overshoot interval))
    (values spin-window observed-overshoot wake-time)))

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
time rather than producing a burst of catch-up frames. The spin window starts
at *TICK-LOOP-SPIN-WINDOW* (1 ms by default) and adapts toward the p90 of recent
sleep wake overshoot. It grows by at most 1 ms or shrinks by at most 0.25 ms per
observed sleep, and is capped at the tick interval. On SBCL/macOS, the current
thread temporarily requests USER_INTERACTIVE QoS during deadline waiting and
restores its prior QoS class afterward; an unspecified prior class is restored
as QOS_CLASS_DEFAULT. Other platforms use the normal thread QoS. STOP is
checked after each tick is advanced and rendered, so the loop always emits the
frame that caused it to stop before returning.

ON-TIMING, when supplied, is called as (FUNCALL ON-TIMING EVENT TICK-NUMBER
VALUE); TICK-NUMBER is one-based. The :ADVANCE, :RENDER, :WRITE-STRING,
:FINISH-OUTPUT, :DEADLINE-SLEEP, :WAKE-OVERSHOOT, :SPIN-WINDOW, and
:SLEEP-WAKE-OVERSHOOT events report seconds. The deadline-sleep value is elapsed
wait up to the scheduled deadline; wake-overshoot is excess time after that
deadline. Spin-window reports the window used for that tick. Sleep-wake-overshoot
reports the greatest excess over a requested sleep wake time when the sleeper
ran. Deadline-sleep and wake-overshoot are reported on every tick, including
zero values. Write-string and finish-output are reported only when those
operations run. A render function that writes directly to STREAM includes that
work in :RENDER and emits no :WRITE-STRING; :FINISH-OUTPUT is still reported
when the loop flushes. When completed tick work passes its next scheduled
deadline, :DEADLINE-MISS reports lateness in seconds and :FRAME-DROP reports
the integer number of scheduled tick slots skipped by resynchronization.
ON-TIMING is disabled by default. The callback runs after each measured
operation returns, without an internal lock held, and its errors propagate."
  (%assert-tick-loop-function :advance advance)
  (%assert-tick-loop-function :render render)
  (%assert-tick-loop-function :stop stop)
  (%assert-tick-loop-optional-function :poll poll)
  (%assert-tick-loop-optional-function :on-timing on-timing)
  (%assert-tick-loop-interval interval)
  (let* ((interval-units (* interval internal-time-units-per-second))
         (wake-estimator (%tick-loop-make-wake-estimator interval-units))
         (next-deadline (%tick-loop-now))
         (tick-number 0))
    (loop
      (incf tick-number)
      (let ((sleep-start (when on-timing (%tick-loop-now))))
        (multiple-value-bind (spin-window sleep-wake-overshoot wake-time)
            (%tick-loop-sleep-until next-deadline wake-estimator interval-units)
          (when on-timing
            (let* ((deadline-wait
                     (max 0 (min (- wake-time sleep-start)
                                 (- next-deadline sleep-start))))
                   (wake-overshoot (max 0 (- wake-time next-deadline))))
              (funcall on-timing :deadline-sleep tick-number
                       (/ deadline-wait internal-time-units-per-second))
              (funcall on-timing :wake-overshoot tick-number
                       (/ wake-overshoot internal-time-units-per-second))
              (funcall on-timing :spin-window tick-number
                       (/ spin-window internal-time-units-per-second))
              (when sleep-wake-overshoot
                (funcall on-timing :sleep-wake-overshoot tick-number
                         (/ sleep-wake-overshoot
                            internal-time-units-per-second))))))
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
