(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; SGR (1006) mouse report decoding
;;;
;;; A report is `ESC [ < Cb ; Cx ; Cy M' for a press/motion or the same with a
;;; trailing `m' for a release. Cb packs the button number, held modifiers, a
;;; motion flag, and a wheel flag; Cx/Cy are 1-based terminal coordinates, which
;;; DECODE-MOUSE-SEQUENCE reports 0-based to match CURSOR and SCREEN. This
;;; extended encoding is the only one decoded because it is unambiguous at any
;;; terminal size (the legacy X10 encoding caps coordinates at 223).
;;; --------------------------------------------------------------------------

(defstruct (mouse-event (:constructor %make-mouse-event
                                      (&key (button :none) (action :press)
                                       (x 0) (y 0) modifiers))
                        (:copier nil))
  "A decoded terminal mouse event: a button, an action, 0-based X/Y column and
row, and a normalized modifier list."
  (button :none :type keyword)
  (action :press :type keyword)
  (x 0 :type (integer 0))
  (y 0 :type (integer 0))
  (modifiers nil :type list))

(setf (documentation 'mouse-event-button 'function)
      "Return the button of MOUSE-EVENT: :LEFT, :MIDDLE, :RIGHT, :WHEEL-UP,
:WHEEL-DOWN, :WHEEL-LEFT, :WHEEL-RIGHT, or :NONE.")

(setf (documentation 'mouse-event-action 'function)
      "Return the action of MOUSE-EVENT: :PRESS, :RELEASE, :DRAG, :MOVE, or
:SCROLL.")

(setf (documentation 'mouse-event-x 'function)
      "Return the 0-based column of MOUSE-EVENT.")

(setf (documentation 'mouse-event-y 'function)
      "Return the 0-based row of MOUSE-EVENT.")

(setf (documentation 'mouse-event-modifiers 'function)
      "Return the normalized modifier list of MOUSE-EVENT.")

(defun %assert-mouse-button (button)
  (%assert (member button
                  '(:left :middle :right :wheel-up :wheel-down :wheel-left
                    :wheel-right :none)
                  :test #'eq) "Mouse event BUTTON ~S must be a supported mouse button." button))

(defun %assert-mouse-action (action)
  (%assert (member action '(:press :release :drag :move :scroll) :test #'eq)
           "Mouse event ACTION ~S must be :PRESS, :RELEASE, :DRAG, :MOVE, or :SCROLL."
           action))

(defun %assert-mouse-coordinate (name value)
  (%assert (typep value '(integer 0))
           "Mouse event ~A ~S must be a non-negative integer." name value))

(defun make-mouse-event (&key (button :none) (action :press) (x 0) (y 0) modifiers)
  "Build a MOUSE-EVENT with normalized modifier ordering."
  (%assert-mouse-button button)
  (%assert-mouse-action action)
  (%assert-mouse-coordinate "X" x)
  (%assert-mouse-coordinate "Y" y)
  (%make-mouse-event :button button
                     :action action
                     :x x
                     :y y
                     :modifiers (normalize-modifiers modifiers)))

(defun %mouse-button-name (low-bits)
  (case low-bits
    (0 :left)
    (1 :middle)
    (2 :right)
    (t :none)))

(defun %decode-mouse-cb (cb final)
  "Return (VALUES BUTTON ACTION MODIFIERS) for the SGR button byte CB.
FINAL is #\\M for a press/motion report and #\\m for a release."
  (let ((modifiers (normalize-modifiers
                    (append (when (logtest cb 4) '(:shift))
                            (when (logtest cb 8) '(:alt))
                            (when (logtest cb 16) '(:control)))))
        (low (logand cb 3)))
    (cond
      ((logtest cb 64)
       (values (case low
                 (0 :wheel-up)
                 (1 :wheel-down)
                 (2 :wheel-left)
                 (3 :wheel-right))
               :scroll modifiers))
      ((logtest cb 32)
       (if (= low 3)
           (values :none :move modifiers)
           (values (%mouse-button-name low) :drag modifiers)))
      (t
       (values (%mouse-button-name low)
               (if (char= final #\m) :release :press)
               modifiers)))))

(defun %bounded-digit-run-p (string start end max-length &optional (radix 10))
  "Return true when [START, END) of STRING is a non-empty run of at most
MAX-LENGTH digits in RADIX (decimal by default). Shared by %PARSE-MOUSE-UINT's
decimal fields and src/keys-decode.lisp's %SCALE-HEX-TO-BYTE's hex fields."
  (and (< start end)
       (<= (- end start) max-length)
       (loop for index from start below end
             always (digit-char-p (char string index) radix))))

(defconstant +max-decoded-uint-digits+ 9
  "Maximum decimal digits accepted in terminal numeric reports.")

(defun %parse-mouse-uint (string start end)
  (when (%bounded-digit-run-p string start end +max-decoded-uint-digits+)
    (parse-integer string :start start :end end)))

(defun %parse-mouse-params (string start end)
  "Split the `Cb;Cx;Cy' body in [START, END) into three unsigned integers.
Returns (VALUES CB CX CY), each NIL when the field is missing or non-numeric."
  (let* ((first-sep (position #\; string :start start :end end))
         (second-sep (and first-sep
                          (position #\; string :start (1+ first-sep) :end end))))
    (if (and first-sep second-sep)
        (values (%parse-mouse-uint string start first-sep)
                (%parse-mouse-uint string (1+ first-sep) second-sep)
                (%parse-mouse-uint string (1+ second-sep) end))
        (values nil nil nil))))

(defun %mouse-final-index (string start limit)
  (loop for index from start below limit
        for char = (char string index)
        when (or (char= char #\M) (char= char #\m))
          do (return index)
        finally (return nil)))

(defun decode-mouse-sequence (input &key (start 0))
  "Decode one SGR mouse report from INPUT starting at START.
Returns two values: a MOUSE-EVENT and the number of characters consumed. When
INPUT at START is not a complete `ESC [ < ... M/m' report -- a different sequence
or a fragment still missing its terminator -- returns NIL and 0 so a caller can
  fall back to ordinary decoding. Coordinates are reported 0-based."
  (let* ((string (%input->string input))
         (limit (length string)))
    (if (and (integerp start)
             (<= 0 start)
             (< (+ start 3) limit)
             (char= (char string start) #\Esc)
             (char= (char string (1+ start)) #\[)
             (char= (char string (+ start 2)) #\<))
        (let ((final-index (%mouse-final-index string (+ start 3) limit)))
          (if final-index
              (multiple-value-bind (cb cx cy)
                  (%parse-mouse-params string (+ start 3) final-index)
                (if (and cb cx cy)
                    (multiple-value-bind (button action modifiers)
                        (%decode-mouse-cb cb (char string final-index))
                      (values (%make-mouse-event
                               :button button
                               :action action
                               :x (max 0 (1- cx))
                               :y (max 0 (1- cy))
                               :modifiers modifiers)
                              (- (1+ final-index) start)))
                    (values nil 0)))
              (values nil 0)))
        (values nil 0))))
