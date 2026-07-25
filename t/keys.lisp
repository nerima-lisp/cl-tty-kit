(in-package #:cl-tty-kit/test)

(defun %esc (&rest suffix-parts)
  "Concatenate an ESC character with SUFFIX-PARTS, the shared building block
behind every literal terminal escape sequence these tests construct."
  (apply #'concatenate 'string (string #\Esc) suffix-parts))

(defparameter +single-decode-cases+
  `(("a" :character #\a nil)
    (,(%esc "[A") :special :up nil)
    (,(%esc "[1;5C") :special :right (:control))
    (,(%esc "[3~") :special :delete nil)
    (,(%esc "[5~") :special :page-up nil)
    (,(%esc "[15~") :special :f5 nil)
    (,(%esc "[105;6u")
     :character #\i (:control :shift))
    (,(%esc "[57363;3u")
     :special :menu (:alt))
    (,(%esc "[57358u")
     :special :caps-lock nil)
    (,(%esc "[57361;6u")
     :special :print-screen (:control :shift))
    (,(%esc "[57414u")
     :special :kp-enter nil)
    (,(%esc "[57429u")
     :special :kp-delete nil)
    (,(%esc "[57364;2u")
     :special :f13 (:shift))
    (,(%esc "[57386u")
     :special :f35 nil)
    (,(%esc "[57426;5u")
     :special :kp-home (:control))
    (,(%esc "[57447u")
     :special :media-track-next nil)
    (,(%esc "[57442;4u")
     :special :media-play-pause (:alt :shift))
    (,(%esc "[57450u")
     :special :lower-volume nil)
    (,(%esc "[57458u")
     :special :left-meta nil)
    (,(%esc "[57460;3u")
     :special :right-control (:alt))
    (,(%esc "[57462;5u")
     :special :right-super (:control))
    (,(%esc "[200~")
     :special :paste-start nil)
    (,(%esc "[201~")
     :special :paste-end nil)
    (,(%esc "[x")
     :special :unknown-csi nil)
    (,(%esc "[999~")
     :special :unknown-csi nil)
    (,(%esc "[Z") :special :backtab nil)
    (,(%esc "x") :character #\x (:alt))
    (,(%esc "OA") :special :up nil)
    (,(%esc "OP") :special :f1 nil)
    (,(%esc "OS") :special :f4 nil)
    (,(string (code-char 3)) :special :control-c nil)
    (,(string (code-char 28)) :special :control-backslash nil)
    (,(string (code-char 29)) :special :control-right-bracket nil)
    (,(string (code-char 30)) :special :control-caret nil)
    (,(string (code-char 31)) :special :control-underscore nil)
    (,(string #\Return) :special :enter nil)
    (,(string #\Tab) :special :tab nil)
    (,(string #\Rubout) :special :backspace nil)))

(defparameter +decode-key-sequence-cases+
  (list (list (%esc "[")
              :special :escape nil 1)
        (list #(97) :character #\a nil 1)
        (list (concatenate 'string "zz" (string #\Esc) "[1;5C")
              :special :right '(:control) 6 :start 2)
        (list (concatenate 'string "zz" (string #\Esc) "x")
              :character #\x '(:alt) 2 :start 2)
        (list (%esc "[1;aC")
              :special :escape nil 1)
        (list (concatenate 'string "zz" (string #\Esc) "O")
              :special :escape nil 1 :start 2)
        (list (%esc "[99999999u")
              :special :escape nil 1)
        (list (%esc "[" (make-string 19 :initial-element #\9) "u")
              :special :escape nil 1)))

(defparameter +decoded-event-code-cases+
  (list (list (%esc "[1;aC")
              '(:escape #\[ #\1 #\; #\a #\C))
        (list (%esc "[99999999u")
              '(:escape #\[ #\9 #\9 #\9 #\9 #\9 #\9 #\9 #\9 #\u))
        (list (%esc "[" (make-string 19 :initial-element #\9) "u")
              (append '(:escape #\[)
                      (make-list 19 :initial-element #\9)
                      '(#\u)))
        (list (%esc "O")
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

(defun %assert-decode-key-sequence-declined (input start)
  (multiple-value-bind (event consumed)
      (decode-key-sequence input :start start)
    (is (null event))
    (is (= 0 consumed))))

(defun %assert-decoded-event-codes (input expected-codes)
  (let ((events (decode-input input)))
    (is (= (length expected-codes) (length events)))
    (loop for event in events
          for expected-code in expected-codes
          do (if (characterp expected-code)
                 (is (char= expected-code (key-event-code event)))
                 (is (eq expected-code (key-event-code event)))))))

(defun %test-key-event->string ()
  (flet ((label (type code &optional modifiers)
           (key-event->string (make-key-event :type type :code code
                                              :modifiers modifiers))))
    (is (string= "C-a" (label :character #\a '(:control))))
    (is (string= "x" (label :character #\x)))
    (is (string= "S-Up" (label :special :up '(:shift))))
    (is (string= "Enter" (label :special :enter)))
    (is (string= "Page-Up" (label :special :page-up)))
    (is (string= "C-a" (label :special :control-a)))
    (is (string= "F1" (label :special :f1)))
    (is (string= "<paste 5 bytes>" (label :paste "hello")))
    (is (string= "<paste 0 bytes>" (label :paste "")))
    ;; Modifier prefix is Ctrl-Alt-Shift order regardless of input order.
    (is (string= "C-S-a" (label :character #\a '(:shift :control)))))
  (signals-non-type-error (key-event->string :not-a-key-event)))

(defun %test-focus-decode ()
  (let ((event (first (decode-input (format nil "~C[I" #\Esc)))))
    (is (eq :special (key-event-type event)))
    (is (eq :focus-in (key-event-code event))))
  (let ((event (first (decode-input (format nil "~C[O" #\Esc)))))
    (is (eq :special (key-event-type event)))
    (is (eq :focus-out (key-event-code event)))))

(defun %test-cursor-position-report ()
  ;; A complete report yields 0-based row/col and the consumed length.
  (multiple-value-bind (row col consumed)
      (decode-cursor-position-report (format nil "~C[12;40R" #\Esc))
    (is (= 11 row))
    (is (= 39 col))
    (is (= 8 consumed)))
  (multiple-value-bind (row col consumed)
      (decode-cursor-position-report (format nil "~C[1;1R" #\Esc))
    (is (= 0 row))
    (is (= 0 col))
    (is (= 6 consumed)))
  ;; Incomplete or non-report input is declined.
  (multiple-value-bind (row col consumed)
      (decode-cursor-position-report (format nil "~C[12;40" #\Esc))
    (is (null row))
    (is (null col))
    (is (= 0 consumed)))
  (multiple-value-bind (row col consumed)
      (decode-cursor-position-report (format nil "~C[A" #\Esc))
    (declare (ignore row col))
    (is (= 0 consumed)))
  ;; A complete report body missing its `;' separator is declined.
  (multiple-value-bind (row col consumed)
      (decode-cursor-position-report (format nil "~C[12R" #\Esc))
    (is (null row))
    (is (null col))
    (is (= 0 consumed)))
  ;; Decoding can start partway through a buffer.
  (multiple-value-bind (row col consumed)
      (decode-cursor-position-report (format nil "xx~C[3;5R" #\Esc) :start 2)
    (is (= 2 row))
    (is (= 4 col))
    (is (= 6 consumed)))
  ;; Invalid offsets are declined rather than indexing before the buffer.
  (multiple-value-bind (row col consumed)
      (decode-cursor-position-report (format nil "~C[3;5R" #\Esc) :start -1)
    (is (null row))
    (is (null col))
    (is (= 0 consumed)))
  (multiple-value-bind (row col consumed)
      (decode-cursor-position-report (format nil "~C[3;5R" #\Esc) :start 1.5)
    (is (null row))
    (is (null col))
    (is (= 0 consumed)))
  (multiple-value-bind (row col consumed)
      (decode-cursor-position-report (format nil "~C[1234567890123;1R" #\Esc))
    (is (null row))
    (is (null col))
    (is (= 0 consumed))))

(defun %test-color-report ()
  ;; 4-hex-digit components scaled to 8-bit, ESC\ terminator.
  (multiple-value-bind (r g b consumed)
      (decode-color-report (format nil "~C]11;rgb:ffff/0000/8080~C\\" #\Esc #\Esc))
    (is (= 255 r))
    (is (= 0 g))
    (is (= 128 b))
    (is (= 25 consumed)))
  ;; 2-hex-digit components, BEL terminator.
  (multiple-value-bind (r g b consumed)
      (decode-color-report (format nil "~C]10;rgb:ff/00/00~C" #\Esc (code-char 7)))
    (is (= 255 r))
    (is (= 0 g))
    (is (= 0 b))
    (is (= 18 consumed)))
  ;; Incomplete / non-report input is declined.
  (multiple-value-bind (r g b consumed)
      (decode-color-report (format nil "~C]11;rgb:ffff/0000" #\Esc))
    (declare (ignore r g b))
    (is (= 0 consumed)))
  (multiple-value-bind (r g b consumed)
      (decode-color-report (format nil "~C[A" #\Esc))
    (declare (ignore r g b))
    (is (= 0 consumed)))
  ;; A well-formed OSC prefix whose body never contains "rgb:" is declined.
  (multiple-value-bind (r g b consumed)
      (decode-color-report (format nil "~C]11;notrgb~C\\" #\Esc #\Esc))
    (declare (ignore r g b))
    (is (= 0 consumed)))
  ;; A complete report missing the second "/" separator (only one channel
  ;; boundary, so R/G/B cannot be split) is declined, as opposed to missing
  ;; the terminator entirely (the case above).
  (multiple-value-bind (r g b consumed)
      (decode-color-report (format nil "~C]10;rgb:ff/00~C\\" #\Esc #\Esc))
    (declare (ignore r g b))
    (is (= 0 consumed)))
  ;; Invalid offsets are declined without signaling.
  (multiple-value-bind (r g b consumed)
      (decode-color-report (format nil "~C]10;rgb:ff/00/00~C" #\Esc (code-char 7))
                           :start -1)
    (is (null r))
    (is (null g))
    (is (null b))
    (is (= 0 consumed)))
  (multiple-value-bind (r g b consumed)
      (decode-color-report (format nil "~C]10;rgb:ff/00/00~C" #\Esc (code-char 7))
                           :start 1.5)
    (is (null r))
    (is (null g))
    (is (null b))
    (is (= 0 consumed)))
  (multiple-value-bind (r g b consumed)
      (decode-color-report (format nil "~C]10;rgb:fffffffff/00/00~C" #\Esc
                                   (code-char 7)))
    (is (null r))
    (is (null g))
    (is (null b))
    (is (= 0 consumed))))

(defun %csi (params final)
  (%esc "[" params (string final)))

(defun %test-kitty-and-f-keys ()
  ;; Kitty CSI-u event types: MODIFIER:EVENT. 'a' = 97; event 3 = release.
  (let ((event (first (decode-input (%csi "97;1:3" #\u)))))
    (is (eq :character (key-event-type event)))
    (is (char= #\a (key-event-code event)))
    (is (eq :release (key-event-kind event))))
  (let ((event (first (decode-input (%csi "97;1:2" #\u)))))
    (is (eq :repeat (key-event-kind event))))
  ;; Shift (modifier 2) + press (event 1).
  (let ((event (first (decode-input (%csi "97;2:1" #\u)))))
    (is (equal '(:shift) (key-event-modifiers event)))
    (is (eq :press (key-event-kind event))))
  ;; Event kinds also apply to arrows and other CSI keys.
  (let ((event (first (decode-input (%csi "1;1:3" #\A)))))
    (is (eq :up (key-event-code event)))
    (is (eq :release (key-event-kind event))))
  ;; A plain key defaults to :PRESS.
  (is (eq :press (key-event-kind (first (decode-input "a")))))
  ;; Legacy CSI-tilde F13-F20.
  (is (eq :f13 (key-event-code (first (decode-input (%csi "25" #\~))))))
  (is (eq :f20 (key-event-code (first (decode-input (%csi "34" #\~))))))
  ;; Kitty associated text (field 3) and the shifted-key subfield of field 1.
  (let ((event (first (decode-input (%csi "97;1;97" #\u)))))
    (is (char= #\a (key-event-code event)))
    (is (string= "a" (key-event-text event))))
  (let ((event (first (decode-input (%csi "97:65;2;65" #\u)))))
    (is (char= #\a (key-event-code event)))
    (is (equal '(:shift) (key-event-modifiers event)))
    (is (string= "A" (key-event-text event))))
  ;; A plain key has no associated text.
  (is (null (key-event-text (first (decode-input "a")))))
  ;; Kitty shifted / base-layout key alternates (field-1 sub-fields).
  (let ((event (first (decode-input (%csi "97:65:97;2" #\u)))))
    (is (char= #\a (key-event-code event)))
    (is (char= #\A (key-event-shifted-key event)))
    (is (char= #\a (key-event-base-key event)))
    (is (equal '(:shift) (key-event-modifiers event))))
  ;; Shifted without base.
  (let ((event (first (decode-input (%csi "97:65;1" #\u)))))
    (is (char= #\A (key-event-shifted-key event)))
    (is (null (key-event-base-key event))))
  ;; No alternates on a plain key.
  (let ((event (first (decode-input "a"))))
    (is (null (key-event-shifted-key event)))
    (is (null (key-event-base-key event))))
  ;; Multi-code-point text (colon-separated within field 3).
  (let ((event (first (decode-input (%csi "97;1;104:105" #\u)))))
    (is (string= "hi" (key-event-text event))))
  ;; An empty text field (nothing between the second `;' and the final byte)
  ;; is NIL, same as when field 3 is absent entirely.
  (let ((event (first (decode-input (%csi "97;1;" #\u)))))
    (is (null (key-event-text event))))
  ;; A code point in field 3 out of the Unicode range is malformed; the
  ;; whole text field is dropped rather than partially decoded.
  (let ((event (first (decode-input (%csi "97;1;9999999" #\u)))))
    (is (null (key-event-text event))))
  ;; More than three `;'-separated fields is not a form this decoder
  ;; recognizes -- it declines and falls back to raw character decoding
  ;; rather than misinterpreting the extra field.
  (is (eq :escape (key-event-code (first (decode-input (%csi "97;1;104;200" #\u))))))
  ;; A non-digit character embedded in a field is likewise declined.
  (is (eq :unknown-csi (key-event-code (first (decode-input (%csi "9x;1" #\u)))))))

(defun %test-device-attributes ()
  (multiple-value-bind (params consumed)
      (decode-device-attributes (%csi "?1;2" #\c))
    (is (equal '(1 2) params))
    (is (= 7 consumed)))
  (multiple-value-bind (params consumed)
      (decode-device-attributes (%csi ">0;276;0" #\c))
    (is (equal '(0 276 0) params))
    (is (plusp consumed)))
  ;; A bare `ESC [ c' has no parameters.
  (multiple-value-bind (params consumed)
      (decode-device-attributes (%csi "" #\c))
    (is (null params))
    (is (= 3 consumed)))
  ;; Non-ESC-prefixed input is declined.
  (multiple-value-bind (params consumed)
      (decode-device-attributes "hello")
    (is (null params))
    (is (= 0 consumed)))
  ;; A bare `ESC [' with nothing after is declined before the `?'/`>' prefix
  ;; check even looks past the end of the string.
  (multiple-value-bind (params consumed)
      (decode-device-attributes (format nil "~C[" #\Esc))
    (is (null params))
    (is (= 0 consumed)))
  ;; Incomplete input is declined.
  (multiple-value-bind (params consumed)
      (decode-device-attributes (format nil "~C[?1;2" #\Esc))
    (is (null params))
    (is (= 0 consumed)))
  ;; Invalid offsets are declined without signaling.
  (multiple-value-bind (params consumed)
      (decode-device-attributes (%csi "?1;2" #\c) :start -1)
    (is (null params))
    (is (= 0 consumed)))
  (multiple-value-bind (params consumed)
      (decode-device-attributes (%csi "?1;2" #\c) :start 1.5)
    (is (null params))
    (is (= 0 consumed))))

(defun test-keys ()
  (%test-key-event->string)
  (%test-focus-decode)
  (%test-cursor-position-report)
  (%test-color-report)
  (%test-kitty-and-f-keys)
  (%test-device-attributes)
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
  (signals-non-type-error (make-key-event :type "bad" :code #\a))
  (signals-non-type-error (make-key-event :type :character :code :not-a-character))
  (signals-non-type-error (make-key-event :type :special :code #\a))
  (signals-non-type-error (make-key-event :type :paste :code #\a))
  (signals-non-type-error (make-key-event :type :character :code #\a :kind :down))
  (signals-non-type-error (make-key-event :type :character :code #\a :text :bad))
  (signals-non-type-error (make-key-event :type :character :code #\a :shifted-key "A"))
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
  (%assert-decode-key-sequence-declined "a" -1)
  (%assert-decode-key-sequence-declined "a" 1.5)
  (%assert-decode-key-sequence-declined "a" 1)
  (do-test-case-bind
      (case +decoded-event-code-cases+
            (input expected-codes))
    (%assert-decoded-event-codes input expected-codes))
  t)
