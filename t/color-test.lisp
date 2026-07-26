(in-package #:cl-tty-kit/test)

(defun %color-256-list (index)
  (multiple-value-list (color-256-to-rgb index)))

(defun %test-parse-hex-color ()
  (is (equal '(255 136 0) (multiple-value-list (parse-hex-color "#ff8800"))))
  (is (equal '(255 255 255) (multiple-value-list (parse-hex-color "ffffff"))))
  (is (equal '(0 0 0) (multiple-value-list (parse-hex-color "#000000"))))
  ;; Short #rgb form doubles each nibble.
  (is (equal '(255 136 0) (multiple-value-list (parse-hex-color "#f80"))))
  (is (equal '(255 136 0) (multiple-value-list (parse-hex-color "f80"))))
  (signals (error c) (parse-hex-color "#12") (is c))
  (signals (error c) (parse-hex-color "#gg0000") (is c)))

(defun %test-color-256-to-rgb ()
  (is (equal '(0 0 0) (%color-256-list 0)))
  (is (equal '(255 255 255) (%color-256-list 15)))
  (is (equal '(0 0 0) (%color-256-list 16)))
  (is (equal '(0 0 255) (%color-256-list 21)))
  (is (equal '(255 255 255) (%color-256-list 231)))
  (is (equal '(8 8 8) (%color-256-list 232)))
  (is (equal '(238 238 238) (%color-256-list 255)))
  (signals (error c) (color-256-to-rgb 256) (is c))
  (signals (error c) (color-256-to-rgb -1) (is c)))

(defun %test-rgb-to-256 ()
  (is (= 16 (rgb-to-256 0 0 0)))
  (is (= 231 (rgb-to-256 255 255 255)))
  ;; Pure blue lands on the cube's blue corner.
  (is (= 21 (rgb-to-256 0 0 255)))
  ;; Mid gray prefers the smoother grayscale ramp over the cube.
  (is (= 244 (rgb-to-256 128 128 128)))
  ;; Round-trip: a cube color maps back to itself.
  (multiple-value-bind (r g b) (color-256-to-rgb 141)
    (is (= 141 (rgb-to-256 r g b))))
  (signals (error c) (rgb-to-256 256 0 0) (is c)))

(defun %test-blend-colors ()
  (is (equal '(128 128 128) (blend-colors '(0 0 0) '(255 255 255) 1/2)))
  (is (equal '(0 0 0) (blend-colors '(0 0 0) '(255 255 255) 0)))
  ;; Ratio is clamped to [0, 1].
  (is (equal '(255 255 255) (blend-colors '(0 0 0) '(255 255 255) 2)))
  (is (equal '(0 0 0) (blend-colors '(0 0 0) '(255 255 255) -1)))
  (is (equal '(10 20 30) (blend-colors '(10 20 30) '(200 200 200) 0))))

(defun %test-color-gradient ()
  (is (equal '((0 0 0) (128 128 128) (255 255 255))
             (color-gradient '(0 0 0) '(255 255 255) 3)))
  ;; A single step yields just the start color.
  (is (equal '((0 0 0)) (color-gradient '(0 0 0) '(255 255 255) 1)))
  ;; Endpoints are exact; the count matches STEPS.
  (let ((ramp (color-gradient '(0 0 0) '(10 10 10) 5)))
    (is (= 5 (length ramp)))
    (is (equal '(0 0 0) (first ramp)))
    (is (equal '(10 10 10) (car (last ramp)))))
  (signals (error c) (color-gradient '(0 0 0) '(1 1 1) 0) (is c)))

(defun %test-rgb-to-ansi16 ()
  (is (= 0 (rgb-to-ansi16 0 0 0)))
  (is (= 15 (rgb-to-ansi16 255 255 255)))
  (is (= 9 (rgb-to-ansi16 255 0 0)))
  (is (= 1 (rgb-to-ansi16 128 0 0)))
  (signals (error c) (rgb-to-ansi16 256 0 0) (is c)))

(defun %test-color-luminance ()
  (is (= 0 (color-luminance 0 0 0)))
  (is (= 255 (color-luminance 255 255 255)))
  (is (= 76 (color-luminance 255 0 0)))
  ;; Green is perceived brighter than red or blue at full intensity.
  (is (> (color-luminance 0 255 0) (color-luminance 255 0 0)))
  (is (> (color-luminance 255 0 0) (color-luminance 0 0 255)))
  (signals (error c) (color-luminance -1 0 0) (is c)))

(defun %test-hsl ()
  (is (equal '(0 100 50) (multiple-value-list (rgb-to-hsl 255 0 0))))
  (is (equal '(120 100 50) (multiple-value-list (rgb-to-hsl 0 255 0))))
  (is (equal '(0 0 100) (multiple-value-list (rgb-to-hsl 255 255 255))))
  (is (equal '(0 0 50) (multiple-value-list (rgb-to-hsl 128 128 128))))
  ;; Blue as the dominant channel selects the hue formula's third branch;
  ;; lightness above 50% selects the saturation formula's other branch.
  (is (equal '(240 100 89) (multiple-value-list (rgb-to-hsl 200 200 255))))
  (is (equal '(240 100 50) (multiple-value-list (rgb-to-hsl 0 0 255))))
  ;; Pure colors round-trip exactly.
  (is (equal '(255 0 0) (multiple-value-list (hsl-to-rgb 0 100 50))))
  (is (equal '(0 0 255) (multiple-value-list (hsl-to-rgb 240 100 50))))
  (is (equal '(128 128 128) (multiple-value-list (hsl-to-rgb 0 0 50))))
  ;; Lightness below 50% selects Q's other branch.
  (is (equal '(153 0 0) (multiple-value-list (hsl-to-rgb 0 100 30)))))

(defun %test-hsv ()
  (is (equal '(0 100 100) (multiple-value-list (rgb-to-hsv 255 0 0))))
  (is (equal '(120 100 100) (multiple-value-list (rgb-to-hsv 0 255 0))))
  (is (equal '(0 0 0) (multiple-value-list (rgb-to-hsv 0 0 0))))
  ;; Blue as the dominant channel selects the hue formula's third branch.
  (is (equal '(240 100 100) (multiple-value-list (rgb-to-hsv 0 0 255))))
  (is (equal '(255 0 0) (multiple-value-list (hsv-to-rgb 0 100 100))))
  (is (equal '(0 0 255) (multiple-value-list (hsv-to-rgb 240 100 100))))
  (is (equal '(0 0 0) (multiple-value-list (hsv-to-rgb 0 0 0))))
  ;; Every ECASE sextant of the hue wheel, not just i=0 and i=4.
  (is (equal '(128 255 0) (multiple-value-list (hsv-to-rgb 90 100 100))))
  (is (equal '(0 255 128) (multiple-value-list (hsv-to-rgb 150 100 100))))
  (is (equal '(0 128 255) (multiple-value-list (hsv-to-rgb 210 100 100))))
  (is (equal '(255 0 128) (multiple-value-list (hsv-to-rgb 330 100 100)))))

(defun %test-parse-and-contrast ()
  (is (equal '(255 136 0) (multiple-value-list (parse-color "#ff8800"))))
  (is (equal '(1 2 3) (multiple-value-list (parse-color "rgb(1, 2, 3)"))))
  (is (equal '(1 2 3) (multiple-value-list (parse-color "rgb(1 2 3)"))))
  ;; Trailing whitespace after the closing paren is tolerated, unlike other
  ;; trailing content (see "rgb(1, 2, 3)junk" below).
  (is (equal '(1 2 3) (multiple-value-list (parse-color "rgb(1, 2, 3)  "))))
  (signals (error c) (parse-color "rgb(1, 2, x)") (is c))
  (signals (error c) (parse-color "rgb(256, 0, 0)") (is c))
  (signals (error c) (parse-color "rgb(1234, 0, 0)") (is c))
  (signals (error c) (parse-color "rgb(-1, 0, 0)") (is c))
  (signals (error c) (parse-color "rgb(1, 2") (is c))
  ;; Well-formed parens but the wrong component count.
  (signals (error c) (parse-color "rgb(1, 2)") (is c))
  (signals (error c) (parse-color "rgb(1, 2, 3, 4)") (is c))
  (signals (error c) (parse-color "rgb(1, 2, 3)junk") (is c))
  (is (equal '(128 0 0) (multiple-value-list (parse-color "red"))))
  (is (equal '(0 255 0) (multiple-value-list (parse-color :bright-green))))
  (let ((before (find-symbol "NOT-A-COLOR-DO-NOT-INTERN" :keyword)))
    (signals (error c) (parse-color "not-a-color-do-not-intern") (is c))
    (is (eq before (find-symbol "NOT-A-COLOR-DO-NOT-INTERN" :keyword))))
  ;; contrast-color picks the readable extreme.
  (is (equal '(0 0 0) (contrast-color 240 240 240)))
  (is (equal '(255 255 255) (contrast-color 10 10 10))))

(defun test-color ()
  (%test-parse-hex-color)
  (%test-color-256-to-rgb)
  (%test-rgb-to-256)
  (%test-blend-colors)
  (%test-color-gradient)
  (%test-rgb-to-ansi16)
  (%test-color-luminance)
  (%test-hsl)
  (%test-hsv)
  (%test-parse-and-contrast)
  t)
