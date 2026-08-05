#+sbcl
(in-package #:cl-tty-kit)

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

#+sbcl
(defmacro %sb-posix-symbol (name)
  `(let ((name ,name))
     (or (find-symbol name :sb-posix)
         (error "SB-POSIX symbol ~A is unavailable." name))))

#+sbcl
(defmacro %sb-posix-function (name)
  `(let ((name ,name))
     (fdefinition (%sb-posix-symbol name))))

#+sbcl
(defmacro %sb-posix-setter (name)
  `(let ((name ,name))
     (fdefinition (list 'setf (%sb-posix-symbol name)))))

#+sbcl
(defmacro %sb-posix-value (name)
  `(let ((name ,name))
     (symbol-value (%sb-posix-symbol name))))

;;; raw-mode.lisp (loaded before this file on every platform) already
;;; (defvar *raw-mode-tcsetattr-function* nil) -- defvar is a no-op on an
;;; already-bound variable, so re-declaring it here with defvar would
;;; silently never install the real SBCL implementation. setf instead.
#+sbcl
(setf *raw-mode-tcsetattr-function*
      (%sb-posix-function "TCSETATTR"))

#+sbcl
(defmacro %raw-mode-flag-values (iflag oflag cflag lflag)
  `(let ((iflag ,iflag) (oflag ,oflag) (cflag ,cflag) (lflag ,lflag))
     ;; Clear a superset of the classic cfmakeraw input flags. The additional
     ;; IGNBRK, PARMRK, INLCR, and IGNCR clears (on top of the original BRKINT,
     ;; ICRNL, INPCK, ISTRIP, IXON, IXOFF) make this a strict "more raw"
     ;; configuration: no break handling, no marking or stripping, and no CR/NL
     ;; translation of input. This satisfies byte-transparent consumers (such as a
     ;; terminal multiplexer feeding the stream verbatim to a child PTY) while
     ;; remaining a valid raw mode for cl-tty-kit's own callers, since every added
     ;; flag only removes input processing.
     (values (logand iflag
                     (lognot (logior (%sb-posix-value "IGNBRK")
                                     (%sb-posix-value "BRKINT")
                                     (%sb-posix-value "PARMRK")
                                     (%sb-posix-value "ISTRIP")
                                     (%sb-posix-value "INLCR")
                                     (%sb-posix-value "IGNCR")
                                     (%sb-posix-value "ICRNL")
                                     (%sb-posix-value "INPCK")
                                     (%sb-posix-value "IXON")
                                     (%sb-posix-value "IXOFF"))))
             (logand oflag (lognot (%sb-posix-value "OPOST")))
             (logior (logand cflag
                             (lognot (logior (%sb-posix-value "CSIZE")
                                             (%sb-posix-value "PARENB"))))
                     (%sb-posix-value "CS8"))
             ;; Clear ECHONL in addition to the classic ECHO/ICANON/IEXTEN/ISIG so
             ;; the local-flag set is likewise a strict superset of the pre-migration
             ;; cl-tmux raw mode. ECHONL is inert while ICANON is cleared, so this is
             ;; a no-op at runtime; it only makes the flag set honest and matches the
             ;; old cl-tmux behavior exactly.
             (logand lflag
                     (lognot (logior (%sb-posix-value "ECHO")
                                     (%sb-posix-value "ECHONL")
                                     (%sb-posix-value "ICANON")
                                     (%sb-posix-value "IEXTEN")
                                     (%sb-posix-value "ISIG")))))))

#+sbcl
(defmacro %set-raw-mode-flags (termios)
  `(let ((termios ,termios))
     (multiple-value-bind (iflag oflag cflag lflag)
         (%raw-mode-flag-values (funcall (%sb-posix-function "TERMIOS-IFLAG") termios)
                                (funcall (%sb-posix-function "TERMIOS-OFLAG") termios)
                                (funcall (%sb-posix-function "TERMIOS-CFLAG") termios)
                                (funcall (%sb-posix-function "TERMIOS-LFLAG") termios))
       (funcall (%sb-posix-setter "TERMIOS-IFLAG") iflag termios)
       (funcall (%sb-posix-setter "TERMIOS-OFLAG") oflag termios)
       (funcall (%sb-posix-setter "TERMIOS-CFLAG") cflag termios)
       (funcall (%sb-posix-setter "TERMIOS-LFLAG") lflag termios))
     termios))

#+sbcl
(defmacro %set-raw-mode-character-control-values (cc)
  `(let ((cc ,cc))
     (setf (aref cc (%sb-posix-value "VMIN")) 1
           (aref cc (%sb-posix-value "VTIME")) 0)
     cc))

#+sbcl
(defmacro %set-raw-mode-character-control (termios)
  `(let ((termios ,termios))
     (%set-raw-mode-character-control-values
      (funcall (%sb-posix-function "TERMIOS-CC") termios))
     termios))

#+sbcl
(defmacro %snapshot-termios (termios)
  `(let ((termios ,termios))
     (list :iflag (funcall (%sb-posix-function "TERMIOS-IFLAG") termios)
           :oflag (funcall (%sb-posix-function "TERMIOS-OFLAG") termios)
           :cflag (funcall (%sb-posix-function "TERMIOS-CFLAG") termios)
           :lflag (funcall (%sb-posix-function "TERMIOS-LFLAG") termios)
           :cc (copy-seq (funcall (%sb-posix-function "TERMIOS-CC") termios)))))

#+sbcl
(defmacro %restore-termios (termios snapshot)
  `(let ((termios ,termios) (snapshot ,snapshot))
     (funcall (%sb-posix-setter "TERMIOS-IFLAG") (getf snapshot :iflag) termios)
     (funcall (%sb-posix-setter "TERMIOS-OFLAG") (getf snapshot :oflag) termios)
     (funcall (%sb-posix-setter "TERMIOS-CFLAG") (getf snapshot :cflag) termios)
     (funcall (%sb-posix-setter "TERMIOS-LFLAG") (getf snapshot :lflag) termios)
     (funcall (%sb-posix-setter "TERMIOS-CC") (copy-seq (getf snapshot :cc)) termios)
     termios))

#+sbcl
(defun enable-raw-mode (&optional (fd 0))
  "Enable raw terminal mode on FD and remember the previous settings."
  (setf fd (%assert-raw-mode-fd fd))
  (%with-raw-mode-states-lock
    (handler-case
        (let ((existing-state (%raw-mode-state fd)))
          (when existing-state
            (incf (getf (cdr existing-state) :depth))
            (return-from enable-raw-mode t))
          (let ((termios (funcall (%sb-posix-function "TCGETATTR") fd)))
            (let ((snapshot (%snapshot-termios termios)))
              (%set-raw-mode-flags termios)
              (%set-raw-mode-character-control termios)
              (funcall *raw-mode-tcsetattr-function*
                       fd (%sb-posix-value "TCSADRAIN") termios)
              (%set-raw-mode-state fd snapshot 1)
              t)))
      (error (condition)
        (%signal-raw-mode-operation-failed :enable fd condition)))))

#+sbcl
(defun disable-raw-mode (&optional (fd 0))
  "Restore the terminal settings saved by ENABLE-RAW-MODE."
  (setf fd (%assert-raw-mode-fd fd))
  (%with-raw-mode-states-lock
    (let ((state (%raw-mode-state fd)))
      (when state
        (if (> (%raw-mode-state-depth state) 1)
            (progn
              (decf (getf (cdr state) :depth))
              t)
            (handler-case
                (progn
                  (let ((termios (funcall (%sb-posix-function "TCGETATTR") fd)))
                    (%restore-termios termios (%raw-mode-state-snapshot state))
                    (funcall *raw-mode-tcsetattr-function*
                             fd (%sb-posix-value "TCSADRAIN") termios))
                  (%remove-raw-mode-state fd)
                  t)
              (error (condition)
                (%signal-raw-mode-operation-failed :disable fd condition))))))))
