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

(defun %csi (params final)
  (%esc "[" params (string final)))

(defmacro %expect-key-event ((event) type code modifiers)
  `(progn
     (expect (key-event-type ,event) :to-be ,type)
     (expect (key-event-code ,event) :to-be ,code)
     (expect (key-event-modifiers ,event) :to-equal ,modifiers)))

(describe "key-event->string"
  (flet ((label (type code &optional modifiers)
           (key-event->string (make-key-event :type type :code code
                                              :modifiers modifiers))))
    (it "renders a control-modified character as C-<char>"
      (expect (label :character #\a '(:control)) :to-equal "C-a"))
    (it "renders a plain character with no modifier prefix"
      (expect (label :character #\x) :to-equal "x"))
    (it "renders a shift-modified special key as S-<Name>"
      (expect (label :special :up '(:shift)) :to-equal "S-Up"))
    (it "renders the :enter special key as Enter"
      (expect (label :special :enter) :to-equal "Enter"))
    (it "renders the :page-up special key as Page-Up"
      (expect (label :special :page-up) :to-equal "Page-Up"))
    (it "renders :control-a as C-a"
      (expect (label :special :control-a) :to-equal "C-a"))
    (it "renders :f1 as F1"
      (expect (label :special :f1) :to-equal "F1"))
    (it "renders a paste event with its byte count"
      (expect (label :paste "hello") :to-equal "<paste 5 bytes>"))
    (it "renders an empty paste event with a zero byte count"
      (expect (label :paste "") :to-equal "<paste 0 bytes>"))
    ;; Modifier prefix is Ctrl-Alt-Shift order regardless of input order.
    (it "orders combined modifiers as Ctrl-Alt-Shift regardless of input order"
      (expect (label :character #\a '(:shift :control)) :to-equal "C-S-a")))
  (it "signals a non-type-error for a non-key-event argument"
    (expect-non-type-error (key-event->string :not-a-key-event))))

(describe "focus-in/focus-out event decoding"
  (it "decodes ESC[I as a :focus-in special event"
    (let ((event (first (decode-input (format nil "~C[I" #\Esc)))))
      (expect (key-event-type event) :to-be :special)
      (expect (key-event-code event) :to-be :focus-in)))
  (it "decodes ESC[O as a :focus-out special event"
    (let ((event (first (decode-input (format nil "~C[O" #\Esc)))))
      (expect (key-event-type event) :to-be :special)
      (expect (key-event-code event) :to-be :focus-out))))

(describe "decode-cursor-position-report"
  ;; A complete report yields 0-based row/col and the consumed length.
  (it "decodes a complete report to 0-based row/col and reports the consumed length"
    (multiple-value-bind (row col consumed)
        (decode-cursor-position-report (format nil "~C[12;40R" #\Esc))
      (expect row :to-be 11)
      (expect col :to-be 39)
      (expect consumed :to-be 8)))
  (it "decodes the top-left report (1,1) to (0,0)"
    (multiple-value-bind (row col consumed)
        (decode-cursor-position-report (format nil "~C[1;1R" #\Esc))
      (expect row :to-be 0)
      (expect col :to-be 0)
      (expect consumed :to-be 6)))
  ;; Incomplete or non-report input is declined.
  (it "declines an incomplete report"
    (multiple-value-bind (row col consumed)
        (decode-cursor-position-report (format nil "~C[12;40" #\Esc))
      (expect row :to-be-falsy)
      (expect col :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines a non-report CSI sequence"
    (multiple-value-bind (row col consumed)
        (decode-cursor-position-report (format nil "~C[A" #\Esc))
      (declare (ignore row col))
      (expect consumed :to-be 0)))
  ;; A complete report body missing its `;' separator is declined.
  (it "declines a complete report body missing its `;' separator"
    (multiple-value-bind (row col consumed)
        (decode-cursor-position-report (format nil "~C[12R" #\Esc))
      (expect row :to-be-falsy)
      (expect col :to-be-falsy)
      (expect consumed :to-be 0)))
  ;; Decoding can start partway through a buffer.
  (it "decodes starting partway through a buffer"
    (multiple-value-bind (row col consumed)
        (decode-cursor-position-report (format nil "xx~C[3;5R" #\Esc) :start 2)
      (expect row :to-be 2)
      (expect col :to-be 4)
      (expect consumed :to-be 6)))
  ;; Invalid offsets are declined rather than indexing before the buffer.
  (it "declines a negative start offset rather than indexing before the buffer"
    (multiple-value-bind (row col consumed)
        (decode-cursor-position-report (format nil "~C[3;5R" #\Esc) :start -1)
      (expect row :to-be-falsy)
      (expect col :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines a fractional start offset"
    (multiple-value-bind (row col consumed)
        (decode-cursor-position-report (format nil "~C[3;5R" #\Esc) :start 1.5)
      (expect row :to-be-falsy)
      (expect col :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines a report whose field overflows the parser's digit budget"
    (multiple-value-bind (row col consumed)
        (decode-cursor-position-report (format nil "~C[1234567890123;1R" #\Esc))
      (expect row :to-be-falsy)
      (expect col :to-be-falsy)
      (expect consumed :to-be 0)))
  ;; A non-ESC prefix is declined without consuming the apparent report body.
  (it "declines a non-ESC prefix without consuming the apparent report body"
    (multiple-value-bind (row col consumed)
        (decode-cursor-position-report "x[3;5R")
      (expect row :to-be-falsy)
      (expect col :to-be-falsy)
      (expect consumed :to-be 0)))
  ;; CSI integer fields accept the configured maximum digit run, but no more.
  (it "accepts a CSI integer field up to the configured maximum digit run"
    (expect (cl-tty-kit::%parse-csi-integer "999999999999999999" 0 18)
            :to-be 999999999999999999))
  (it "declines a CSI integer field one digit past the configured maximum"
    (expect (cl-tty-kit::%parse-csi-integer "9999999999999999999" 0 19)
            :to-be-falsy)))

(describe "decode-color-report"
  ;; 4-hex-digit components scaled to 8-bit, ESC\ terminator.
  (it "decodes 4-hex-digit RGB components scaled to 8-bit, with an ESC\\ terminator"
    (multiple-value-bind (r g b consumed)
        (decode-color-report (format nil "~C]11;rgb:ffff/0000/8080~C\\" #\Esc #\Esc))
      (expect r :to-be 255)
      (expect g :to-be 0)
      (expect b :to-be 128)
      (expect consumed :to-be 25)))
  ;; 2-hex-digit components, BEL terminator.
  (it "decodes 2-hex-digit RGB components with a BEL terminator"
    (multiple-value-bind (r g b consumed)
        (decode-color-report (format nil "~C]10;rgb:ff/00/00~C" #\Esc (code-char 7)))
      (expect r :to-be 255)
      (expect g :to-be 0)
      (expect b :to-be 0)
      (expect consumed :to-be 18)))
  ;; Incomplete / non-report input is declined.
  (it "declines incomplete/non-report input"
    (multiple-value-bind (r g b consumed)
        (decode-color-report (format nil "~C]11;rgb:ffff/0000" #\Esc))
      (declare (ignore r g b))
      (expect consumed :to-be 0)))
  (it "declines a non-OSC CSI sequence"
    (multiple-value-bind (r g b consumed)
        (decode-color-report (format nil "~C[A" #\Esc))
      (declare (ignore r g b))
      (expect consumed :to-be 0)))
  ;; A well-formed OSC prefix whose body never contains "rgb:" is declined.
  (it "declines a well-formed OSC prefix whose body never contains \"rgb:\""
    (multiple-value-bind (r g b consumed)
        (decode-color-report (format nil "~C]11;notrgb~C\\" #\Esc #\Esc))
      (declare (ignore r g b))
      (expect consumed :to-be 0)))
  ;; A complete report missing the second "/" separator (only one channel
  ;; boundary, so R/G/B cannot be split) is declined, as opposed to missing
  ;; the terminator entirely (the case above).
  (it "declines a complete report missing the second \"/\" separator, as opposed to a missing terminator"
    (multiple-value-bind (r g b consumed)
        (decode-color-report (format nil "~C]10;rgb:ff/00~C\\" #\Esc #\Esc))
      (declare (ignore r g b))
      (expect consumed :to-be 0)))
  ;; Invalid offsets are declined without signaling.
  (it "declines a negative start offset without signaling"
    (multiple-value-bind (r g b consumed)
        (decode-color-report (format nil "~C]10;rgb:ff/00/00~C" #\Esc (code-char 7))
                             :start -1)
      (expect r :to-be-falsy)
      (expect g :to-be-falsy)
      (expect b :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines a fractional start offset without signaling"
    (multiple-value-bind (r g b consumed)
        (decode-color-report (format nil "~C]10;rgb:ff/00/00~C" #\Esc (code-char 7))
                             :start 1.5)
      (expect r :to-be-falsy)
      (expect g :to-be-falsy)
      (expect b :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines an overlong hex component"
    (multiple-value-bind (r g b consumed)
        (decode-color-report (format nil "~C]10;rgb:fffffffff/00/00~C" #\Esc
                                     (code-char 7)))
      (expect r :to-be-falsy)
      (expect g :to-be-falsy)
      (expect b :to-be-falsy)
      (expect consumed :to-be 0))))

(describe "kitty CSI-u protocol and legacy CSI-tilde F-keys"
  ;; Kitty CSI-u event types: MODIFIER:EVENT. 'a' = 97; event 3 = release.
  (it "decodes a kitty CSI-u release event (event type 3)"
    (let ((event (first (decode-input (%csi "97;1:3" #\u)))))
      (expect (key-event-type event) :to-be :character)
      (expect (key-event-code event) :to-be #\a)
      (expect (key-event-kind event) :to-be :release)))
  (it "decodes a kitty CSI-u repeat event (event type 2)"
    (let ((event (first (decode-input (%csi "97;1:2" #\u)))))
      (expect (key-event-kind event) :to-be :repeat)))
  ;; Shift (modifier 2) + press (event 1).
  (it "decodes shift modifier (2) with a press event (1)"
    (let ((event (first (decode-input (%csi "97;2:1" #\u)))))
      (expect (key-event-modifiers event) :to-equal '(:shift))
      (expect (key-event-kind event) :to-be :press)))
  ;; Event kinds also apply to arrows and other CSI keys.
  (it "applies event kinds to arrow and other CSI keys too, not just kitty character keys"
    (let ((event (first (decode-input (%csi "1;1:3" #\A)))))
      (expect (key-event-code event) :to-be :up)
      (expect (key-event-kind event) :to-be :release)))
  ;; A plain key defaults to :PRESS.
  (it "defaults a plain key's kind to :press"
    (expect (key-event-kind (first (decode-input "a"))) :to-be :press))
  ;; Legacy CSI-tilde F13-F20.
  (it "decodes legacy CSI-tilde F13"
    (expect (key-event-code (first (decode-input (%csi "25" #\~)))) :to-be :f13))
  (it "decodes legacy CSI-tilde F20"
    (expect (key-event-code (first (decode-input (%csi "34" #\~)))) :to-be :f20))
  ;; Kitty associated text (field 3) and the shifted-key subfield of field 1.
  (it "decodes kitty associated text (field 3) alongside the shifted-key subfield of field 1"
    (let ((event (first (decode-input (%csi "97;1;97" #\u)))))
      (expect (key-event-code event) :to-be #\a)
      (expect (key-event-text event) :to-equal "a")))
  (it "decodes a shift modifier together with field-3 text"
    (let ((event (first (decode-input (%csi "97:65;2;65" #\u)))))
      (expect (key-event-code event) :to-be #\a)
      (expect (key-event-modifiers event) :to-equal '(:shift))
      (expect (key-event-text event) :to-equal "A")))
  ;; A plain key has no associated text.
  (it "leaves a plain key's text as NIL"
    (expect (key-event-text (first (decode-input "a"))) :to-be-falsy))
  ;; Kitty shifted / base-layout key alternates (field-1 sub-fields).
  (it "decodes kitty shifted- and base-layout-key alternates (field-1 sub-fields)"
    (let ((event (first (decode-input (%csi "97:65:97;2" #\u)))))
      (expect (key-event-code event) :to-be #\a)
      (expect (key-event-shifted-key event) :to-be #\A)
      (expect (key-event-base-key event) :to-be #\a)
      (expect (key-event-modifiers event) :to-equal '(:shift))))
  ;; Shifted without base.
  (it "decodes a shifted-key alternate without a base-key alternate"
    (let ((event (first (decode-input (%csi "97:65;1" #\u)))))
      (expect (key-event-shifted-key event) :to-be #\A)
      (expect (key-event-base-key event) :to-be-falsy)))
  ;; No alternates on a plain key.
  (it "leaves shifted-/base-key alternates NIL on a plain key"
    (let ((event (first (decode-input "a"))))
      (expect (key-event-shifted-key event) :to-be-falsy)
      (expect (key-event-base-key event) :to-be-falsy)))
  ;; Multi-code-point text (colon-separated within field 3).
  (it "decodes multi-code-point text (colon-separated within field 3)"
    (let ((event (first (decode-input (%csi "97;1;104:105" #\u)))))
      (expect (key-event-text event) :to-equal "hi")))
  ;; An empty text field (nothing between the second `;' and the final byte)
  ;; is NIL, same as when field 3 is absent entirely.
  (it "treats an empty text field the same as an absent field 3 (NIL)"
    (let ((event (first (decode-input (%csi "97;1;" #\u)))))
      (expect (key-event-text event) :to-be-falsy)))
  ;; A code point in field 3 out of the Unicode range is malformed; the
  ;; whole text field is dropped rather than partially decoded.
  (it "drops the whole text field when its code point is out of Unicode range, rather than partially decoding"
    (let ((event (first (decode-input (%csi "97;1;9999999" #\u)))))
      (expect (key-event-text event) :to-be-falsy)))
  ;; More than three `;'-separated fields is not a form this decoder
  ;; recognizes -- it declines and falls back to raw character decoding
  ;; rather than misinterpreting the extra field.
  (it "declines more than three `;'-separated fields and falls back to raw character decoding"
    (expect (key-event-code (first (decode-input (%csi "97;1;104;200" #\u))))
            :to-be :escape))
  ;; A non-digit character embedded in a field is likewise declined.
  (it "declines a non-digit character embedded in a field"
    (expect (key-event-code (first (decode-input (%csi "9x;1" #\u))))
            :to-be :unknown-csi)))

(describe "decode-device-attributes"
  (it "decodes primary device attributes parameters"
    (multiple-value-bind (params consumed)
        (decode-device-attributes (%csi "?1;2" #\c))
      (expect params :to-equal '(1 2))
      (expect consumed :to-be 7)))
  (it "decodes secondary device attributes parameters"
    (multiple-value-bind (params consumed)
        (decode-device-attributes (%csi ">0;276;0" #\c))
      (expect params :to-equal '(0 276 0))
      (expect consumed :to-be-greater-than 0)))
  ;; A bare `ESC [ c' has no parameters.
  (it "has no parameters for a bare ESC [ c"
    (multiple-value-bind (params consumed)
        (decode-device-attributes (%csi "" #\c))
      (expect params :to-be-falsy)
      (expect consumed :to-be 3)))
  ;; Non-ESC-prefixed input is declined.
  (it "declines non-ESC-prefixed input"
    (multiple-value-bind (params consumed)
        (decode-device-attributes "hello")
      (expect params :to-be-falsy)
      (expect consumed :to-be 0)))
  ;; A bare `ESC [' with nothing after is declined before the `?'/`>' prefix
  ;; check even looks past the end of the string.
  (it "declines a bare ESC [ before the `?'/`>' prefix check looks past the end of the string"
    (multiple-value-bind (params consumed)
        (decode-device-attributes (format nil "~C[" #\Esc))
      (expect params :to-be-falsy)
      (expect consumed :to-be 0)))
  ;; Incomplete input is declined.
  (it "declines incomplete input"
    (multiple-value-bind (params consumed)
        (decode-device-attributes (format nil "~C[?1;2" #\Esc))
      (expect params :to-be-falsy)
      (expect consumed :to-be 0)))
  ;; Invalid offsets are declined without signaling.
  (it "declines a negative start offset without signaling"
    (multiple-value-bind (params consumed)
        (decode-device-attributes (%csi "?1;2" #\c) :start -1)
      (expect params :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines a fractional start offset without signaling"
    (multiple-value-bind (params consumed)
        (decode-device-attributes (%csi "?1;2" #\c) :start 1.5)
      (expect params :to-be-falsy)
      (expect consumed :to-be 0))))

(describe "make-key-event modifier normalization"
  (it "accepts a single modifier"
    (let ((event (make-key-event :type :special :code :enter :modifiers '(:control))))
      (%expect-key-event (event) :special :enter '(:control))))
  (it "deduplicates and sorts modifiers into canonical order regardless of input order/duplicates"
    (let ((event (make-key-event :type :special
                                 :code :enter
                                 :modifiers '(:reverse :alt :bold :alt))))
      (%expect-key-event (event) :special :enter '(:alt :bold :reverse))))
  (it "deduplicates repeated modifiers and drops non-keyword modifier entries"
    (let ((event (make-key-event :type :special
                                 :code :enter
                                 :modifiers '(:control :control :shift 1))))
      (%expect-key-event (event) :special :enter '(:control :shift)))))

(describe "unsupported-feature condition"
  (it "stores the feature and reports it in the condition message"
    (expect (lambda () (error 'unsupported-feature :feature :pty))
            :to-throw (lambda (condition)
                        (and (typep condition 'unsupported-feature)
                             (eq :pty (unsupported-feature-feature condition))
                             (search "Unsupported feature: PTY"
                                     (format nil "~A" condition)))))))

(describe "make-key-event argument validation"
  (it "rejects a non-keyword :type"
    (expect-non-type-error (make-key-event :type "bad" :code #\a)))
  (it "rejects a :character type whose :code is not a character"
    (expect-non-type-error (make-key-event :type :character :code :not-a-character)))
  (it "rejects a :special type whose :code is a character instead of a keyword"
    (expect-non-type-error (make-key-event :type :special :code #\a)))
  (it "rejects a :paste type with a character :code"
    (expect-non-type-error (make-key-event :type :paste :code #\a)))
  (it "rejects :kind :down, which is not a recognized event kind"
    (expect-non-type-error (make-key-event :type :character :code #\a :kind :down)))
  (it "rejects a non-string :text"
    (expect-non-type-error (make-key-event :type :character :code #\a :text :bad)))
  (it "rejects a non-character :shifted-key"
    (expect-non-type-error (make-key-event :type :character :code #\a :shifted-key "A"))))

(describe "decode-input over the single-key-event decode table"
  (dolist (case +single-decode-cases+)
    (destructuring-bind (input expected-type expected-code expected-modifiers) case
      (it (format nil "decodes ~S as (~S ~S ~S)"
                  input expected-type expected-code expected-modifiers)
        (let ((events (decode-input input)))
          (expect (length events) :to-be 1)
          (%expect-key-event ((first events))
                             expected-type expected-code expected-modifiers))))))

(describe "decode-key-sequence"
  (dolist (case +decode-key-sequence-cases+)
    (destructuring-bind (input expected-type expected-code expected-modifiers
                          expected-consumed &key (start 0))
        case
      (it (format nil "decodes ~S (start ~D) as (~S ~S ~S), consuming ~D"
                  input start expected-type expected-code expected-modifiers
                  expected-consumed)
        (multiple-value-bind (event consumed) (decode-key-sequence input :start start)
          (%expect-key-event (event) expected-type expected-code expected-modifiers)
          (expect consumed :to-be expected-consumed)))))
  (it "declines a negative start offset"
    (multiple-value-bind (event consumed) (decode-key-sequence "a" :start -1)
      (expect event :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines a fractional start offset"
    (multiple-value-bind (event consumed) (decode-key-sequence "a" :start 1.5)
      (expect event :to-be-falsy)
      (expect consumed :to-be 0)))
  (it "declines a start offset at the end of the buffer"
    (multiple-value-bind (event consumed) (decode-key-sequence "a" :start 1)
      (expect event :to-be-falsy)
      (expect consumed :to-be 0))))

(describe "decode-input event codes for CSI edge cases"
  (dolist (case +decoded-event-code-cases+)
    (destructuring-bind (input expected-codes) case
      (it (format nil "decodes ~S to codes ~S" input expected-codes)
        (let ((events (decode-input input)))
          (expect (length events) :to-be (length expected-codes))
          (loop for event in events
                for expected-code in expected-codes
                do (expect (key-event-code event) :to-be expected-code)))))))
