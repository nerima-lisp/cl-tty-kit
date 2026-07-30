(defpackage #:cl-tty-kit/conditions-tests
  (:use #:cl #:cl-tty-kit)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave #:expect #:it))

(in-package #:cl-tty-kit/conditions-tests)

;;; --------------------------------------------------------------------------
;;; The condition hierarchy, built on nerima-lisp/cl-weave.
;;; --------------------------------------------------------------------------

(describe "tty-kit-error"
  (it "is the base condition for every cl-tty-kit error"
    (expect (make-condition 'tty-kit-error) :to-be-instance-of 'error))
  (it "documents itself as the base condition"
    (expect (search "Base condition for all cl-tty-kit errors."
                     (documentation 'tty-kit-error 'type)))))

(describe "unsupported-feature"
  (it "reports the unavailable feature"
    (let ((condition (make-condition 'unsupported-feature :feature :epoll)))
      (expect (unsupported-feature-feature condition) :to-be :epoll)
      (expect (format nil "~A" condition) :to-equal "Unsupported feature: EPOLL")))
  (it "is signaled by unsupported"
    (expect (lambda () (cl-tty-kit::unsupported :poll))
            :to-throw
            (lambda (condition)
              (and (typep condition 'unsupported-feature)
                   (eq :poll (unsupported-feature-feature condition)))))))

(describe "invalid-utf8-sequence"
  (it "reports position, octet, and reason for an overlong sequence"
    (let ((condition (make-condition 'invalid-utf8-sequence
                                     :position 7
                                     :octet #xC0
                                     :reason :overlong-sequence)))
      (expect (invalid-utf8-sequence-position condition) :to-be 7)
      (expect (invalid-utf8-sequence-octet condition) :to-be #xC0)
      (expect (invalid-utf8-sequence-reason condition) :to-be :overlong-sequence)
      (expect (format nil "~A" condition)
              :to-equal
              "Invalid UTF-8 sequence at position 7 (OVERLONG-SEQUENCE; octet C0).")))
  (it "omits the octet for a truncated sequence, which has none"
    (let ((condition (make-condition 'invalid-utf8-sequence
                                     :position 4
                                     :octet :none
                                     :reason :truncated-sequence)))
      (expect (format nil "~A" condition)
              :to-equal
              "Invalid UTF-8 sequence at position 4 (TRUNCATED-SEQUENCE).")))
  (it "is signaled by %signal-invalid-utf8-sequence"
    (expect (lambda () (cl-tty-kit::%signal-invalid-utf8-sequence 1 #x80 :invalid-leading-byte))
            :to-throw
            (lambda (condition)
              (and (typep condition 'invalid-utf8-sequence)
                   (= 1 (invalid-utf8-sequence-position condition))
                   (= #x80 (invalid-utf8-sequence-octet condition))
                   (eq :invalid-leading-byte (invalid-utf8-sequence-reason condition)))))))

(describe "screen-index-out-of-bounds"
  (it "reports the out-of-range cell and the screen's actual size"
    (let* ((screen (make-screen 3 2))
           (condition (make-condition 'screen-index-out-of-bounds
                                      :screen screen :x 4 :y 3 :width 3 :height 2)))
      (expect (screen-index-out-of-bounds-screen condition) :to-be screen)
      (expect (screen-index-out-of-bounds-x condition) :to-be 4)
      (expect (screen-index-out-of-bounds-y condition) :to-be 3)
      (expect (screen-index-out-of-bounds-width condition) :to-be 3)
      (expect (screen-index-out-of-bounds-height condition) :to-be 2)
      (expect (format nil "~A" condition)
              :to-equal
              "Cell position (4, 3) is outside the screen 3x2."))))

(describe "screen-dimensions-invalid"
  (it "reports both invalid dimensions"
    (let ((condition (make-condition 'screen-dimensions-invalid :width -1 :height :bad)))
      (expect (screen-dimensions-invalid-width condition) :to-be -1)
      (expect (screen-dimensions-invalid-height condition) :to-be :bad)
      (expect (format nil "~A" condition) :to-equal "Invalid screen dimensions -1x:BAD."))))

(describe "cursor-parameter-invalid"
  (it "reports the parameter, its value, and what was expected"
    (let ((condition (make-condition 'cursor-parameter-invalid
                                     :parameter :x :value -2
                                     :expected "non-negative integer")))
      (expect (cursor-parameter-invalid-parameter condition) :to-be :x)
      (expect (cursor-parameter-invalid-value condition) :to-be -2)
      (expect (cursor-parameter-invalid-expected condition) :to-equal "non-negative integer")
      (expect (format nil "~A" condition)
              :to-equal
              "Invalid cursor parameter X: -2 (expected non-negative integer)."))))

(describe "unsupported-code-point"
  (it "reports the rejected code point in decimal"
    (let ((condition (make-condition 'unsupported-code-point :code-point #x110000)))
      (expect (unsupported-code-point-code-point condition) :to-be #x110000)
      (expect (format nil "~A" condition) :to-equal "Unsupported Unicode code point 1114112."))))

(describe "raw-mode-operation-failed"
  (it "reports the operation, fd, and OS-level reason"
    (let ((condition (make-condition 'raw-mode-operation-failed
                                     :operation :tcsetattr :fd 12 :reason :eperm)))
      (expect (raw-mode-operation-failed-operation condition) :to-be :tcsetattr)
      (expect (raw-mode-operation-failed-fd condition) :to-be 12)
      (expect (raw-mode-operation-failed-reason condition) :to-be :eperm)
      (expect (format nil "~A" condition)
              :to-equal
              "Raw mode operation TCSETATTR failed for FD 12: EPERM."))))

(describe "pty-operation-failed"
  (it "reports the operation, the PTY, and the failure reason"
    (let* ((pty (cl-tty-kit::%make-pty :process nil :stream nil))
           (condition (make-condition 'pty-operation-failed
                                      :operation :read :pty pty :reason "closed")))
      (expect (pty-operation-failed-operation condition) :to-be :read)
      (expect (pty-operation-failed-pty condition) :to-be pty)
      (expect (pty-operation-failed-reason condition) :to-equal "closed")
      (expect (format nil "~A" condition) :to-equal "PTY operation READ failed: closed."))))

(describe "the condition-defining macros"
  ;; These macros are only ever expanded within conditions.lisp itself, so
  ;; exercising their expansion here pins the contract and covers their
  ;; bodies, which no runtime call site reaches.
  (it "%assert expands to an UNLESS-guarded error"
    (expect (first (macroexpand-1 '(cl-tty-kit::%assert pred "m ~A" arg))) :to-be 'unless))
  (it "define-tty-kit-condition expands to a documented define-condition"
    (let ((form (macroexpand-1
                 '(cl-tty-kit::define-tty-kit-condition demo-condition (error) () "doc"))))
      (expect (first form) :to-be 'define-condition)
      (expect (member '(:documentation "doc") (cddr form) :test #'equal))))
  (it "define-formatted-tty-kit-condition always carries a :report option"
    (flet ((reportp (option) (and (consp option) (eq :report (first option)))))
      ;; The format-string form derives its own :report reporter...
      (let ((form (macroexpand-1
                   '(cl-tty-kit::define-formatted-tty-kit-condition demo-condition (error)
                     ((x :initarg :x)) "doc" "value ~A" x))))
        (expect (first form) :to-be 'cl-tty-kit::define-tty-kit-condition)
        (expect (find-if #'reportp (cddddr form))))
      ;; ...and an explicit :report spec passes straight through.
      (let ((form (macroexpand-1
                   '(cl-tty-kit::define-formatted-tty-kit-condition demo-condition (error)
                     () "doc" :report demo-reporter))))
        (expect (first form) :to-be 'cl-tty-kit::define-tty-kit-condition)
        (expect (find-if #'reportp (cddddr form)))))))
