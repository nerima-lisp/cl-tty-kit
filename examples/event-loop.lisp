(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defparameter +event-loop-demo-chunks+
  '("j"
    #.(string #\Esc)
    "[A"
    #.(concatenate 'string (string #\Esc) "[200~he")
    "llo"
    #.(concatenate 'string (string #\Esc) "[201~q")))

(defstruct event-loop-state
  count
  donep
  last-event
  previous-screen
  previous-cursor)

(defun event-loop-example-events ()
  (let ((decoder (cl-tty-kit:make-input-decoder :collect-bracketed-paste t))
        (events '()))
    (dolist (chunk +event-loop-demo-chunks+)
      (setf events
            (nconc events
                   (copy-list (cl-tty-kit:decode-input-chunk decoder chunk)))))
    (nconc events
           (copy-list (cl-tty-kit:flush-input-decoder decoder)))))

(defun %event-loop-event-label (event)
  (case (cl-tty-kit:key-event-type event)
    (:character
     (format nil "char ~C" (cl-tty-kit:key-event-code event)))
    (:paste
     (format nil "paste ~D bytes" (length (cl-tty-kit:key-event-code event))))
    (t
     (string-downcase (symbol-name (cl-tty-kit:key-event-code event))))))

(defun %event-loop-apply-event (count event)
  (case (cl-tty-kit:key-event-type event)
    (:character
     (case (cl-tty-kit:key-event-code event)
       (#\j (values (1+ count) nil))
       (#\q (values count t))
       (otherwise (values count nil))))
    (:paste
     (values (+ count (length (cl-tty-kit:key-event-code event))) nil))
    (:special
     (case (cl-tty-kit:key-event-code event)
       (:up (values (1+ count) nil))
       (otherwise (values count nil))))
    (t
     (values count nil))))

(defun %event-loop-render-frame (state stream)
  (let* ((screen (%event-loop-screen (event-loop-state-count state)
                                     (event-loop-state-last-event state)
                                     (event-loop-state-donep state)))
         (cursor (cl-tty-kit:make-cursor
                  :x (+ 7 (length (write-to-string (event-loop-state-count state))))
                  :y 3
                  :visible (not (event-loop-state-donep state)))))
    (write-string
     (if (event-loop-state-previous-screen state)
         (cl-tty-kit:render-frame-diff
          screen
          (event-loop-state-previous-screen state)
          cursor
          :previous-cursor (event-loop-state-previous-cursor state))
         (cl-tty-kit:render-frame screen cursor))
     stream)
    (setf (event-loop-state-previous-screen state) screen
          (event-loop-state-previous-cursor state) cursor)
    state))

(defun %event-loop-advance (state event)
  (multiple-value-bind (count donep)
      (%event-loop-apply-event (event-loop-state-count state) event)
    (setf (event-loop-state-count state) count
          (event-loop-state-donep state) donep
          (event-loop-state-last-event state)
          (%event-loop-event-label event))
    state))

(defun %event-loop-screen (count last-event donep)
  (let ((screen (cl-tty-kit:make-screen 34 6)))
    (cl-tty-kit:screen-write-string screen 0 0 "TTY loop demo" :style '(:bold))
    (cl-tty-kit:screen-write-string screen 0 1 "j / Up: increment")
    (cl-tty-kit:screen-write-string screen 0 2 "paste: add payload length")
    (cl-tty-kit:screen-write-string screen 0 3 (format nil "count: ~D" count))
    (cl-tty-kit:screen-write-string screen 0 4 (format nil "last: ~A" last-event))
    (cl-tty-kit:screen-write-string screen 0 5 (if donep
                                                   "state: stopping"
                                                   "state: running"))
    screen))

(defun event-loop-example ()
  (let ((state (make-event-loop-state :count 0
                                      :donep nil
                                      :last-event "waiting")))
    (cl-tty-kit:with-terminal-session-output (stream :stream stream
                                                      :bracketed-paste t
                                                      :keyboard-enhancements 1)
      (%event-loop-render-frame state stream)
      (dolist (event (event-loop-example-events))
        (%event-loop-advance state event)
        (%event-loop-render-frame state stream)))))

(defun run-event-loop-example ()
  (format t "~A~%" (event-loop-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-event-loop-example))
