(in-package #:cl-tty-kit/test)

(defun %color-256-list (index)
  (multiple-value-list (color-256-to-rgb index)))

(describe "parse-hex-color"
  (it "parses a leading #"
    (expect (multiple-value-list (parse-hex-color "#ff8800")) :to-equal '(255 136 0)))
  (it "parses without a leading #"
    (expect (multiple-value-list (parse-hex-color "ffffff")) :to-equal '(255 255 255)))
  (it "parses black"
    (expect (multiple-value-list (parse-hex-color "#000000")) :to-equal '(0 0 0)))
  (it "doubles each nibble of the short #rgb form"
    (expect (multiple-value-list (parse-hex-color "#f80")) :to-equal '(255 136 0))
    (expect (multiple-value-list (parse-hex-color "f80")) :to-equal '(255 136 0)))
  (it "rejects the wrong digit count"
    (expect (lambda () (parse-hex-color "#12")) :to-throw))
  (it "rejects a non-hex digit"
    (expect (lambda () (parse-hex-color "#gg0000")) :to-throw)))

(describe "color-256-to-rgb"
  (it "maps the basic 16-color and grayscale boundaries"
    (expect (%color-256-list 0) :to-equal '(0 0 0))
    (expect (%color-256-list 15) :to-equal '(255 255 255))
    (expect (%color-256-list 16) :to-equal '(0 0 0))
    (expect (%color-256-list 21) :to-equal '(0 0 255))
    (expect (%color-256-list 231) :to-equal '(255 255 255))
    (expect (%color-256-list 232) :to-equal '(8 8 8))
    (expect (%color-256-list 255) :to-equal '(238 238 238)))
  (it "rejects an out-of-range index"
    (expect (lambda () (color-256-to-rgb 256)) :to-throw)
    (expect (lambda () (color-256-to-rgb -1)) :to-throw)))

(describe "rgb-to-256"
  (it "maps black and white to the cube corners"
    (expect (rgb-to-256 0 0 0) :to-be 16)
    (expect (rgb-to-256 255 255 255) :to-be 231))
  (it "maps pure blue to the cube's blue corner"
    (expect (rgb-to-256 0 0 255) :to-be 21))
  (it "prefers the grayscale ramp over the cube for mid gray"
    (expect (rgb-to-256 128 128 128) :to-be 244))
  (it "round-trips a cube color back to itself"
    (multiple-value-bind (r g b) (color-256-to-rgb 141)
      (expect (rgb-to-256 r g b) :to-be 141)))
  (it "rejects an out-of-range channel"
    (expect (lambda () (rgb-to-256 256 0 0)) :to-throw)))

(describe "blend-colors"
  (it "blends at the midpoint"
    (expect (blend-colors '(0 0 0) '(255 255 255) 1/2) :to-equal '(128 128 128)))
  (it "returns the start color at ratio 0"
    (expect (blend-colors '(0 0 0) '(255 255 255) 0) :to-equal '(0 0 0)))
  (it "clamps a ratio above 1 to the end color"
    (expect (blend-colors '(0 0 0) '(255 255 255) 2) :to-equal '(255 255 255)))
  (it "clamps a ratio below 0 to the start color"
    (expect (blend-colors '(0 0 0) '(255 255 255) -1) :to-equal '(0 0 0)))
  (it "at ratio 0, ignores the end color entirely"
    (expect (blend-colors '(10 20 30) '(200 200 200) 0) :to-equal '(10 20 30))))

(describe "color-gradient"
  (it "interpolates evenly across the requested step count"
    (expect (color-gradient '(0 0 0) '(255 255 255) 3)
            :to-equal '((0 0 0) (128 128 128) (255 255 255))))
  (it "a single step yields just the start color"
    (expect (color-gradient '(0 0 0) '(255 255 255) 1) :to-equal '((0 0 0))))
  (it "endpoints are exact and the count matches steps"
    (let ((ramp (color-gradient '(0 0 0) '(10 10 10) 5)))
      (expect (length ramp) :to-be 5)
      (expect (first ramp) :to-equal '(0 0 0))
      (expect (car (last ramp)) :to-equal '(10 10 10))))
  (it "rejects a zero step count"
    (expect (lambda () (color-gradient '(0 0 0) '(1 1 1) 0)) :to-throw))
  (it "rejects a fractional step count"
    (expect (lambda () (color-gradient '(0 0 0) '(1 1 1) 1.5))
            :to-throw (lambda (c) (not (typep c 'type-error))))))

(describe "rgb-to-ansi16"
  (it "maps black and white to indices 0 and 15"
    (expect (rgb-to-ansi16 0 0 0) :to-be 0)
    (expect (rgb-to-ansi16 255 255 255) :to-be 15))
  (it "maps bright red to index 9 and dim red to index 1"
    (expect (rgb-to-ansi16 255 0 0) :to-be 9)
    (expect (rgb-to-ansi16 128 0 0) :to-be 1))
  (it "rejects an out-of-range channel"
    (expect (lambda () (rgb-to-ansi16 256 0 0)) :to-throw)))

(describe "color-luminance"
  (it "maps black to 0 and white to 255"
    (expect (color-luminance 0 0 0) :to-be 0)
    (expect (color-luminance 255 255 255) :to-be 255))
  (it "computes red's perceived luminance"
    (expect (color-luminance 255 0 0) :to-be 76))
  (it "perceives green as brighter than red or blue at full intensity"
    (expect (color-luminance 0 255 0) :to-be-greater-than (color-luminance 255 0 0))
    (expect (color-luminance 255 0 0) :to-be-greater-than (color-luminance 0 0 255)))
  (it "rejects a negative channel"
    (expect (lambda () (color-luminance -1 0 0)) :to-throw)))

(describe "rgb-to-hsl and hsl-to-rgb"
  (it "converts primary and neutral colors to HSL"
    (expect (multiple-value-list (rgb-to-hsl 255 0 0)) :to-equal '(0 100 50))
    (expect (multiple-value-list (rgb-to-hsl 0 255 0)) :to-equal '(120 100 50))
    (expect (multiple-value-list (rgb-to-hsl 255 255 255)) :to-equal '(0 0 100))
    (expect (multiple-value-list (rgb-to-hsl 128 128 128)) :to-equal '(0 0 50)))
  (it "selects the hue formula's blue branch and the saturation formula's high-lightness branch"
    (expect (multiple-value-list (rgb-to-hsl 200 200 255)) :to-equal '(240 100 89)))
  (it "converts blue at 50% lightness to HSL"
    (expect (multiple-value-list (rgb-to-hsl 0 0 255)) :to-equal '(240 100 50)))
  (it "round-trips pure colors exactly"
    (expect (multiple-value-list (hsl-to-rgb 0 100 50)) :to-equal '(255 0 0))
    (expect (multiple-value-list (hsl-to-rgb 240 100 50)) :to-equal '(0 0 255))
    (expect (multiple-value-list (hsl-to-rgb 0 0 50)) :to-equal '(128 128 128)))
  (it "selects Q's other branch when lightness is below 50%"
    (expect (multiple-value-list (hsl-to-rgb 0 100 30)) :to-equal '(153 0 0))))

(describe "rgb-to-hsv and hsv-to-rgb"
  (it "converts primary and neutral colors to HSV"
    (expect (multiple-value-list (rgb-to-hsv 255 0 0)) :to-equal '(0 100 100))
    (expect (multiple-value-list (rgb-to-hsv 0 255 0)) :to-equal '(120 100 100))
    (expect (multiple-value-list (rgb-to-hsv 0 0 0)) :to-equal '(0 0 0)))
  (it "selects the hue formula's blue branch"
    (expect (multiple-value-list (rgb-to-hsv 0 0 255)) :to-equal '(240 100 100)))
  (it "round-trips primary and neutral colors"
    (expect (multiple-value-list (hsv-to-rgb 0 100 100)) :to-equal '(255 0 0))
    (expect (multiple-value-list (hsv-to-rgb 240 100 100)) :to-equal '(0 0 255))
    (expect (multiple-value-list (hsv-to-rgb 0 0 0)) :to-equal '(0 0 0)))
  (it "covers every ECASE sextant of the hue wheel, not just i=0 and i=4"
    (expect (multiple-value-list (hsv-to-rgb 90 100 100)) :to-equal '(128 255 0))
    (expect (multiple-value-list (hsv-to-rgb 150 100 100)) :to-equal '(0 255 128))
    (expect (multiple-value-list (hsv-to-rgb 210 100 100)) :to-equal '(0 128 255))
    (expect (multiple-value-list (hsv-to-rgb 330 100 100)) :to-equal '(255 0 128))))

(describe "parse-color"
  (it "parses a hex string"
    (expect (multiple-value-list (parse-color "#ff8800")) :to-equal '(255 136 0)))
  (it "parses rgb(...) with comma or space separators"
    (expect (multiple-value-list (parse-color "rgb(1, 2, 3)")) :to-equal '(1 2 3))
    (expect (multiple-value-list (parse-color "rgb(1 2 3)")) :to-equal '(1 2 3)))
  (it "tolerates trailing whitespace after the closing paren"
    (expect (multiple-value-list (parse-color "rgb(1, 2, 3)  ")) :to-equal '(1 2 3)))
  (it "rejects a non-numeric component"
    (expect (lambda () (parse-color "rgb(1, 2, x)")) :to-throw))
  (it "rejects an out-of-range component"
    (expect (lambda () (parse-color "rgb(256, 0, 0)")) :to-throw)
    (expect (lambda () (parse-color "rgb(1234, 0, 0)")) :to-throw)
    (expect (lambda () (parse-color "rgb(-1, 0, 0)")) :to-throw))
  (it "rejects an unterminated rgb(...)"
    (expect (lambda () (parse-color "rgb(1, 2")) :to-throw))
  (it "rejects the wrong component count"
    (expect (lambda () (parse-color "rgb(1, 2)")) :to-throw)
    (expect (lambda () (parse-color "rgb(1, 2, 3, 4)")) :to-throw))
  (it "rejects trailing content after a well-formed rgb(...)"
    (expect (lambda () (parse-color "rgb(1, 2, 3)junk")) :to-throw))
  (it "resolves a named color, by string or keyword"
    (expect (multiple-value-list (parse-color "red")) :to-equal '(128 0 0))
    (expect (multiple-value-list (parse-color :bright-green)) :to-equal '(0 255 0)))
  (it "rejects an unknown color name without interning it as a symbol"
    (let ((before (find-symbol "NOT-A-COLOR-DO-NOT-INTERN" :keyword)))
      (expect (lambda () (parse-color "not-a-color-do-not-intern")) :to-throw)
      (expect (find-symbol "NOT-A-COLOR-DO-NOT-INTERN" :keyword) :to-be before))))

(describe "contrast-color"
  (it "picks the readable extreme"
    (expect (contrast-color 240 240 240) :to-equal '(0 0 0))
    (expect (contrast-color 10 10 10) :to-equal '(255 255 255))))
