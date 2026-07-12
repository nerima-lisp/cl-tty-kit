(in-package #:cl-tty-kit/test)

(defparameter +single-decode-cases+
  `(("a" :character #\a nil)
    (,(concatenate 'string (string #\Esc) "[A") :special :up nil)
    (,(concatenate 'string (string #\Esc) "[1;5C") :special :right (:control))
    (,(concatenate 'string (string #\Esc) "[3~") :special :delete nil)
    (,(concatenate 'string (string #\Esc) "[5~") :special :page-up nil)
    (,(concatenate 'string (string #\Esc) "[15~") :special :f5 nil)
    (,(concatenate 'string (string #\Esc) "[105;6u")
     :character #\i (:control :shift))
    (,(concatenate 'string (string #\Esc) "[57363;3u")
     :special :menu (:alt))
    (,(concatenate 'string (string #\Esc) "[57358u")
     :special :caps-lock nil)
    (,(concatenate 'string (string #\Esc) "[57361;6u")
     :special :print-screen (:control :shift))
    (,(concatenate 'string (string #\Esc) "[57414u")
     :special :kp-enter nil)
    (,(concatenate 'string (string #\Esc) "[57429u")
     :special :kp-delete nil)
    (,(concatenate 'string (string #\Esc) "[57364;2u")
     :special :f13 (:shift))
    (,(concatenate 'string (string #\Esc) "[57386u")
     :special :f35 nil)
    (,(concatenate 'string (string #\Esc) "[57426;5u")
     :special :kp-home (:control))
    (,(concatenate 'string (string #\Esc) "[57447u")
     :special :media-track-next nil)
    (,(concatenate 'string (string #\Esc) "[57442;4u")
     :special :media-play-pause (:alt :shift))
    (,(concatenate 'string (string #\Esc) "[57450u")
     :special :lower-volume nil)
    (,(concatenate 'string (string #\Esc) "[57458u")
     :special :left-meta nil)
    (,(concatenate 'string (string #\Esc) "[57460;3u")
     :special :right-control (:alt))
    (,(concatenate 'string (string #\Esc) "[57462;5u")
     :special :right-super (:control))
    (,(concatenate 'string (string #\Esc) "[200~")
     :special :paste-start nil)
    (,(concatenate 'string (string #\Esc) "[201~")
     :special :paste-end nil)
    (,(concatenate 'string (string #\Esc) "[Z") :special :backtab nil)
    (,(concatenate 'string (string #\Esc) "x") :character #\x (:alt))
    (,(concatenate 'string (string #\Esc) "OA") :special :up nil)
    (,(concatenate 'string (string #\Esc) "OP") :special :f1 nil)
    (,(concatenate 'string (string #\Esc) "OS") :special :f4 nil)
    (,(string (code-char 3)) :special :control-c nil)
    (,(string #\Return) :special :enter nil)
    (,(string #\Tab) :special :tab nil)))

(defparameter +decode-key-sequence-cases+
  (list (list (concatenate 'string (string #\Esc) "[")
              :special :escape nil 1)
        (list #(97) :character #\a nil 1)
        (list (concatenate 'string "zz" (string #\Esc) "[1;5C")
              :special :right (:control) 6 :start 2)
        (list (concatenate 'string "zz" (string #\Esc) "x")
              :character #\x (:alt) 2 :start 2)
        (list (concatenate 'string (string #\Esc) "[1;aC")
              :special :escape nil 1)
        (list (concatenate 'string "zz" (string #\Esc) "O")
              :special :escape nil 1 :start 2)
        (list (concatenate 'string (string #\Esc) "[99999999u")
              :special :escape nil 1)))

(defparameter +decoded-event-code-cases+
  (list (list (concatenate 'string (string #\Esc) "[1;aC")
              '(:escape #\[ #\1 #\; #\a #\C))
        (list (concatenate 'string (string #\Esc) "[99999999u")
              '(:escape #\[ #\9 #\9 #\9 #\9 #\9 #\9 #\9 #\9 #\u))
        (list (concatenate 'string (string #\Esc) "O")
              '(:escape #\O))))

(defun %key-event-signature (event)
  (list (key-event-type event)
        (key-event-code event)
        (key-event-modifiers event)))

(defun %assert-key-event= (event expected-signature)
  (is (equal (%key-event-signature event) expected-signature)))

(defun %assert-key-event (event expected-type expected-code expected-modifiers)
  (%assert-key-event= event
                      (list expected-type expected-code expected-modifiers)))

(defun %assert-single-decode-case (input expected-type expected-code
                                   expected-modifiers)
  (let ((events (decode-input input)))
    (is (= 1 (length events)))
    (%assert-key-event (first events)
                       expected-type
                       expected-code
                       expected-modifiers)))

(defun %assert-decode-key-sequence-case (input expected-type expected-code
                                         expected-modifiers expected-consumed
                                         &key (start 0))
  (multiple-value-bind (event consumed)
      (decode-key-sequence input :start start)
    (%assert-key-event event expected-type expected-code expected-modifiers)
    (is (= expected-consumed consumed))))

(defun %assert-decoded-event-codes (input expected-codes)
  (let ((events (decode-input input)))
    (is (= (length expected-codes) (length events)))
    (loop for event in events
          for expected-code in expected-codes
          do (if (characterp expected-code)
                 (is (char= expected-code (key-event-code event)))
                 (is (eq expected-code (key-event-code event)))))))

(defun test-keys ()
  (let ((event (make-key-event :type :special :code :enter :modifiers '(:control))))
    (%assert-key-event= event '(:special :enter (:control))))
  (let ((event (make-key-event :type :special
                               :code :enter
                               :modifiers '(:reverse :alt :bold :alt))))
    (%assert-key-event= event '(:special :enter (:alt :bold :reverse))))
  (handler-case
      (progn
        (error 'unsupported-feature :feature :pty)
        (is nil))
    (unsupported-feature (condition)
      (is (eq :pty (unsupported-feature-feature condition)))
      (is (search "Unsupported feature: PTY" (format nil "~A" condition)))))
  (let ((event (make-key-event :type :special
                               :code :enter
                               :modifiers '(:control :control :shift 1))))
    (%assert-key-event= event '(:special :enter (:control :shift))))
  (do-test-case-bind
      (case +single-decode-cases+
            (input expected-type expected-code expected-modifiers))
    (%assert-single-decode-case input
                                expected-type
                                expected-code
                                expected-modifiers))
  (do-test-case-bind
      (case +decode-key-sequence-cases+
            (input expected-type expected-code expected-modifiers
                   expected-consumed &key (start 0)))
    (%assert-decode-key-sequence-case input
                                      expected-type
                                      expected-code
                                      expected-modifiers
                                      expected-consumed
                                      :start start))
  (do-test-case-bind
      (case +decoded-event-code-cases+
            (input expected-codes))
    (%assert-decoded-event-codes input expected-codes))
  t)
