(in-package #:cl-user)

(defstruct (interactive-dashboard-state
            (:constructor make-interactive-dashboard-state
                (&key renderer decoder input-fd width height ticks events quit-p)))
  renderer
  decoder
  input-fd
  width
  height
  ticks
  events
  quit-p)

(defun interactive-dashboard-example ()
  "Render a bounded dashboard frame for the example runner.

The live version is RUN-INTERACTIVE-DASHBOARD; keeping this entry point
bounded lets documentation and CI load every example without requiring a TTY."
  (let ((screen (cl-tty-kit:make-screen 34 5 :initial-cell #\space)))
    (cl-tty-kit:screen-write-string screen 1 1 "cl-tty-kit interactive dashboard")
    (cl-tty-kit:screen-write-string screen 1 3 "Run RUN-INTERACTIVE-DASHBOARD in a TTY")
    (cl-tty-kit:render-screen screen)))

(defun %interactive-dashboard-size (fd width height)
  (multiple-value-bind (new-width new-height) (cl-tty-kit:terminal-size fd)
    (values (or new-width width) (or new-height height))))

(defun %interactive-dashboard-handle-events (state events)
  (dolist (event events)
    (push event (interactive-dashboard-state-events state))
    (when (and (eq (cl-tty-kit:key-event-type event) :character)
               (char-equal (cl-tty-kit:key-event-code event) #\q))
      (setf (interactive-dashboard-state-quit-p state) t))
    (when (and (eq (cl-tty-kit:key-event-type event) :special)
               (member (cl-tty-kit:key-event-code event) '(:escape :eof)))
      (setf (interactive-dashboard-state-quit-p state) t)))
  state)

(defun %interactive-dashboard-poll (state)
  (let ((fd (interactive-dashboard-state-input-fd state))
        (decoder (interactive-dashboard-state-decoder state))
        (buffer (make-array 4096 :element-type '(unsigned-byte 8))))
    (when (cl-tty-kit:fd-wait fd :input (/ 1.0 30))
      (loop
        (let ((count (cl-tty-kit:fd-read-octets fd buffer)))
          (cond
            ((null count) (return))
            ((zerop count)
             (setf (interactive-dashboard-state-quit-p state) t)
             (return))
            (t
             (%interactive-dashboard-handle-events
              state
               (cl-tty-kit:decode-input-chunk decoder (subseq buffer 0 count) :eof nil))))
          (unless (cl-tty-kit:fd-wait fd :input 0)
            (return)))))
    (multiple-value-bind (width height)
        (%interactive-dashboard-size fd
                                     (interactive-dashboard-state-width state)
                                     (interactive-dashboard-state-height state))
      (unless (and (= width (interactive-dashboard-state-width state))
                   (= height (interactive-dashboard-state-height state)))
        (cl-tty-kit:renderer-resize (interactive-dashboard-state-renderer state) width height)
        (setf (interactive-dashboard-state-width state) width
              (interactive-dashboard-state-height state) height)))
    state))

(defun %interactive-dashboard-advance (state)
  (incf (interactive-dashboard-state-ticks state))
  state)

(defun %interactive-dashboard-render (state stream)
  (let* ((renderer (interactive-dashboard-state-renderer state))
         (screen (cl-tty-kit:renderer-screen renderer))
         (width (cl-tty-kit:renderer-width renderer))
         (height (cl-tty-kit:renderer-height renderer)))
    (cl-tty-kit:renderer-clear renderer :cell #\space)
    (cl-tty-kit:screen-write-string screen 0 0 "cl-tty-kit  q: quit" :style '(:bold))
    (cl-tty-kit:screen-write-string screen 0 1
                         (format nil "frame ~D  size ~Dx~D"
                                 (interactive-dashboard-state-ticks state)
                                 width height))
    (cl-tty-kit:screen-write-string screen 0 2
                         (format nil "events ~D"
                                 (length (interactive-dashboard-state-events state))))
    (cl-tty-kit:renderer-render renderer :stream stream)
    stream))

(defun run-interactive-dashboard (&key (input *standard-input*)
                                       (output *standard-output*))
  "Run a small resident TUI until Q, Escape, or input EOF is received.

The loop demonstrates the production composition: scoped terminal state,
bounded readiness waits, incremental input decoding, resize-aware renderer
buffers, and direct streaming from RENDERER-RENDER."
  (let* ((input-fd (cl-tty-kit:stream-fd input))
         (width 80)
         (height 24))
    (multiple-value-setq (width height)
      (%interactive-dashboard-size input-fd width height))
    (let ((state (make-interactive-dashboard-state
                  :renderer (cl-tty-kit:make-renderer width height :initial-cell #\space)
                  :decoder (cl-tty-kit:make-input-decoder)
                  :input-fd input-fd
                  :width width
                  :height height
                  :ticks 0
                  :events nil)))
      (cl-tty-kit:with-terminal-session (session :stream output :fd input-fd :raw-mode t
                                                 :mouse :button :focus-reporting t
                                                 :disable-line-wrap t)
        (cl-tty-kit:tick-loop-run-realtime
         state
         #'%interactive-dashboard-advance
         (lambda (current-state)
           (%interactive-dashboard-render current-state session))
         #'interactive-dashboard-state-quit-p
         :stream session
         :interval (/ 1.0 30)
         :poll #'%interactive-dashboard-poll)))))
