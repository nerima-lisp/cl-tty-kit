(in-package #:cl-tty-kit/test)

#+sbcl
(describe "%raw-mode-flag-values"
  (it "clears the classic raw-input iflag/oflag/cflag/lflag bits"
    (multiple-value-bind (iflag oflag cflag lflag)
        (cl-tty-kit::%raw-mode-flag-values
         (logior sb-posix:brkint sb-posix:icrnl sb-posix:inpck sb-posix:istrip
                 sb-posix:ixon sb-posix:ixoff #x10)
         (logior sb-posix:opost #x20)
         (logior sb-posix:csize sb-posix:parenb #x40)
         (logior sb-posix:echo sb-posix:echonl sb-posix:icanon sb-posix:iexten
                 sb-posix:isig #x80))
      (expect (zerop (logand iflag
                             (logior sb-posix:brkint sb-posix:icrnl sb-posix:inpck
                                     sb-posix:istrip sb-posix:ixon sb-posix:ixoff))))
      (expect (zerop (logand oflag sb-posix:opost)))
      (expect (zerop (logand cflag sb-posix:parenb)))
      (expect (logand cflag sb-posix:csize) :to-be sb-posix:cs8)
      (expect (not (zerop (logand cflag sb-posix:cs8))))
      (expect (zerop (logand lflag
                             (logior sb-posix:echo sb-posix:echonl sb-posix:icanon
                                     sb-posix:iexten sb-posix:isig))))
      ;; ECHONL is cleared alongside the classic local flags, keeping the
      ;; local-flag set a strict superset of the pre-migration cl-tmux raw mode.
      (expect (zerop (logand lflag sb-posix:echonl)))))
  (it "clears a superset (FR-006) so the mode is byte-transparent for a multiplexer"
    ;; On top of BRKINT/ICRNL/INPCK/ISTRIP/IXON/IXOFF it must also clear
    ;; IGNBRK, PARMRK, INLCR and IGNCR.
    (let ((superset (logior sb-posix:ignbrk sb-posix:brkint sb-posix:parmrk
                            sb-posix:istrip sb-posix:inlcr sb-posix:igncr
                            sb-posix:icrnl sb-posix:inpck sb-posix:ixon
                            sb-posix:ixoff))
          (unrelated-iflag-bit #x40000000))
      (multiple-value-bind (iflag oflag cflag lflag)
          (cl-tty-kit::%raw-mode-flag-values (logior superset unrelated-iflag-bit) 0 0 0)
        (declare (ignore oflag cflag lflag))
        (expect (zerop (logand iflag superset)))
        (expect (zerop (logand iflag sb-posix:ignbrk)))
        (expect (zerop (logand iflag sb-posix:parmrk)))
        (expect (zerop (logand iflag sb-posix:inlcr)))
        (expect (zerop (logand iflag sb-posix:igncr)))
        ;; Unrelated input flags are preserved (only input processing is removed).
        (expect (not (zerop (logand iflag unrelated-iflag-bit))))))))

(describe "with-raw-mode"
  (it "expands to an UNWIND-PROTECT guarded by a WHEN on the enable result"
    (let ((expanded (macroexpand-1 '(with-raw-mode () (format t "x")))))
      (expect (first expanded) :to-be 'let)
      (expect (first (third expanded)) :to-be 'unwind-protect)
      (expect (first (second (third expanded))) :to-be 'when))))

(describe "%set-raw-mode-character-control-values"
  (it "sets VMIN to 1 and VTIME to 0, leaving other indices untouched"
    (let ((cc (make-array 32 :initial-element 9)))
      (cl-tty-kit::%set-raw-mode-character-control-values cc)
      (expect (aref cc sb-posix:vmin) :to-be 1)
      (expect (aref cc sb-posix:vtime) :to-be 0)
      (expect (aref cc 0) :to-be 9))))

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

(describe "with-raw-mode, over stubbed enable/disable"
  (it "skips the body and never disables when enabling fails"
    (with-raw-mode-stubs (nil)
      (expect (with-raw-mode () (setf body-ran t)) :to-be-falsy)
      (expect body-ran :to-be-falsy)
      (expect disabled :to-be-falsy)))
  (it "runs the body and always disables when enabling succeeds"
    (with-raw-mode-stubs (t)
      (expect (with-raw-mode () (setf body-ran t) "done") :to-equal "done")
      (expect body-ran :to-be-truthy)
      (expect disabled :to-be-truthy))))

#+sbcl
(describe "enable-raw-mode / disable-raw-mode argument validation"
  (it "rejects a negative or non-integer fd"
    (expect (lambda () (enable-raw-mode -1)) :to-throw)
    (expect (lambda () (enable-raw-mode "fd")) :to-throw)
    (expect (lambda () (disable-raw-mode -1)) :to-throw)
    (expect (lambda () (disable-raw-mode "fd")) :to-throw)))

#+sbcl
(describe "enable-raw-mode against a real but unopened fd"
  (it "signals raw-mode-operation-failed naming the operation and fd"
    (expect (lambda () (enable-raw-mode 987654321))
            :to-throw
            (lambda (condition)
              (and (typep condition 'raw-mode-operation-failed)
                   (eq :enable (raw-mode-operation-failed-operation condition))
                   (= 987654321 (raw-mode-operation-failed-fd condition))
                   (search "Raw mode operation ENABLE failed for FD 987654321"
                           (format nil "~A" condition)))))))

#+sbcl
(describe "enable-raw-mode when tcsetattr fails"
  (it "signals raw-mode-operation-failed and leaves *raw-mode-states* untouched"
    (let ((pty (make-pty :program "/bin/sh")))
      (unwind-protect
          (let ((fd (sb-sys:fd-stream-fd (pty-stream pty))))
            (let ((cl-tty-kit::*raw-mode-states*
                    (list (cons 99 (list :snapshot :sentinel :depth 1)))))
              (let ((cl-tty-kit::*raw-mode-tcsetattr-function*
                      (lambda (&rest args)
                        (declare (ignore args))
                        (error "tcsetattr failed"))))
                (expect (lambda () (enable-raw-mode fd))
                        :to-throw
                        (lambda (condition)
                          (and (typep condition 'raw-mode-operation-failed)
                               (eq :enable (raw-mode-operation-failed-operation condition))
                               (= fd (raw-mode-operation-failed-fd condition))
                               (equal '((99 :snapshot :sentinel :depth 1))
                                      cl-tty-kit::*raw-mode-states*)
                               (search "Raw mode operation ENABLE failed"
                                       (format nil "~A" condition))))))))
        (close-pty pty)))))

#+sbcl
(describe "enable-raw-mode / disable-raw-mode nesting depth"
  (it "tracks a reentrant enable/disable pair as one tcsetattr call each way"
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
              (expect (enable-raw-mode fd))
              (let ((state (assoc fd cl-tty-kit::*raw-mode-states*)))
                (expect state)
                (expect (getf (cdr state) :depth) :to-be 1))
              (let ((snapshot (getf (cdr (assoc fd cl-tty-kit::*raw-mode-states*)) :snapshot)))
                (expect (enable-raw-mode fd))
                (expect tcsetattr-calls :to-be 1)
                (let ((state (assoc fd cl-tty-kit::*raw-mode-states*)))
                  (expect (getf (cdr state) :depth) :to-be 2)
                  (expect (getf (cdr state) :snapshot) :to-be snapshot)))
              (expect (disable-raw-mode fd))
              (expect tcsetattr-calls :to-be 1)
              (expect (getf (cdr (assoc fd cl-tty-kit::*raw-mode-states*)) :depth) :to-be 1)
              (expect (disable-raw-mode fd))
              (expect tcsetattr-calls :to-be 2)
              (expect (assoc fd cl-tty-kit::*raw-mode-states*) :to-be-falsy)))
        (close-pty pty)))))

#+sbcl
(describe "disable-raw-mode when tcsetattr fails"
  (it "signals raw-mode-operation-failed and leaves *raw-mode-states* untouched"
    (let ((pty (make-pty :program "/bin/sh")))
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
              (expect (lambda () (disable-raw-mode fd))
                      :to-throw
                      (lambda (condition)
                        (and (typep condition 'raw-mode-operation-failed)
                             (eq :disable (raw-mode-operation-failed-operation condition))
                             (= fd (raw-mode-operation-failed-fd condition))
                             (equal (list (cons fd (list :snapshot snapshot :depth 1)))
                                    cl-tty-kit::*raw-mode-states*)
                             (search "Raw mode operation DISABLE failed"
                                     (format nil "~A" condition)))))))
        (close-pty pty)))))

(describe "%sb-posix-symbol"
  (it "signals a clear error for a name that has never existed in sb-posix"
    ;; A portability guard against an SB-POSIX symbol renamed or removed out
    ;; from under this code; a name that has never existed there exercises the
    ;; same path deterministically.
    (expect (lambda () (cl-tty-kit::%sb-posix-symbol "DEFINITELY-NOT-A-REAL-SB-POSIX-SYMBOL"))
            :to-throw
            (lambda (c) (search "SB-POSIX symbol" (format nil "~A" c))))))
