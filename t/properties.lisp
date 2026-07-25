(defpackage #:cl-tty-kit/property-tests
  (:use #:cl #:cl-tty-kit)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
                #:expect #:it-property #:run-all)
  (:export #:run-tests))

(in-package #:cl-tty-kit/property-tests)

;;; --------------------------------------------------------------------------
;;; Property-based invariants for the pure core, built on nerima-lisp/cl-weave.
;;;
;;; This is a FIRST-CLASS test system (wired into cl-tty-kit's ASDF test-op),
;;; not a contrib add-on. Where t/*.lisp pins behaviour with worked examples,
;;; each block below states an algebraic law the function must satisfy for ALL
;;; inputs and lets cl-weave's generators search the space for a counterexample.
;;; The laws are the specification; the implementations are checked against them.
;;; --------------------------------------------------------------------------

(describe "clamp keeps a value within an ordered bound"
  (it-property "the result lies within [lo, hi]"
      ((value (cl-weave:gen-integer :min -1000 :max 1000))
       (lo (cl-weave:gen-integer :min -100 :max 100))
       (width (cl-weave:gen-integer :min 0 :max 200)))
    (let ((clamped (cl-tty-kit::clamp value lo (+ lo width))))
      (expect (<= lo clamped (+ lo width)))))
  (it-property "clamping an already-clamped value changes nothing"
      ((value (cl-weave:gen-integer :min -1000 :max 1000))
       (lo (cl-weave:gen-integer :min -100 :max 100))
       (width (cl-weave:gen-integer :min 0 :max 200)))
    (let* ((hi (+ lo width))
           (once (cl-tty-kit::clamp value lo hi)))
      (expect (= once (cl-tty-kit::clamp once lo hi))))))

(describe "hex colour parsing inverts formatting"
  (it-property "#RRGGBB round-trips through parse-hex-color"
      ((r (cl-weave:gen-integer :min 0 :max 255))
       (g (cl-weave:gen-integer :min 0 :max 255))
       (b (cl-weave:gen-integer :min 0 :max 255)))
    (multiple-value-bind (pr pg pb)
        (parse-hex-color (format nil "#~2,'0X~2,'0X~2,'0X" r g b))
      (expect (and (= r pr) (= g pg) (= b pb)))))
  (it-property "color-256-to-rgb yields three in-range channels"
      ((index (cl-weave:gen-integer :min 0 :max 255)))
    (multiple-value-bind (r g b) (color-256-to-rgb index)
      (expect (and (<= 0 r 255) (<= 0 g 255) (<= 0 b 255)))))
  (it-property "rgb-to-256 yields a valid palette index"
      ((r (cl-weave:gen-integer :min 0 :max 255))
       (g (cl-weave:gen-integer :min 0 :max 255))
       (b (cl-weave:gen-integer :min 0 :max 255)))
    (expect (typep (rgb-to-256 r g b) '(integer 0 255)))))

(describe "derived rectangle edges match origin plus extent"
  (it-property "rect-right = x + width and rect-bottom = y + height"
      ((x (cl-weave:gen-integer :min 0 :max 500))
       (y (cl-weave:gen-integer :min 0 :max 500))
       (w (cl-weave:gen-integer :min 0 :max 500))
       (h (cl-weave:gen-integer :min 0 :max 500)))
    (let ((rect (make-rect :x x :y y :width w :height h)))
      (expect (and (= (rect-right rect) (+ x w))
                   (= (rect-bottom rect) (+ y h)))))))

(describe "padding and truncation respect their width contract"
  (it-property "pad-string never falls short of the requested width"
      ((text (cl-weave:gen-string :min-length 0 :max-length 20))
       (width (cl-weave:gen-integer :min 0 :max 40)))
    (expect (>= (string-width (pad-string text width)) width)))
  (it-property "pad-string never shrinks the input"
      ((text (cl-weave:gen-string :min-length 0 :max-length 20))
       (width (cl-weave:gen-integer :min 0 :max 40)))
    (expect (>= (string-width (pad-string text width)) (string-width text))))
  (it-property "truncate-string never exceeds the requested width"
      ((text (cl-weave:gen-string :min-length 0 :max-length 30))
       (width (cl-weave:gen-integer :min 0 :max 20)))
    (expect (<= (string-width (truncate-string text width)) width)))
  (it-property "expand-tabs removes every tab character"
      ((text (cl-weave:gen-string :min-length 0 :max-length 20
                                  :alphabet #.(coerce (list #\a #\b #\Space #\Tab)
                                                      'string))))
    (expect (not (find #\Tab (expand-tabs text))))))

(describe "decode-sgr inverts style-ansi for indexed colours"
  (it-property "a foreground index round-trips through SGR encoding"
      ((index (cl-weave:gen-integer :min 0 :max 255)))
    (expect (equal (make-style (style-fg index))
                   (decode-sgr (style-ansi (style-fg index)))))))

(describe "%split-on-char inverts joining with the same delimiter"
  (it-property "splitting a semicolon-joined triple recovers the original pieces"
      ((a (cl-weave:gen-string :min-length 0 :max-length 8 :alphabet "abcXYZ"))
       (b (cl-weave:gen-string :min-length 0 :max-length 8 :alphabet "abcXYZ"))
       (c (cl-weave:gen-string :min-length 0 :max-length 8 :alphabet "abcXYZ")))
    (expect (equal (list a b c)
                   (cl-tty-kit::%split-on-char (format nil "~A;~A;~A" a b c) #\;)))))

(describe "blend-colors is idempotent when both colors match"
  (it-property "blending a color with itself returns that color at any ratio"
      ((rgb (cl-weave:gen-tuple (cl-weave:gen-integer :min 0 :max 255)
                                (cl-weave:gen-integer :min 0 :max 255)
                                (cl-weave:gen-integer :min 0 :max 255)))
       (ratio-numerator (cl-weave:gen-integer :min 0 :max 100)))
    (expect (equal rgb (blend-colors rgb rgb (/ ratio-numerator 100))))))

(describe "render-diff never exceeds a full repaint"
  ;; A model-based property, not a pure algebraic law like the ones above:
  ;; GEN-STATE-MACHINE drives SCREEN-COPY/SCREEN-PUT-CELL through random
  ;; mutation sequences and replays the resulting screen states, so RENDER-DIFF
  ;; is checked against every adjacent (PREVIOUS, CURRENT) pair the trace
  ;; reaches rather than the fixed handful of examples in t/render-diff.lisp.
  ;; %PREFERRED-DIFF-COMMANDS (src/render-diff.lisp) is documented to fall
  ;; back to a full repaint whenever the diff would not be shorter, so this
  ;; length bound is a real invariant, not an incidental one.
  (it-property "the diff for any reachable screen state stays no longer than RENDER-SCREEN"
      ((trace (cl-weave:gen-state-machine
               (make-screen 4 3)
               (lambda (screen event)
                 (let ((next (screen-copy screen)))
                   (destructuring-bind (x y ch) event
                     (screen-put-cell next x y ch))
                   next))
               (cl-weave:gen-tuple (cl-weave:gen-integer :min 0 :max 3)
                                   (cl-weave:gen-integer :min 0 :max 2)
                                   (cl-weave:gen-character :alphabet "ab "))
               :min-length 0 :max-length 8)))
    (loop for (previous current) on (getf trace :states)
          while current
          do (expect (<= (length (render-diff current previous))
                          (length (render-screen current)))))))

(defun run-tests ()
  "Run every property block registered above and return true iff all passed."
  (run-all :reporter :spec))
