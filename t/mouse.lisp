(in-package #:cl-tty-kit/test)

(defun %sgr-mouse (cb cx cy final)
  (format nil "~C[<~D;~D;~D~C" #\Esc cb cx cy final))

(defmacro %mouse-is ((event) &key button action x y modifiers)
  `(progn
     (is (eq ,button (mouse-event-button ,event)))
     (is (eq ,action (mouse-event-action ,event)))
     (is (= ,x (mouse-event-x ,event)))
     (is (= ,y (mouse-event-y ,event)))
     (is (equal ,modifiers (mouse-event-modifiers ,event)))))

(defparameter +mouse-decode-cases+
  '((0 1 1 #\M :left :press 0 0 nil
     "Left press at terminal (1,1) reports 0-based (0,0)")
    (0 5 3 #\m :left :release 4 2 nil
     "Release (trailing `m')")
    (2 10 20 #\M :right :press 9 19 nil
     "Right button")
    (1 2 2 #\M :middle :press 1 1 nil
     "Middle button")
    (3 5 5 #\M :none :press 4 4 nil
     "Low button bits of 3 are not a real button: reported as :NONE, still a press")
    (64 5 5 #\M :wheel-up :scroll 4 4 nil
     "Wheel up")
    (65 5 5 #\M :wheel-down :scroll 4 4 nil
     "Wheel down")
    (66 5 5 #\M :wheel-left :scroll 4 4 nil
     "Horizontal wheel left (button 66)")
    (67 5 5 #\M :wheel-right :scroll 4 4 nil
     "Horizontal wheel right (button 67)")
    (32 3 3 #\M :left :drag 2 2 nil
     "Motion with the left button held is a drag")
    (35 3 3 #\M :none :move 2 2 nil
     "Motion without a button held is a move")
    (4 1 1 #\M :left :press 0 0 (:shift)
     "Shift modifier")
    (8 1 1 #\M :left :press 0 0 (:alt)
     "Alt (button bit 8)")
    (20 1 1 #\M :left :press 0 0 (:control :shift)
     "Shift (4) + Control (16), normalized and sorted"))
  "Each case is (CB CX CY FINAL BUTTON ACTION X Y MODIFIERS MESSAGE): the SGR
mouse report parameters %SGR-MOUSE builds, and the MOUSE-EVENT DECODE-MOUSE-
SEQUENCE must decode it into.")

(defun %test-mouse-decode-cases ()
  (do-test-case-bind (case +mouse-decode-cases+
                            (cb cx cy final button action x y modifiers message))
    (let ((report (%sgr-mouse cb cx cy final)))
      (multiple-value-bind (event consumed) (decode-mouse-sequence report)
        (%mouse-is (event) :button button :action action :x x :y y
                   :modifiers modifiers)
        (is (= (length report) consumed) message)))))

(defun %test-mouse-partial-and-offset ()
  ;; A report missing its terminator does not decode.
  (multiple-value-bind (event consumed)
      (decode-mouse-sequence (format nil "~C[<0;1;1" #\Esc))
    (is (null event))
    (is (= 0 consumed)))
  ;; A non-mouse CSI is declined. This one is too short to reach the `<'
  ;; check at all -- it fails the earlier length guard first.
  (multiple-value-bind (event consumed)
      (decode-mouse-sequence (format nil "~C[A" #\Esc))
    (is (null event))
    (is (= 0 consumed)))
  ;; A non-mouse CSI long enough to reach the `<' check itself is declined
  ;; there instead of by the earlier length guard.
  (multiple-value-bind (event consumed)
      (decode-mouse-sequence (format nil "~C[Axxxx" #\Esc))
    (is (null event))
    (is (= 0 consumed)))
  ;; A terminated report whose body lacks the two `;' separators is declined.
  (multiple-value-bind (event consumed)
      (decode-mouse-sequence (format nil "~C[<0;5M" #\Esc))
    (is (null event))
    (is (= 0 consumed)))
  ;; A non-digit character embedded within a field (not just an empty or
  ;; overlong field) is declined.
  (multiple-value-bind (event consumed)
      (decode-mouse-sequence (format nil "~C[<1x;1;1M" #\Esc))
    (is (null event))
    (is (= 0 consumed)))
  ;; Decoding can start partway through a buffer.
  (let ((buffer (concatenate 'string "ab" (%sgr-mouse 0 1 1 #\M))))
    (multiple-value-bind (event consumed)
        (decode-mouse-sequence buffer :start 2)
      (%mouse-is (event) :button :left :action :press :x 0 :y 0 :modifiers nil)
      (is (= 9 consumed))))
  ;; Invalid offsets are declined rather than indexing before the buffer.
  (multiple-value-bind (event consumed)
      (decode-mouse-sequence (%sgr-mouse 0 1 1 #\M) :start -1)
    (is (null event))
    (is (= 0 consumed)))
  (multiple-value-bind (event consumed)
      (decode-mouse-sequence (%sgr-mouse 0 1 1 #\M) :start 1.5)
    (is (null event))
    (is (= 0 consumed)))
  (multiple-value-bind (event consumed)
      (decode-mouse-sequence (format nil "~C[<1234567890123;1;1M" #\Esc))
    (is (null event))
    (is (= 0 consumed)))
  ;; MAKE-MOUSE-EVENT normalizes its modifier list.
  (is (equal '(:control :shift)
             (mouse-event-modifiers
              (make-mouse-event :modifiers '(:shift :control :shift)))))
  (%mouse-is ((make-mouse-event :button :left :action :drag :x 2 :y 3))
             :button :left :action :drag :x 2 :y 3 :modifiers nil)
  (signals (error c) (make-mouse-event :button :invalid) (is c))
  (signals (error c) (make-mouse-event :action :invalid) (is c))
  (signals (error c) (make-mouse-event :x -1) (is c))
  (signals (error c) (make-mouse-event :y 1.5) (is c)))

(defun %test-mouse-input-integration ()
  ;; DECODE-INPUT surfaces mouse events inline with key events.
  (let ((events (decode-input (concatenate 'string
                                            "a" (%sgr-mouse 2 4 2 #\M) "b"))))
    (is (= 3 (length events)))
    (is (typep (first events) (quote key-event)))
    (is (char= #\a (key-event-code (first events))))
    (is (typep (second events) (quote mouse-event)))
    (%mouse-is ((second events)) :button :right :action :press
               :x 3 :y 1 :modifiers nil)
    (is (typep (third events) (quote key-event)))
    (is (char= #\b (key-event-code (third events)))))
  ;; A mouse report split across chunks is buffered, not mis-decoded as ESC.
  (let ((decoder (make-input-decoder)))
    (is (null (decode-input-chunk decoder (format nil "~C[<0;1" #\Esc))))
    (let ((events (decode-input-chunk decoder ";1M")))
      (is (= 1 (length events)))
      (is (typep (first events) (quote mouse-event)))
      (%mouse-is ((first events)) :button :left :action :press
                 :x 0 :y 0 :modifiers nil))))

(defun test-mouse ()
  (%test-mouse-decode-cases)
  (%test-mouse-partial-and-offset)
  (%test-mouse-input-integration)
  t)
