(in-package #:cl-tty-kit/test)

(defun test-conditions ()
  (let ((base (make-condition 'tty-kit-error)))
    (is (typep base 'error))
    (is (search "Base condition for all cl-tty-kit errors."
                (documentation 'tty-kit-error 'type))))
  (let ((condition (make-condition 'unsupported-feature :feature :epoll)))
    (is (eq :epoll (unsupported-feature-feature condition)))
    (is (string= "Unsupported feature: EPOLL"
                 (format nil "~A" condition))))
  (let ((condition (make-condition 'invalid-utf8-sequence
                                   :position 7
                                   :octet #xC0
                                   :reason :overlong-sequence)))
    (is (= 7 (invalid-utf8-sequence-position condition)))
    (is (= #xC0 (invalid-utf8-sequence-octet condition)))
    (is (eq :overlong-sequence
            (invalid-utf8-sequence-reason condition)))
    (is (string= "Invalid UTF-8 sequence at position 7 (OVERLONG-SEQUENCE; octet C0)."
                 (format nil "~A" condition))))
  (let ((condition (make-condition 'invalid-utf8-sequence
                                   :position 4
                                   :octet :none
                                   :reason :truncated-sequence)))
    (is (string= "Invalid UTF-8 sequence at position 4 (TRUNCATED-SEQUENCE)."
                 (format nil "~A" condition))))
  (let* ((screen (make-screen 3 2))
         (condition (make-condition 'screen-index-out-of-bounds
                                    :screen screen
                                    :x 4
                                    :y 3
                                    :width 3
                                    :height 2)))
    (is (eq screen (screen-index-out-of-bounds-screen condition)))
    (is (= 4 (screen-index-out-of-bounds-x condition)))
    (is (= 3 (screen-index-out-of-bounds-y condition)))
    (is (= 3 (screen-index-out-of-bounds-width condition)))
    (is (= 2 (screen-index-out-of-bounds-height condition)))
    (is (string= "Cell position (4, 3) is outside the screen 3x2."
                 (format nil "~A" condition))))
  (let ((condition (make-condition 'screen-dimensions-invalid
                                   :width -1
                                   :height :bad)))
    (is (= -1 (screen-dimensions-invalid-width condition)))
    (is (eq :bad (screen-dimensions-invalid-height condition)))
    (is (string= "Invalid screen dimensions -1x:BAD."
                 (format nil "~A" condition))))
  (let ((condition (make-condition 'cursor-parameter-invalid
                                   :parameter :x
                                   :value -2
                                   :expected "non-negative integer")))
    (is (eq :x (cursor-parameter-invalid-parameter condition)))
    (is (= -2 (cursor-parameter-invalid-value condition)))
    (is (string= "non-negative integer"
                 (cursor-parameter-invalid-expected condition)))
    (is (string= "Invalid cursor parameter X: -2 (expected non-negative integer)."
                 (format nil "~A" condition))))
  (let ((condition (make-condition 'unsupported-code-point :code-point #x110000)))
    (is (= #x110000 (unsupported-code-point-code-point condition)))
    (is (string= "Unsupported Unicode code point 1114112."
                 (format nil "~A" condition))))
  (let ((condition (make-condition 'raw-mode-operation-failed
                                   :operation :tcsetattr
                                   :fd 12
                                   :reason :eperm)))
    (is (eq :tcsetattr (raw-mode-operation-failed-operation condition)))
    (is (= 12 (raw-mode-operation-failed-fd condition)))
    (is (eq :eperm (raw-mode-operation-failed-reason condition)))
    (is (string= "Raw mode operation TCSETATTR failed for FD 12: EPERM."
                 (format nil "~A" condition))))
  (let ((pty (cl-tty-kit::%make-pty :process nil :stream nil))
        (condition nil))
    (setf condition
          (make-condition 'pty-operation-failed
                          :operation :read
                          :pty pty
                          :reason "closed"))
    (is (eq :read (pty-operation-failed-operation condition)))
    (is (eq pty (pty-operation-failed-pty condition)))
    (is (string= "closed" (pty-operation-failed-reason condition)))
    (is (string= "PTY operation READ failed: closed."
                 (format nil "~A" condition))))
  (signals (invalid-utf8-sequence condition)
      (cl-tty-kit::%signal-invalid-utf8-sequence 1 #x80 :invalid-leading-byte)
    (is (= 1 (invalid-utf8-sequence-position condition)))
    (is (= #x80 (invalid-utf8-sequence-octet condition)))
    (is (eq :invalid-leading-byte
            (invalid-utf8-sequence-reason condition))))
  (signals (unsupported-feature condition)
      (cl-tty-kit::unsupported :poll)
    (is (eq :poll (unsupported-feature-feature condition))))
  ;; The condition-defining macros are only ever expanded within
  ;; conditions.lisp itself, so exercising them here pins their expansion
  ;; contract (and covers their bodies, which no runtime call site reaches).
  (is (eq 'unless (first (macroexpand-1 '(cl-tty-kit::%assert pred "m ~A" arg)))))
  (let ((form (macroexpand-1
               '(cl-tty-kit::define-tty-kit-condition demo-condition (error) () "doc"))))
    (is (eq 'define-condition (first form)))
    (is (member '(:documentation "doc") (cddr form) :test #'equal)))
  (flet ((reportp (option) (and (consp option) (eq :report (first option)))))
    ;; Both branches expand into a define-tty-kit-condition carrying a :report
    ;; option -- a report lambda for the format-string form...
    (let ((form (macroexpand-1
                 '(cl-tty-kit::define-formatted-tty-kit-condition demo-condition (error)
                   ((x :initarg :x)) "doc" "value ~A" x))))
      (is (eq 'cl-tty-kit::define-tty-kit-condition (first form)))
      (is (find-if #'reportp (cddddr form))))
    ;; ...and the explicit :report spec passed straight through for the other.
    (let ((form (macroexpand-1
                 '(cl-tty-kit::define-formatted-tty-kit-condition demo-condition (error)
                   () "doc" :report demo-reporter))))
      (is (eq 'cl-tty-kit::define-tty-kit-condition (first form)))
      (is (find-if #'reportp (cddddr form))))))
