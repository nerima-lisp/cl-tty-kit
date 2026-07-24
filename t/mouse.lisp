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

(defun %test-mouse-basic ()
  ;; Left press at terminal (1,1) reports 0-based (0,0) and consumes the report.
  (multiple-value-bind (event consumed)
      (decode-mouse-sequence (%sgr-mouse 0 1 1 #\M))
    (%mouse-is (event) :button :left :action :press :x 0 :y 0 :modifiers nil)
    (is (= 9 consumed)))
  ;; Release (trailing `m').
  (multiple-value-bind (event consumed)
      (decode-mouse-sequence (%sgr-mouse 0 5 3 #\m))
    (declare (ignore consumed))
    (%mouse-is (event) :button :left :action :release :x 4 :y 2 :modifiers nil))
  ;; Right and middle buttons.
  (%mouse-is ((decode-mouse-sequence (%sgr-mouse 2 10 20 #\M)))
             :button :right :action :press :x 9 :y 19 :modifiers nil)
  (%mouse-is ((decode-mouse-sequence (%sgr-mouse 1 2 2 #\M)))
             :button :middle :action :press :x 1 :y 1 :modifiers nil)
  ;; Low button bits of 3 are not a real button: reported as :NONE, still a press.
  (%mouse-is ((decode-mouse-sequence (%sgr-mouse 3 5 5 #\M)))
             :button :none :action :press :x 4 :y 4 :modifiers nil))

(defun %test-mouse-wheel-and-motion ()
  (%mouse-is ((decode-mouse-sequence (%sgr-mouse 64 5 5 #\M)))
             :button :wheel-up :action :scroll :x 4 :y 4 :modifiers nil)
  (%mouse-is ((decode-mouse-sequence (%sgr-mouse 65 5 5 #\M)))
             :button :wheel-down :action :scroll :x 4 :y 4 :modifiers nil)
  ;; Horizontal wheel (buttons 66/67).
  (%mouse-is ((decode-mouse-sequence (%sgr-mouse 66 5 5 #\M)))
             :button :wheel-left :action :scroll :x 4 :y 4 :modifiers nil)
  (%mouse-is ((decode-mouse-sequence (%sgr-mouse 67 5 5 #\M)))
             :button :wheel-right :action :scroll :x 4 :y 4 :modifiers nil)
  ;; Motion with the left button held is a drag; without a button it is a move.
  (%mouse-is ((decode-mouse-sequence (%sgr-mouse 32 3 3 #\M)))
             :button :left :action :drag :x 2 :y 2 :modifiers nil)
  (%mouse-is ((decode-mouse-sequence (%sgr-mouse 35 3 3 #\M)))
             :button :none :action :move :x 2 :y 2 :modifiers nil))

(defun %test-mouse-modifiers ()
  (%mouse-is ((decode-mouse-sequence (%sgr-mouse 4 1 1 #\M)))
             :button :left :action :press :x 0 :y 0 :modifiers '(:shift))
  ;; Alt (button bit 8) on a left press.
  (%mouse-is ((decode-mouse-sequence (%sgr-mouse 8 1 1 #\M)))
             :button :left :action :press :x 0 :y 0 :modifiers '(:alt))
  ;; Shift (4) + Control (16) on a left press, normalized and sorted.
  (%mouse-is ((decode-mouse-sequence (%sgr-mouse 20 1 1 #\M)))
             :button :left :action :press :x 0 :y 0
             :modifiers '(:control :shift)))

(defun %test-mouse-partial-and-offset ()
  ;; A report missing its terminator does not decode.
  (multiple-value-bind (event consumed)
      (decode-mouse-sequence (format nil "~C[<0;1;1" #\Esc))
    (is (null event))
    (is (= 0 consumed)))
  ;; A non-mouse CSI is declined.
  (multiple-value-bind (event consumed)
      (decode-mouse-sequence (format nil "~C[A" #\Esc))
    (is (null event))
    (is (= 0 consumed)))
  ;; A terminated report whose body lacks the two `;' separators is declined.
  (multiple-value-bind (event consumed)
      (decode-mouse-sequence (format nil "~C[<0;5M" #\Esc))
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
  (%test-mouse-basic)
  (%test-mouse-wheel-and-motion)
  (%test-mouse-modifiers)
  (%test-mouse-partial-and-offset)
  (%test-mouse-input-integration)
  t)
