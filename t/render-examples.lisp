(in-package #:cl-tty-kit/test)

(defun %quick-start-output ()
  (let ((screen (make-screen 20 4)))
    (screen-put-cell screen 0 0 #\H)
    (screen-put-cell screen 1 0 #\i)
    (render-screen screen)))

(defun %status-dashboard-screen (status jobs)
  (let ((screen (make-screen 28 5)))
    (screen-write-string screen 0 0 "TTY monitor" :style '(:bold))
    (screen-write-string screen 0 2 "status:")
    (screen-write-string screen 8 2 status :style '(:bold))
    (screen-write-string screen 0 3 "jobs:")
    (screen-write-string screen 6 3 jobs)
    screen))

(defun %status-dashboard-output ()
  (let* ((frame-1 (%status-dashboard-screen "warming" "parse, render"))
         (frame-2 (%status-dashboard-screen "ready" "parse, render, io"))
         (frame-3 (%status-dashboard-screen "ready" "parse, render, io"))
         (cursor-1 (make-cursor :x 14 :y 2 :visible nil))
         (cursor-2 (make-cursor :x 22 :y 3))
         (cursor-3 (make-cursor :x 15 :y 4)))
    (screen-write-string frame-3 0 4 "press q to quit")
    (with-terminal-session-output (stream :stream stream)
      (write-string (render-frame frame-1 cursor-1) stream)
      (write-string
       (render-frame-diff frame-2 frame-1 cursor-2
                          :previous-cursor cursor-1)
       stream)
      (write-string
       (render-frame-diff frame-3 frame-2 cursor-3
                          :previous-cursor cursor-2)
       stream))))

(defun %event-loop-screen (count last-event donep)
  (let ((screen (make-screen 34 6)))
    (screen-write-string screen 0 0 "TTY loop demo" :style '(:bold))
    (screen-write-string screen 0 1 "j / Up: increment")
    (screen-write-string screen 0 2 "paste: add payload length")
    (screen-write-string screen 0 3 (format nil "count: ~D" count))
    (screen-write-string screen 0 4 (format nil "last: ~A" last-event))
    (screen-write-string screen 0 5 (if donep
                                       "state: stopping"
                                       "state: running"))
    screen))

(defun %event-loop-output ()
  (let ((count 0)
        (donep nil)
        (last-event "waiting")
        (previous-screen nil)
        (previous-cursor nil))
    (flet ((event-label (event)
             (case (key-event-type event)
               (:character
                (format nil "char ~C" (key-event-code event)))
               (:paste
                (format nil "paste ~D bytes" (length (key-event-code event))))
               (t
                (string-downcase (symbol-name (key-event-code event))))))
           (apply-event (event)
             (case (key-event-type event)
               (:character
                (case (key-event-code event)
                  (#\j (incf count))
                  (#\q (setf donep t))))
               (:paste
                (incf count (length (key-event-code event))))
               (:special
                (case (key-event-code event)
                  (:up (incf count)))))))
      (with-terminal-session-output (stream :stream stream
                                              :bracketed-paste t
                                              :keyboard-enhancements 1)
        (labels ((emit-frame ()
                   (let* ((screen (%event-loop-screen count last-event donep))
                          (cursor (make-cursor :x (+ 7 (length (write-to-string count)))
                                               :y 3
                                               :visible (not donep))))
                     (write-string
                      (if previous-screen
                          (render-frame-diff screen previous-screen cursor
                                             :previous-cursor previous-cursor)
                          (render-frame screen cursor))
                      stream)
                     (setf previous-screen screen
                           previous-cursor cursor))))
          (emit-frame)
          (load-example-symbol "examples/event-loop.lisp")
          (dolist (event (funcall (symbol-function
                                   (find-symbol "EVENT-LOOP-EXAMPLE-EVENTS"
                                                :cl-user))))
            (apply-event event)
            (setf last-event (event-label event))
            (emit-frame)))))))

(defun %quick-start-expected-output ()
  (concatenate 'string
               (ansi-clear-screen)
               (ansi-move-cursor 1 1)
               "Hi"
               (make-string 18 :initial-element #\Space)
               (string #\Newline)
               (make-string 20 :initial-element #\Space)
               (string #\Newline)
               (make-string 20 :initial-element #\Space)
               (string #\Newline)
               (make-string 20 :initial-element #\Space)))

(defun %simple-render-expected-output ()
  (concatenate 'string
               (ansi-clear-screen)
               (ansi-move-cursor 1 1)
               "Hi"
               (make-string 18 :initial-element #\Space)
               (string #\Newline)
               "!"
               (make-string 19 :initial-element #\Space)
               (string #\Newline)
               (make-string 20 :initial-element #\Space)))

(defun %styled-render-expected-output ()
  (concatenate 'string
               (ansi-move-cursor 1 1)
               (format nil "~C[1;38;5;196m" #\Esc)
               "H"
               (ansi-reset-style)
               (format nil "~C[38;5;33m" #\Esc)
               "i"
               (ansi-reset-style)
               (ansi-move-cursor 2 1)
               (format nil "~C[4;48;5;17m" #\Esc)
               "!"
               (ansi-reset-style)))

(defun %frame-render-expected-output ()
  (concatenate 'string
               (ansi-move-cursor 1 1)
               "Hi"
               (ansi-move-cursor 2 1)
               "!"
               (ansi-move-cursor 2 3)
               (ansi-show-cursor)))

(defun %screen-update-expected-output ()
  (concatenate 'string
               (ansi-move-cursor 1 1)
               "Hi"
               (ansi-move-cursor 2 1)
               "!"))

(defun %terminal-session-expected-output ()
  (concatenate 'string
               (ansi-enter-alternate-screen)
               (ansi-hide-cursor)
               (ansi-enable-bracketed-paste)
               (ansi-push-keyboard-enhancements 1)
               (ansi-clear-screen)
               (ansi-move-cursor 1 1)
               (ansi-bold)
               "T"
               (ansi-reset-style)
               (ansi-bold)
               "T"
               (ansi-reset-style)
               (ansi-bold)
               "Y"
               (ansi-reset-style)
               " demo"
               (make-string 10 :initial-element #\Space)
               (string #\Newline)
               "Press q to exit"
               (make-string 3 :initial-element #\Space)
               (string #\Newline)
               (make-string 18 :initial-element #\Space)
               (ansi-pop-keyboard-enhancements)
               (ansi-disable-bracketed-paste)
               (ansi-show-cursor)
               (ansi-exit-alternate-screen)))

(defparameter +render-example-cases+
  '(("examples/simple-render.lisp" . %simple-render-expected-output)
    ("examples/styled-render.lisp" . %styled-render-expected-output)
    ("examples/frame-render.lisp" . %frame-render-expected-output)
    ("examples/screen-update.lisp" . %screen-update-expected-output)
    ("examples/status-dashboard.lisp" . %status-dashboard-output)
    ("examples/event-loop.lisp" . %event-loop-output)))

(defun %assert-example-renders (file expected-output)
  (let ((example (symbol-function (load-example-symbol file))))
    (is (string= (funcall example) expected-output)
        (format nil "~A should render the documented output" file))))

(defun test-render-examples ()
  (let ((screen (make-screen 2 1)))
    (screen-put-cell screen 0 0 #\H)
    (screen-put-cell screen 1 0 #\i)
    (let ((output (render-screen screen)))
      (is (search "Hi" output))
      (is (search (ansi-clear-screen) output)))
    (is (string= (%quick-start-output)
                 (%quick-start-expected-output)))
    (do-test-case-bind
        (example-case +render-example-cases+ (file expected-output-fn))
      (%assert-example-renders file (funcall expected-output-fn))))
  (let ((example (symbol-function
                  (load-example-symbol "examples/terminal-session.lisp"))))
    (is (string= (with-output-to-string (out)
                   (funcall example out))
                 (%terminal-session-expected-output))))
  t)
