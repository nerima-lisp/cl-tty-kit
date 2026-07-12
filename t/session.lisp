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

(defun %assert-terminal-session-output (output &key (body "")
                                                 (alternate-screen t)
                                                 (hide-cursor t)
                                                 (bracketed-paste nil)
                                                 keyboard-enhancements)
  (is (string= (%terminal-session-expected-output :body body
                                                  :alternate-screen alternate-screen
                                                  :hide-cursor hide-cursor
                                                  :bracketed-paste bracketed-paste
                                                  :keyboard-enhancements keyboard-enhancements)
               output)))

(defun test-terminal-session ()
  (let ((output nil)
        (body-ran nil))
    (setf output
          (%capture-terminal-session-output ()
            (is (equal "done"
                       (progn
                         (setf body-ran t)
                         (write-string "BODY" stream)
                         "done")))))
    (is body-ran)
    (%assert-terminal-session-output output :body "BODY"))
  (let ((output nil))
    (setf output
          (%capture-terminal-session-output (:bracketed-paste t
                                             :keyboard-enhancements 5)
            (write-string "BODY" stream)))
    (%assert-terminal-session-output output :body "BODY"
                                      :bracketed-paste t
                                      :keyboard-enhancements 5))
  (let ((output nil))
    (setf output
          (%capture-terminal-session-output (:alternate-screen nil
                                             :hide-cursor nil)
            (write-string "BODY" stream)))
    (%assert-terminal-session-output output :body "BODY"
                                      :alternate-screen nil
                                      :hide-cursor nil))
  (let ((output nil)
        (failed nil))
    (setf output
          (%capture-terminal-session-output (:bracketed-paste t
                                             :keyboard-enhancements 7)
            (handler-case
                (progn
                  (write-string "BODY" stream)
                  (error "boom"))
              (error ()
                (setf failed t)))))
    (is failed)
    (%assert-terminal-session-output output :body "BODY"
                                      :bracketed-paste t
                                      :keyboard-enhancements 7))
  (let ((enabled nil)
        (disabled nil))
    (flet ((enable-raw-mode (&optional fd)
             (setf enabled fd)
             t)
           (disable-raw-mode (&optional fd)
             (setf disabled fd)
             t))
      (is (string=
           (%capture-terminal-session-output (:fd 9
                                              :raw-mode t)
             (write-string "BODY" stream))
           (%terminal-session-expected-output :body "BODY")))
      (is (= 9 enabled))
      (is (= 9 disabled))))
  (let ((events nil)
        (failed nil))
    (flet ((enable-raw-mode (&optional fd)
             (push (list :enable fd) events)
             t)
           (disable-raw-mode (&optional fd)
             (push (list :disable fd) events)
             t))
      (let ((output
              (%capture-terminal-session-output (:fd 17
                                                 :raw-mode t
                                                 :bracketed-paste t
                                                 :keyboard-enhancements 9)
                (handler-case
                    (progn
                      (push :body events)
                      (write-string "BODY" stream)
                      (error "boom"))
                  (error ()
                    (setf failed t))))))
        (is failed)
        (%assert-terminal-session-output output :body "BODY"
                                          :bracketed-paste t
                                          :keyboard-enhancements 9)
        (is (equal '((:enable 17) :body (:disable 17))
                   (nreverse events))))))
  (let ((failed nil))
    (let ((old-hide-cursor
            (symbol-function 'cl-tty-kit::ansi-hide-cursor)))
      (unwind-protect
            (progn
              (setf (symbol-function 'cl-tty-kit::ansi-hide-cursor)
                    (lambda ()
                      (error "hide failed")))
              (let ((output
              (%capture-terminal-session-output ()
                        (handler-case
                            (is nil)
                          (error ()
                            (setf failed t))))))
                (is failed)
                (%assert-terminal-session-output output :body ""
                                                  :hide-cursor nil)))
        (setf (symbol-function 'cl-tty-kit::ansi-hide-cursor)
              old-hide-cursor))))
  (let ((failed nil))
    (let ((old-push-keyboard-enhancements
            (symbol-function 'cl-tty-kit::ansi-push-keyboard-enhancements)))
      (unwind-protect
            (progn
              (setf (symbol-function 'cl-tty-kit::ansi-push-keyboard-enhancements)
                    (lambda (flags)
                      (declare (ignore flags))
                      (error "push failed")))
              (let ((output
              (%capture-terminal-session-output (:bracketed-paste t
                                                         :keyboard-enhancements 11)
                        (handler-case
                            (is nil)
                          (error ()
                            (setf failed t))))))
                (is failed)
                (%assert-terminal-session-output output :body ""
                                                  :bracketed-paste t
                                                  :keyboard-enhancements nil)))
        (setf (symbol-function 'cl-tty-kit::ansi-push-keyboard-enhancements)
              old-push-keyboard-enhancements))))
  t)
