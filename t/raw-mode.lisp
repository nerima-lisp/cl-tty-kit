(in-package #:cl-tty-kit/test)

#+sbcl
(defun test-raw-mode-superset ()
  ;; FR-006: ENABLE-RAW-MODE clears a superset of the classic raw input flags.
  ;; On top of BRKINT/ICRNL/INPCK/ISTRIP/IXON/IXOFF it must also clear IGNBRK,
  ;; PARMRK, INLCR and IGNCR, so the resulting mode is byte-transparent enough
  ;; for a multiplexer feeding the stream verbatim to a child PTY.
  (let ((superset (logior sb-posix:ignbrk sb-posix:brkint sb-posix:parmrk
                          sb-posix:istrip sb-posix:inlcr sb-posix:igncr
                          sb-posix:icrnl sb-posix:inpck sb-posix:ixon
                          sb-posix:ixoff))
        (unrelated-iflag-bit #x40000000))
    (multiple-value-bind (iflag oflag cflag lflag)
        (cl-tty-kit::%raw-mode-flag-values
         (logior superset unrelated-iflag-bit) 0 0 0)
      (declare (ignore oflag cflag lflag))
      ;; The whole superset is cleared.
      (is (zerop (logand iflag superset)))
      ;; Each newly-added flag is cleared individually.
      (is (zerop (logand iflag sb-posix:ignbrk)))
      (is (zerop (logand iflag sb-posix:parmrk)))
      (is (zerop (logand iflag sb-posix:inlcr)))
      (is (zerop (logand iflag sb-posix:igncr)))
      ;; Unrelated input flags are preserved (only input processing is removed).
      (is (not (zerop (logand iflag unrelated-iflag-bit))))))
  t)

#-sbcl
(defun test-raw-mode-superset ()
  t)

(defmacro with-raw-mode-stubs ((enable-result) &body body)
  `(let ((body-ran nil)
         (disabled nil))
     (flet ((enable-raw-mode (&optional fd)
              (declare (ignore fd))
              ,enable-result)
            (disable-raw-mode (&optional fd)
              (declare (ignore fd))
              (setf disabled t)))
       ,@body)))

(defun test-raw-mode ()
  (let ((expanded (macroexpand-1 '(with-raw-mode () (format t "x")))))
    (is (eq 'let (first expanded)))
    (is (eq 'unwind-protect (first (third expanded))))
    (is (eq 'when (first (second (third expanded)))))
  )
  (multiple-value-bind (iflag oflag cflag lflag)
      (cl-tty-kit::%raw-mode-flag-values
       (logior sb-posix:brkint
               sb-posix:icrnl
               sb-posix:inpck
               sb-posix:istrip
               sb-posix:ixon
               sb-posix:ixoff
               #x10)
       (logior sb-posix:opost #x20)
       (logior sb-posix:csize sb-posix:parenb #x40)
       (logior sb-posix:echo
               sb-posix:echonl
               sb-posix:icanon
               sb-posix:iexten
               sb-posix:isig
               #x80))
    (is (zerop (logand iflag
                       (logior sb-posix:brkint
                               sb-posix:icrnl
                               sb-posix:inpck
                               sb-posix:istrip
                               sb-posix:ixon
                               sb-posix:ixoff))))
    (is (zerop (logand oflag sb-posix:opost)))
    (is (zerop (logand cflag sb-posix:parenb)))
    (is (= sb-posix:cs8 (logand cflag sb-posix:csize)))
    (is (not (zerop (logand cflag sb-posix:cs8))))
    (is (zerop (logand lflag
                       (logior sb-posix:echo
                               sb-posix:echonl
                               sb-posix:icanon
                               sb-posix:iexten
                               sb-posix:isig))))
    ;; ECHONL is cleared alongside the classic local flags, keeping the local-flag
    ;; set a strict superset of the pre-migration cl-tmux raw mode.
    (is (zerop (logand lflag sb-posix:echonl))))
  (let ((cc (make-array 32 :initial-element 9)))
    (cl-tty-kit::%set-raw-mode-character-control-values cc)
    (is (= 1 (aref cc sb-posix:vmin)))
    (is (= 0 (aref cc sb-posix:vtime)))
    (is (= 9 (aref cc 0))))
  (with-raw-mode-stubs (nil)
    (is (null (with-raw-mode ()
                (setf body-ran t))))
    (is (not body-ran))
    (is (not disabled)))
  (with-raw-mode-stubs (t)
    (is (equal "done"
               (with-raw-mode ()
                 (setf body-ran t)
                 "done")))
    (is body-ran)
    (is disabled))
  #+sbcl
  (progn
    (signals (error condition) (enable-raw-mode -1)
      (declare (ignore condition)))
    (signals (error condition) (enable-raw-mode "fd")
      (declare (ignore condition)))
    (signals (error condition) (disable-raw-mode -1)
      (declare (ignore condition)))
    (signals (error condition) (disable-raw-mode "fd")
      (declare (ignore condition))))
  #+sbcl
  (let ((failed nil))
    (handler-case
        (enable-raw-mode 987654321)
      (raw-mode-operation-failed (condition)
        (is (eq :enable (raw-mode-operation-failed-operation condition)))
        (is (= 987654321 (raw-mode-operation-failed-fd condition)))
        (is (search "Raw mode operation ENABLE failed for FD 987654321"
                    (format nil "~A" condition)))
        (setf failed t)))
    (is failed))
  #+sbcl
  (let ((failed nil)
        (pty (make-pty :program "/bin/sh")))
    (unwind-protect
        (let ((fd (sb-sys:fd-stream-fd (pty-stream pty))))
          (let ((cl-tty-kit::*raw-mode-states*
                  (list (cons 99 (list :snapshot :sentinel :depth 1)))))
            (let ((cl-tty-kit::*raw-mode-tcsetattr-function*
                   (lambda (&rest args)
                     (declare (ignore args))
                     (error "tcsetattr failed"))))
              (handler-case
                  (progn
                    (enable-raw-mode fd)
                    (is nil))
                (raw-mode-operation-failed (condition)
                  (is (eq :enable (raw-mode-operation-failed-operation condition)))
                  (is (= fd (raw-mode-operation-failed-fd condition)))
                  (is (equal '((99 :snapshot :sentinel :depth 1))
                             cl-tty-kit::*raw-mode-states*))
                  (is (search "Raw mode operation ENABLE failed"
                              (format nil "~A" condition)))
                  (setf failed t)))))))
      (close-pty pty)
      (is failed))
  #+sbcl
  (let ((pty (make-pty :program "/bin/sh"))
        (tcsetattr-calls 0))
    (unwind-protect
        (let ((fd (sb-sys:fd-stream-fd (pty-stream pty))))
          (let ((cl-tty-kit::*raw-mode-states* nil)
                (cl-tty-kit::*raw-mode-tcsetattr-function*
                  (lambda (&rest args)
                    (declare (ignore args))
                    (incf tcsetattr-calls)
                    t)))
            (is (enable-raw-mode fd))
            (let ((state (assoc fd cl-tty-kit::*raw-mode-states*)))
              (is state)
              (is (= 1 (getf (cdr state) :depth))))
            (let ((snapshot (getf (cdr (assoc fd cl-tty-kit::*raw-mode-states*))
                                  :snapshot)))
              (is (enable-raw-mode fd))
              (is (= 1 tcsetattr-calls))
              (let ((state (assoc fd cl-tty-kit::*raw-mode-states*)))
                (is (= 2 (getf (cdr state) :depth)))
                (is (eq snapshot (getf (cdr state) :snapshot)))))
            (is (disable-raw-mode fd))
            (is (= 1 tcsetattr-calls))
            (is (= 1 (getf (cdr (assoc fd cl-tty-kit::*raw-mode-states*))
                           :depth)))
            (is (disable-raw-mode fd))
            (is (= 2 tcsetattr-calls))
            (is (null (assoc fd cl-tty-kit::*raw-mode-states*)))))
      (close-pty pty)))
  #+sbcl
  (let ((failed nil)
        (pty (make-pty :program "/bin/sh")))
    (unwind-protect
        (let* ((fd (sb-sys:fd-stream-fd (pty-stream pty)))
               (termios (sb-posix:tcgetattr fd))
               (snapshot (cl-tty-kit::%snapshot-termios termios)))
          (let ((cl-tty-kit::*raw-mode-states*
                  (list (cons fd (list :snapshot snapshot :depth 1))))
                (cl-tty-kit::*raw-mode-tcsetattr-function*
                  (lambda (&rest args)
                    (declare (ignore args))
                    (error "tcsetattr failed"))))
            (handler-case
                (progn
                  (disable-raw-mode fd)
                  (is nil))
              (raw-mode-operation-failed (condition)
                (is (eq :disable (raw-mode-operation-failed-operation condition)))
                (is (= fd (raw-mode-operation-failed-fd condition)))
                (is (equal (list (cons fd (list :snapshot snapshot :depth 1)))
                           cl-tty-kit::*raw-mode-states*))
                (is (search "Raw mode operation DISABLE failed"
                            (format nil "~A" condition)))
                (setf failed t)))))
      (close-pty pty)
      (is failed)))
  t)
