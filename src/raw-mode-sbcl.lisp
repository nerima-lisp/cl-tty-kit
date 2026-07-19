#+sbcl
(in-package #:cl-tty-kit)

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

#+sbcl
(defun %sb-posix-symbol (name)
  (or (find-symbol name :sb-posix)
      (error "SB-POSIX symbol ~A is unavailable." name)))

#+sbcl
(defun %sb-posix-function (name)
  (fdefinition (%sb-posix-symbol name)))

#+sbcl
(defun %sb-posix-setter (name)
  (fdefinition (list 'setf (%sb-posix-symbol name))))

#+sbcl
(defun %sb-posix-value (name)
  (symbol-value (%sb-posix-symbol name)))

#+sbcl
(defvar *raw-mode-tcsetattr-function*
  (%sb-posix-function "TCSETATTR"))

#+sbcl
(defun %raw-mode-flag-values (iflag oflag cflag lflag)
  (values (logand iflag
                  (lognot (logior (%sb-posix-value "BRKINT")
                                  (%sb-posix-value "ICRNL")
                                  (%sb-posix-value "INPCK")
                                  (%sb-posix-value "ISTRIP")
                                  (%sb-posix-value "IXON")
                                  (%sb-posix-value "IXOFF"))))
          (logand oflag (lognot (%sb-posix-value "OPOST")))
          (logior (logand cflag
                          (lognot (logior (%sb-posix-value "CSIZE")
                                          (%sb-posix-value "PARENB"))))
                  (%sb-posix-value "CS8"))
          (logand lflag
                  (lognot (logior (%sb-posix-value "ECHO")
                                  (%sb-posix-value "ICANON")
                                  (%sb-posix-value "IEXTEN")
                                  (%sb-posix-value "ISIG"))))))

#+sbcl
(defun %set-raw-mode-flags (termios)
  (multiple-value-bind (iflag oflag cflag lflag)
      (%raw-mode-flag-values (funcall (%sb-posix-function "TERMIOS-IFLAG") termios)
                             (funcall (%sb-posix-function "TERMIOS-OFLAG") termios)
                             (funcall (%sb-posix-function "TERMIOS-CFLAG") termios)
                             (funcall (%sb-posix-function "TERMIOS-LFLAG") termios))
    (funcall (%sb-posix-setter "TERMIOS-IFLAG") iflag termios)
    (funcall (%sb-posix-setter "TERMIOS-OFLAG") oflag termios)
    (funcall (%sb-posix-setter "TERMIOS-CFLAG") cflag termios)
    (funcall (%sb-posix-setter "TERMIOS-LFLAG") lflag termios))
  termios)

#+sbcl
(defun %set-raw-mode-character-control-values (cc)
  (setf (aref cc (%sb-posix-value "VMIN")) 1
        (aref cc (%sb-posix-value "VTIME")) 0)
  cc)

#+sbcl
(defun %set-raw-mode-character-control (termios)
  (%set-raw-mode-character-control-values
   (funcall (%sb-posix-function "TERMIOS-CC") termios))
  termios)

#+sbcl
(defun %snapshot-termios (termios)
  (list :iflag (funcall (%sb-posix-function "TERMIOS-IFLAG") termios)
        :oflag (funcall (%sb-posix-function "TERMIOS-OFLAG") termios)
        :cflag (funcall (%sb-posix-function "TERMIOS-CFLAG") termios)
        :lflag (funcall (%sb-posix-function "TERMIOS-LFLAG") termios)
        :cc (copy-seq (funcall (%sb-posix-function "TERMIOS-CC") termios))))

#+sbcl
(defun %restore-termios (termios snapshot)
  (funcall (%sb-posix-setter "TERMIOS-IFLAG") (getf snapshot :iflag) termios)
  (funcall (%sb-posix-setter "TERMIOS-OFLAG") (getf snapshot :oflag) termios)
  (funcall (%sb-posix-setter "TERMIOS-CFLAG") (getf snapshot :cflag) termios)
  (funcall (%sb-posix-setter "TERMIOS-LFLAG") (getf snapshot :lflag) termios)
  (funcall (%sb-posix-setter "TERMIOS-CC") (copy-seq (getf snapshot :cc)) termios)
  termios)

#+sbcl
(defun enable-raw-mode (&optional (fd 0))
  "Enable raw terminal mode on FD and remember the previous settings."
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
