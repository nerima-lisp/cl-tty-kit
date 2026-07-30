(in-package #:cl-tty-kit/test)

(defun %ansi-string (&rest parts)
  (with-output-to-string (out)
    (dolist (part parts)
      (write-string part out))))

(defun %single-cell-render-output (char style)
  (let ((screen (make-screen 1 1)))
    (screen-put-cell screen 0 0 char :style style)
    (render-screen screen)))

(defparameter +render-style-cases+
  `((#\B (:bold) ,(ansi-bold) t)
    (#\I (:italic) ,(format nil "~C[3m" #\Esc) t)
    (#\U (:bold :underline) ,(format nil "~C[1;4m" #\Esc) t)
    (#\F ((:fg 196)) ,(format nil "~C[38;5;196m" #\Esc) t)
    (#\B ((:bg 17)) ,(format nil "~C[48;5;17m" #\Esc) t)
    (#\R ((:fg 1 2 3) (:bg 4 5 6))
     ,(format nil "~C[38;2;1;2;3;48;2;4;5;6m" #\Esc)
     t)
    (#\K (:blink) ,(format nil "~C[5m" #\Esc) t)
    (#\S (:strikethrough) ,(format nil "~C[9m" #\Esc) t)
    (#\H (:hidden) ,(format nil "~C[8m" #\Esc) t)
    (#\Z (:no-such-modifier) nil nil)))

(defparameter +render-cursor-cases+
  `((,(make-cursor :x 3 :y 4)
     ,(%ansi-string (ansi-move-cursor 5 4)
                    (ansi-show-cursor)))
    (,(make-cursor :x 1 :y 2 :visible nil)
     ,(%ansi-string (ansi-move-cursor 3 2)
                    (ansi-hide-cursor)))))

(defun %assert-render-style-case (char style sgr expect-reset-p)
  (let ((output (%single-cell-render-output char style)))
    (if sgr
        (expect (search sgr output))
        (expect output :to-equal
                (%ansi-string (ansi-clear-screen)
                              (ansi-move-cursor 1 1)
                              (string char))))
    (when expect-reset-p
      (expect (search (ansi-reset-style) output)))
    (expect (search (string char) output))))

(defun %assert-render-cursor-case (cursor expected)
  (expect (render-cursor cursor) :to-equal expected))

(describe "single-cell style rendering"
  (dolist (style-case +render-style-cases+)
    (destructuring-bind (char style sgr expect-reset-p) style-case
      (it (format nil "renders ~C with style ~S" char style)
        (%assert-render-style-case char style sgr expect-reset-p)))))

;; STYLE-ANSI: public SGR emitter over normalized style lists.
(describe "style-ansi"
  (it "returns an empty string for unsupported or malformed style forms"
    (expect (style-ansi 42) :to-equal "")
    (expect (style-ansi :foo) :to-equal "")
    (expect (style-ansi (list :fg 1 2)) :to-equal "")
    (expect (style-ansi) :to-equal "")
    (expect (style-ansi :no-such-modifier) :to-equal ""))
  (it "emits SGR codes for supported modifiers and colors"
    (expect (style-ansi :bold) :to-equal (ansi-bold))
    (expect (style-ansi :bold :underline) :to-equal (format nil "~C[1;4m" #\Esc))
    (expect (style-ansi (style-fg 208)) :to-equal (format nil "~C[38;5;208m" #\Esc))
    (expect (style-ansi :bold (style-fg 196) (style-bg 17))
            :to-equal (format nil "~C[1;38;5;196;48;5;17m" #\Esc))))

;; NAMED-COLOR: the sixteen standard palette indices, usable with STYLE-FG.
(describe "named-color"
  (it "maps the sixteen standard palette names to their indices"
    (expect (named-color :red) :to-be 1)
    (expect (named-color :white) :to-be 7)
    (expect (named-color :gray) :to-be 8)
    (expect (named-color :grey) :to-be 8)
    (expect (named-color :bright-white) :to-be 15))
  (it "composes with style-fg to produce the matching SGR code"
    (expect (style-ansi (style-fg (named-color :bright-red)))
            :to-equal (format nil "~C[38;5;9m" #\Esc)))
  (it "rejects an unknown color name"
    (expect (lambda () (named-color :not-a-color)) :to-throw)))

;; STYLE-MERGE: modifiers union, OVERRIDE's colors win.
(describe "style-merge"
  (it "unions modifiers, with OVERRIDE's colors winning over BASE's"
    (expect (style-merge '(:bold) '(:italic)) :to-equal '(:bold :italic))
    (expect (style-merge (make-style (style-fg 1)) (make-style (style-fg 2)))
            :to-equal '((:fg 2)))
    (expect (style-merge (make-style :bold (style-fg 1)) (make-style (style-bg 2)))
            :to-equal '(:bold (:fg 1) (:bg 2)))
    (expect (style-merge nil '(:bold)) :to-equal '(:bold))))

;; MAKE-CELL's STYLE accepts a bare, unwrapped modifier keyword too, not
;; only a style list -- %CELL-STYLE-ITEMS wraps it in a list itself.
(describe "make-cell"
  (it "accepts a bare, unwrapped modifier keyword for :style, not only a style list"
    (expect (cell-style (make-cell :char #\x :style :bold)) :to-equal '(:bold))))

;; CELL-BLANK-P: a space with no rendered style is blank.
(describe "cell-blank-p"
  (it "treats a space with no rendered style as blank"
    (expect (cell-blank-p (make-cell)))
    (expect (not (cell-blank-p (make-cell :char #\x))))
    (expect (not (cell-blank-p (make-cell :char #\Space :style '(:bold)))))
    (expect (cell-blank-p (make-cell :char #\Space :style '(:no-such-modifier)))))
  (it "rejects a non-cell argument"
    (expect (lambda () (cell-blank-p :not-a-cell)) :to-throw)))

;; Extended underline styles and overline emit their SGR sub-parameters.
(describe "extended underline styles and the underline color channel"
  (it "emits SGR sub-parameters for curly/double underline and overline"
    (expect (style-ansi :curly-underline) :to-equal (format nil "~C[4:3m" #\Esc))
    (expect (style-ansi :double-underline) :to-equal (format nil "~C[4:2m" #\Esc))
    (expect (style-ansi :overline) :to-equal (format nil "~C[53m" #\Esc)))
  ;; Underline color is a third color channel (SGR 58).
  (it "emits underline color as SGR 58, a third color channel alongside fg/bg"
    (expect (style-ansi :underline (style-underline-color 9))
            :to-equal (format nil "~C[4;58;5;9m" #\Esc))
    (expect (style-ansi (style-underline-color 1 2 3))
            :to-equal (format nil "~C[58;2;1;2;3m" #\Esc)))
  ;; A later underline color overrides an earlier one, like fg/bg.
  (it "lets a later underline color override an earlier one, like fg/bg"
    (expect (make-style (style-underline-color 1) (style-underline-color 5))
            :to-equal '((:underline-color 5)))))

;; DECODE-SGR is the inverse of STYLE-ANSI.
(describe "decode-sgr"
  (it "inverts style-ansi for a basic and an extended-color style"
    (expect (decode-sgr (format nil "~C[1;31m" #\Esc)) :to-equal '(:bold (:fg 1)))
    (expect (decode-sgr (format nil "~C[38;5;208m" #\Esc)) :to-equal '((:fg 208))))
  (it "rejects out-of-range or overflowing color channel values"
    (expect (decode-sgr "38;5;256") :to-be nil)
    (expect (decode-sgr "38;5;1234567890123") :to-be nil)
    (expect (decode-sgr "38;2;1;2;256") :to-be nil)
    (expect (decode-sgr "38;2;1;2;1234567890123") :to-be nil))
  (it "returns a null style for a bare reset, and reports reset-p via the second value"
    (expect (decode-sgr (format nil "~C[0m" #\Esc)) :to-be nil)
    (multiple-value-bind (style reset-p) (decode-sgr (format nil "~C[0m" #\Esc))
      (expect style :to-be nil)
      (expect reset-p)))
  (it "round-trips through style-ansi for a full modifier+color combination"
    (expect (decode-sgr (style-ansi :bold (style-fg 196) (style-bg 17)))
            :to-equal (make-style :bold (style-fg 196) (style-bg 17)))))

;; The full basic/extended color and color-reset grammar of DECODE-SGR: each
;; case pairs an SGR parameter body with the normalized style it must recover.
(describe "decode-sgr's color and color-reset grammar"
  (dolist (sgr-case
           '(("91"         ((:fg 9)))               ; bright foreground (90-97)
             ("41"         ((:bg 1)))               ; background (40-47)
             ("101"        ((:bg 9)))               ; bright background (100-107)
             ("48;5;9"     ((:bg 9)))               ; extended indexed background
             ("58;5;9"     ((:underline-color 9)))  ; extended underline color
             ("38;2;1;2;3" ((:fg 1 2 3)))           ; truecolor foreground
             ("31;39"      nil)                     ; 39 clears the foreground
             ("1;31;39"    (:bold))                 ; a color reset spares other modifiers
             ("41;49"      nil)                     ; 49 clears the background
             ("58;5;9;59"  nil)                     ; 59 clears the underline color
             ("38"         nil)                     ; truncated extended color
             ("999"        nil)))                   ; unknown parameter ignored
    (destructuring-bind (body expected) sgr-case
      (it (format nil "decode-sgr ~S" body)
        (expect (decode-sgr body) :to-equal expected)))))

;; PARSE-STYLED-STRING recovers text and accumulated style per run, and
;; tolerates malformed or non-SGR escape sequences without losing the
;; surrounding text.
(describe "parse-styled-string"
  (it "recovers text and accumulated style per run"
    (expect (parse-styled-string
             (concatenate 'string (style-ansi :bold) "A"
                          (style-ansi (style-fg 1)) "B"
                          (ansi-reset-style) "C"))
            :to-equal '(("A" :bold) ("B" :bold (:fg 1)) ("C"))))
  (it "unterminated CSI yields no segments"
    (expect (parse-styled-string (format nil "~C[1" #\Esc)) :to-be nil))
  (it "non-SGR CSI (cursor move) is dropped"
    (expect (parse-styled-string (format nil "~C[HX" #\Esc)) :to-equal '(("X"))))
  (it "non-CSI escape is skipped, surrounding text kept"
    (expect (parse-styled-string (format nil "A~CMB" #\Esc)) :to-equal '(("AB")))))

(describe "render-screen"
  (it "writes directly to a stream and returns it"
    (let ((screen (make-screen 2 1))
          (stream (make-string-output-stream)))
      (screen-put-cell screen 0 0 #\H)
      (screen-put-cell screen 1 0 #\i)
      (expect-render-stream-output (stream (render-screen screen stream))
                                    (render-screen screen)))))

(describe "render-cursor"
  (it "writes directly to a stream and returns it"
    (let ((cursor (make-cursor :x 0 :y 0 :visible nil))
          (stream (make-string-output-stream)))
      (expect-render-stream-output
       (stream (render-cursor cursor stream))
       (%ansi-string (ansi-move-cursor 1 1)
                     (ansi-hide-cursor)))))
  (dolist (cursor-case +render-cursor-cases+)
    (destructuring-bind (cursor expected) cursor-case
      (it (format nil "renders cursor ~S" cursor)
        (%assert-render-cursor-case cursor expected)))))

(describe "render-frame"
  (it "combines a screen render with the cursor escape"
    (let ((screen (make-screen 2 1))
          (cursor (make-cursor :x 1 :y 0)))
      (screen-put-cell screen 0 0 #\H)
      (screen-put-cell screen 1 0 #\i)
      (expect (render-frame screen cursor)
              :to-equal (%ansi-string (render-screen screen)
                                      (ansi-move-cursor 1 2)
                                      (ansi-show-cursor)))))
  (it "writes directly to a stream and returns it"
    (let ((screen (make-screen 2 1))
          (cursor (make-cursor :x 0 :y 0 :visible nil))
          (stream (make-string-output-stream)))
      (screen-put-cell screen 0 0 #\H)
      (screen-put-cell screen 1 0 #\i)
      (expect-render-stream-output
       (stream (render-frame screen cursor stream))
       (%ansi-string (render-screen screen)
                     (ansi-move-cursor 1 1)
                     (ansi-hide-cursor))))))
