(in-package #:cl-tty-kit/test)

(defmacro %capture-terminal-session-output ((&rest session-options)
                                            &body body)
  `(with-output-to-string (stream)
     (with-terminal-session (stream :stream stream ,@session-options)
       ,@body)))

(defun %terminal-session-expected-output (&key (body "")
                                               (alternate-screen t)
                                               (hide-cursor t)
                                               (bracketed-paste nil)
                                               keyboard-enhancements)
  (concatenate 'string
               (if alternate-screen
                   (ansi-enter-alternate-screen)
                   "")
               (if hide-cursor
                   (ansi-hide-cursor)
                   "")
               (if bracketed-paste
                   (ansi-enable-bracketed-paste)
                   "")
               (if keyboard-enhancements
                   (ansi-push-keyboard-enhancements keyboard-enhancements)
                   "")
               body
               (if keyboard-enhancements
                   (ansi-pop-keyboard-enhancements)
                   "")
               (if bracketed-paste
                   (ansi-disable-bracketed-paste)
                   "")
               (if hide-cursor
                   (ansi-show-cursor)
                   "")
               (if alternate-screen
                   (ansi-exit-alternate-screen)
                   "")))

(defun %expect-terminal-session-output (output &key (body "")
                                                 (alternate-screen t)
                                                 (hide-cursor t)
                                                 (bracketed-paste nil)
                                                 keyboard-enhancements)
  (expect output
          :to-equal
          (%terminal-session-expected-output :body body
                                             :alternate-screen alternate-screen
                                             :hide-cursor hide-cursor
                                             :bracketed-paste bracketed-paste
                                             :keyboard-enhancements keyboard-enhancements)))

(defvar *terminal-size-synonym-target* nil
  "A dynamically rebindable target for exercising %STREAM-FD's SYNONYM-STREAM
case below.")

(describe "terminal-size"
  (it "reports either a real size or NIL/NIL, never an error, when FD 0 is not a tty"
    ;; Under the test harness FD 0 is usually not a tty, so TERMINAL-SIZE either
    ;; reports the real size (two positive integers) or NIL/NIL -- never an error.
    (multiple-value-bind (columns rows) (terminal-size)
      (expect (or (and (null columns) (null rows))
                  (and (integerp columns) (plusp columns)
                       (integerp rows) (plusp rows))))))
  (it "rejects an invalid descriptor as a programmer error"
    (expect (lambda () (terminal-size -1)) :to-throw)
    (expect (lambda () (terminal-size "fd")) :to-throw))
  (it "reports size unavailable for an FD that overflows the ioctl's C int, rather than erroring"
    ;; An FD that passes %ASSERT-TERMINAL-FD's own validation (a non-negative
    ;; integer) but overflows the C int SB-UNIX:UNIX-IOCTL marshals it into
    ;; raises a genuine Lisp error at the FFI boundary -- distinct from an
    ;; ordinary ioctl failure (e.g. a closed FD), which UNIX-IOCTL reports by
    ;; returning NIL, not by signaling. TERMINAL-SIZE/%SET-TERMINAL-SIZE catch
    ;; that error too, reporting it the same as "size unavailable".
    (expect (multiple-value-list (terminal-size (expt 2 40))) :to-equal '(nil nil))
    (expect (cl-tty-kit::%set-terminal-size (expt 2 40) 80 24) :to-be-falsy))
  (it "reports size unavailable for an unrecognized platform (no known ioctl constant)"
    ;; +TIOCGWINSZ+/+TIOCSWINSZ+ are ordinary special variables, so this is
    ;; exercised directly by rebinding them to NIL.
    (let ((cl-tty-kit::+tiocgwinsz+ nil))
      (expect (multiple-value-list (terminal-size)) :to-equal '(nil nil)))
    (let ((cl-tty-kit::+tiocswinsz+ nil))
      (expect (cl-tty-kit::%set-terminal-size 0 80 24) :to-be-falsy)))
  (it "unwraps a TWO-WAY-STREAM or SYNONYM-STREAM to the underlying fd, like a PTY's bidirectional stream"
    (let ((two-way (make-two-way-stream *standard-input* *standard-output*)))
      (expect (cl-tty-kit::%stream-fd two-way)
              :to-be (cl-tty-kit::%stream-fd *standard-output*)))
    (let ((*terminal-size-synonym-target* *standard-output*))
      (expect (cl-tty-kit::%stream-fd (make-synonym-stream '*terminal-size-synonym-target*))
              :to-be (cl-tty-kit::%stream-fd *standard-output*)))))

#+sbcl
(describe "set-terminal-size"
  (it "round-trips through a PTY: what it sets is what TERMINAL-SIZE reads back"
    ;; The master side of a real PTY is the only descriptor both directions of
    ;; the ioctl agree on that resizing disturbs nothing outside the test --
    ;; unlike fd 0, which under an interactive run is the developer's own
    ;; terminal. The two calls swap COLUMNS and ROWS, so an argument order
    ;; inverted anywhere along set -> ioctl -> get would read back transposed.
    (let ((pty (make-pty :program "/bin/sh")))
      (unwind-protect
           (let ((fd (cl-tty-kit::%stream-fd (pty-stream pty))))
             (expect (integerp fd))
             (expect (multiple-value-list (set-terminal-size 93 41 fd))
                     :to-equal '(93 41))
             (expect (multiple-value-list (terminal-size fd)) :to-equal '(93 41))
             (expect (multiple-value-list (set-terminal-size 41 93 fd))
                     :to-equal '(41 93))
             (expect (multiple-value-list (terminal-size fd)) :to-equal '(41 93)))
        (close-pty pty))))
  (it "rejects a non-positive size or an invalid descriptor as a programmer error"
    ;; Rejected before any ioctl is attempted, so none of these touches fd 0.
    (expect-non-type-error (set-terminal-size 0 24))
    (expect-non-type-error (set-terminal-size 80 0))
    (expect-non-type-error (set-terminal-size -1 24))
    (expect-non-type-error (set-terminal-size 1.5 24))
    (expect-non-type-error (set-terminal-size 80 24 -1))
    (expect-non-type-error (set-terminal-size 80 24 "fd")))
  (it "signals TERMINAL-SIZE-SET-FAILED with the fd and requested size for a non-terminal fd"
    ;; A regular file is a valid descriptor that is definitively not a
    ;; terminal, so the ioctl reaches the kernel and comes back ENOTTY.
    (with-open-file (stream (cl-tty-kit/bootstrap:project-pathname "README.md")
                            :direction :input)
      (let ((fd (cl-tty-kit::%stream-fd stream)))
        (expect (integerp fd))
        (expect (lambda () (set-terminal-size 80 24 fd))
                :to-throw
                (lambda (condition)
                  (and (typep condition 'terminal-size-set-failed)
                       (typep condition 'tty-kit-error)
                       (eql fd (terminal-size-set-failed-fd condition))
                       (= 80 (terminal-size-set-failed-columns condition))
                       (= 24 (terminal-size-set-failed-rows condition))
                       (search "errno"
                               (format nil "~A"
                                       (terminal-size-set-failed-reason condition)))
                       (search "Could not set the window size"
                               (format nil "~A" condition)))))
        ;; The private helper reports the same failure as a second value rather
        ;; than signaling; SET-TERMINAL-SIZE is what turns it into a condition.
        (multiple-value-bind (successp reason)
            (cl-tty-kit::%set-terminal-size fd 80 24)
          (expect successp :to-be-falsy)
          (expect (search "errno" (format nil "~A" reason)))))))
  (it "reports :UNSUPPORTED-PLATFORM when the host's TIOCSWINSZ constant is unknown"
    ;; +TIOCSWINSZ+ is an ordinary special variable, so rebinding it to NIL is
    ;; how the unrecognized-platform path is reached on a platform that is in
    ;; fact recognized. No ioctl is issued, so fd 0 is untouched.
    (let ((cl-tty-kit::+tiocswinsz+ nil))
      (expect (lambda () (set-terminal-size 80 24))
              :to-throw
              (lambda (condition)
                (and (typep condition 'terminal-size-set-failed)
                     (eq :unsupported-platform
                         (terminal-size-set-failed-reason condition))))))))

(describe "with-terminal-session"
  (it "wraps the body in the default alternate-screen/hide-cursor bracket and returns its value"
    (let (body-ran)
      (let ((output (%capture-terminal-session-output ()
                      (expect (progn (setf body-ran t) (write-string "BODY" stream) "done")
                              :to-equal "done"))))
        (expect body-ran)
        (%expect-terminal-session-output output :body "BODY"))))
  (it "adds bracketed paste and keyboard enhancements when requested"
    (let ((output (%capture-terminal-session-output (:bracketed-paste t
                                                      :keyboard-enhancements 5)
                    (write-string "BODY" stream))))
      (%expect-terminal-session-output output :body "BODY"
                                       :bracketed-paste t :keyboard-enhancements 5)))
  (it "omits the alternate screen and cursor-hide bracket when disabled"
    (let ((output (%capture-terminal-session-output (:alternate-screen nil :hide-cursor nil)
                    (write-string "BODY" stream))))
      (%expect-terminal-session-output output :body "BODY"
                                       :alternate-screen nil :hide-cursor nil)))
  (it "still unwinds the full bracket when the body signals"
    (let (failed)
      (let ((output (%capture-terminal-session-output (:bracketed-paste t
                                                        :keyboard-enhancements 7)
                      (handler-case
                          (progn (write-string "BODY" stream) (error "boom"))
                        (error () (setf failed t))))))
        (expect failed)
        (%expect-terminal-session-output output :body "BODY"
                                         :bracketed-paste t :keyboard-enhancements 7))))
  (it "enables and disables raw mode on the requested :fd around the body"
    (let (enabled disabled)
      (flet ((enable-raw-mode (&optional fd) (setf enabled fd) t)
             (disable-raw-mode (&optional fd) (setf disabled fd) t))
        (expect (%capture-terminal-session-output (:fd 9 :raw-mode t)
                  (write-string "BODY" stream))
                :to-equal (%terminal-session-expected-output :body "BODY"))
        (expect enabled :to-be 9)
        (expect disabled :to-be 9))))
  (it "enables raw mode before the body and disables it after, even when the body signals"
    (let (events failed)
      (flet ((enable-raw-mode (&optional fd) (push (list :enable fd) events) t)
             (disable-raw-mode (&optional fd) (push (list :disable fd) events) t))
        (let ((output (%capture-terminal-session-output (:fd 17 :raw-mode t
                                                          :bracketed-paste t
                                                          :keyboard-enhancements 9)
                        (handler-case
                            (progn (push :body events) (write-string "BODY" stream)
                                   (error "boom"))
                          (error () (setf failed t))))))
          (expect failed)
          (%expect-terminal-session-output output :body "BODY"
                                           :bracketed-paste t :keyboard-enhancements 9)
          (expect (nreverse events) :to-equal '((:enable 17) :body (:disable 17)))))))
  (it "reports :hide-cursor nil in the unwind when entering the alternate screen fails"
    (let (failed)
      (let ((old-hide-cursor (symbol-function 'cl-tty-kit::ansi-hide-cursor)))
        (unwind-protect
             (progn
               (setf (symbol-function 'cl-tty-kit::ansi-hide-cursor)
                     (lambda () (error "hide failed")))
               (let ((output (%capture-terminal-session-output ()
                               (handler-case (error "boom")
                                 (error () (setf failed t))))))
                 (expect failed)
                 (%expect-terminal-session-output output :body "" :hide-cursor nil)))
          (setf (symbol-function 'cl-tty-kit::ansi-hide-cursor) old-hide-cursor)))))
  (it "reports :keyboard-enhancements nil in the unwind when pushing enhancements fails"
    (let (failed)
      (let ((old-push (symbol-function 'cl-tty-kit::ansi-push-keyboard-enhancements)))
        (unwind-protect
             (progn
               (setf (symbol-function 'cl-tty-kit::ansi-push-keyboard-enhancements)
                     (lambda (flags) (declare (ignore flags)) (error "push failed")))
               (let ((output (%capture-terminal-session-output (:bracketed-paste t
                                                                 :keyboard-enhancements 11)
                               (handler-case (error "boom")
                                 (error () (setf failed t))))))
                 (expect failed)
                 (%expect-terminal-session-output output :body ""
                                                  :bracketed-paste t :keyboard-enhancements nil)))
          (setf (symbol-function 'cl-tty-kit::ansi-push-keyboard-enhancements) old-push))))))
