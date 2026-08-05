(in-package #:cl-tty-kit/test)

(defun %sgr-mouse (cb cx cy final)
  (format nil "~C[<~D;~D;~D~C" #\Esc cb cx cy final))

(defmacro %expect-mouse ((event) &key button action x y modifiers)
  `(progn
     (expect (mouse-event-button ,event) :to-be ,button)
     (expect (mouse-event-action ,event) :to-be ,action)
     (expect (mouse-event-x ,event) :to-be ,x)
     (expect (mouse-event-y ,event) :to-be ,y)
     (expect (mouse-event-modifiers ,event) :to-equal ,modifiers)))

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
     "Shift (4) + Control (16), normalized and sorted")
    (0 0 5 #\M :left :press 0 4 nil
     "A Cx of 0 clamps to column 0 instead of wrapping below the screen")
    (0 5 0 #\M :left :press 4 0 nil
     "A Cy of 0 clamps to row 0 instead of wrapping below the screen"))
  "Each case is (CB CX CY FINAL BUTTON ACTION X Y MODIFIERS MESSAGE): the SGR
mouse report parameters %SGR-MOUSE builds, and the MOUSE-EVENT DECODE-MOUSE-
SEQUENCE must decode it into.")

(describe "decode-mouse-sequence over the SGR mouse report grammar"
  (dolist (case +mouse-decode-cases+)
    (destructuring-bind (cb cx cy final button action x y modifiers message) case
      (it message
        (let ((report (%sgr-mouse cb cx cy final)))
          (multiple-value-bind (event consumed) (decode-mouse-sequence report)
            (%expect-mouse (event) :button button :action action :x x :y y
                           :modifiers modifiers)
            (expect consumed :to-be (length report))))))))

(describe "decode-mouse-sequence on partial, malformed, or offset input"
  (it "does not decode a report missing its terminator"
    (multiple-value-bind (event consumed) (decode-mouse-sequence (format nil "~C[<0;1;1" #\Esc))
      (expect event :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines a non-mouse CSI too short to reach the `<' check"
    (multiple-value-bind (event consumed) (decode-mouse-sequence (format nil "~C[A" #\Esc))
      (expect event :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines a non-mouse CSI long enough to reach the `<' check itself"
    (multiple-value-bind (event consumed) (decode-mouse-sequence (format nil "~C[Axxxx" #\Esc))
      (expect event :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines a terminated report whose body lacks the two `;' separators"
    (multiple-value-bind (event consumed) (decode-mouse-sequence (format nil "~C[<0;5M" #\Esc))
      (expect event :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines a non-digit character embedded within a field"
    (multiple-value-bind (event consumed)
        (decode-mouse-sequence (format nil "~C[<1x;1;1M" #\Esc))
      (expect event :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "decodes starting partway through a buffer"
    (let ((buffer (concatenate 'string "ab" (%sgr-mouse 0 1 1 #\M))))
      (multiple-value-bind (event consumed) (decode-mouse-sequence buffer :start 2)
        (%expect-mouse (event) :button :left :action :press :x 0 :y 0 :modifiers nil)
        (expect consumed :to-be 9))))
  (it "declines an out-of-range start offset rather than indexing before the buffer"
    (multiple-value-bind (event consumed) (decode-mouse-sequence (%sgr-mouse 0 1 1 #\M) :start -1)
      (expect event :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines a fractional start offset"
    (multiple-value-bind (event consumed)
        (decode-mouse-sequence (%sgr-mouse 0 1 1 #\M) :start 1.5)
      (expect event :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines a report whose field overflows the parser's digit budget"
    (multiple-value-bind (event consumed)
        (decode-mouse-sequence (format nil "~C[<1234567890123;1;1M" #\Esc))
      (expect event :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines a non-ESC prefix that otherwise resembles an SGR report"
    (multiple-value-bind (event consumed) (decode-mouse-sequence "x[<0;1;1M")
      (expect event :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines a terminated report whose body carries no `;' separator at all"
    (multiple-value-bind (event consumed) (decode-mouse-sequence (format nil "~C[<0M" #\Esc))
      (expect event :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines a report whose first field is empty"
    (multiple-value-bind (event consumed) (decode-mouse-sequence (format nil "~C[<;1;1M" #\Esc))
      (expect event :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines an ESC that is not followed by `['"
    (multiple-value-bind (event consumed) (decode-mouse-sequence (format nil "~C?<0;1;1M" #\Esc))
      (expect event :to-be-falsy)
      (expect consumed :to-be 0))))

(describe "make-mouse-event"
  (it "normalizes its modifier list (deduplicated and sorted)"
    (expect (mouse-event-modifiers (make-mouse-event :modifiers '(:shift :control :shift)))
            :to-equal '(:control :shift)))
  (it "stores every supplied field"
    (%expect-mouse ((make-mouse-event :button :left :action :drag :x 2 :y 3))
                   :button :left :action :drag :x 2 :y 3 :modifiers nil))
  (it "rejects an invalid button"
    (expect (lambda () (make-mouse-event :button :invalid)) :to-throw))
  (it "rejects an invalid action"
    (expect (lambda () (make-mouse-event :action :invalid)) :to-throw))
  (it "rejects a negative x"
    (expect (lambda () (make-mouse-event :x -1)) :to-throw))
  (it "rejects a fractional y"
    (expect (lambda () (make-mouse-event :y 1.5)) :to-throw)))

(describe "mouse events integrated into decode-input"
  (it "surfaces a mouse event inline with surrounding key events"
    (let ((events (decode-input (concatenate 'string "a" (%sgr-mouse 2 4 2 #\M) "b"))))
      (expect (length events) :to-be 3)
      (expect (first events) :to-be-instance-of 'key-event)
      (expect (key-event-code (first events)) :to-be #\a)
      (expect (second events) :to-be-instance-of 'mouse-event)
      (%expect-mouse ((second events)) :button :right :action :press :x 3 :y 1 :modifiers nil)
      (expect (third events) :to-be-instance-of 'key-event)
      (expect (key-event-code (third events)) :to-be #\b)))
  (it "buffers a mouse report split across chunks instead of mis-decoding it as ESC"
    (let ((decoder (make-input-decoder)))
      (expect (decode-input-chunk decoder (format nil "~C[<0;1" #\Esc)) :to-be-falsy)
      (let ((events (decode-input-chunk decoder ";1M")))
        (expect (length events) :to-be 1)
        (expect (first events) :to-be-instance-of 'mouse-event)
        (%expect-mouse ((first events)) :button :left :action :press :x 0 :y 0 :modifiers nil)))))
