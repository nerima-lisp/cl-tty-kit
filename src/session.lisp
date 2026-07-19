(in-package #:cl-tty-kit)

(defmacro with-terminal-session-output ((stream-var &rest session-options)
                                        &body body)
  "Capture terminal session output from BODY into a string.

This is a convenience wrapper around WITH-TERMINAL-SESSION for examples and
tests that need the rendered escape sequences as a return value."
  `(with-output-to-string (,stream-var)
     (with-terminal-session (,stream-var ,@session-options)
       ,@body)))

(defmacro with-terminal-session ((stream-var &key (stream '*standard-output*)
                                        (fd 0)
                                        raw-mode
                                        (alternate-screen t)
                                        (hide-cursor t)
                                        bracketed-paste
                                        keyboard-enhancements)
                                 &body body)
  "Execute BODY with terminal session state scoped to STREAM.

The helper composes alternate-screen, cursor visibility, bracketed paste,
keyboard enhancement, and optional raw mode setup with guaranteed cleanup."
  (let ((fd-value (gensym "FD"))
        (raw-mode-value (gensym "RAW-MODE"))
        (alternate-screen-value (gensym "ALTERNATE-SCREEN"))
        (hide-cursor-value (gensym "HIDE-CURSOR"))
        (bracketed-paste-value (gensym "BRACKETED-PASTE"))
        (keyboard-enhancements-value (gensym "KEYBOARD-ENHANCEMENTS")))
    `(let ((,stream-var ,stream)
           (,fd-value ,fd)
           (,raw-mode-value ,raw-mode)
           (,alternate-screen-value ,alternate-screen)
           (,hide-cursor-value ,hide-cursor)
           (,bracketed-paste-value ,bracketed-paste)
           (,keyboard-enhancements-value ,keyboard-enhancements))
       (labels ((%emit (sequence)
                  (write-string sequence ,stream))
                (%start-step (thunk)
                  ;; Attempt one setup step; on failure leave it un-done so the
                  ;; matching teardown is skipped and the body still runs.
                  (handler-case (progn (funcall thunk) t)
                    (error () nil)))
                (%start-session ()
                  (when (and ,alternate-screen-value
                             (not (%start-step
                                   (lambda ()
                                     (%emit (ansi-enter-alternate-screen))))))
                    (setf ,alternate-screen-value nil))
                  (when (and ,hide-cursor-value
                             (not (%start-step
                                   (lambda ()
                                     (%emit (ansi-hide-cursor))))))
                    (setf ,hide-cursor-value nil))
                  (when (and ,bracketed-paste-value
                             (not (%start-step
                                   (lambda ()
                                     (%emit (ansi-enable-bracketed-paste))))))
                    (setf ,bracketed-paste-value nil))
                  (when (and ,keyboard-enhancements-value
                             (not (%start-step
                                   (lambda ()
                                     (%emit (ansi-push-keyboard-enhancements
                                             ,keyboard-enhancements-value))))))
                    (setf ,keyboard-enhancements-value nil))
                  (finish-output ,stream))
                (%end-session ()
                  (when ,keyboard-enhancements-value
                    (%emit (ansi-pop-keyboard-enhancements)))
                  (when ,bracketed-paste-value
                    (%emit (ansi-disable-bracketed-paste)))
                  (when ,hide-cursor-value
                    (%emit (ansi-show-cursor)))
                  (when ,alternate-screen-value
                    (%emit (ansi-exit-alternate-screen)))
                  (finish-output ,stream)))
         (if ,raw-mode-value
             (with-raw-mode (,fd-value)
               (unwind-protect
                    (progn
                      (%start-session)
                      ,@body)
                 (%end-session)))
             (unwind-protect
                  (progn
                    (%start-session)
                    ,@body)
               (%end-session)))))))
