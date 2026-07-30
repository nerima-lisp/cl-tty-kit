(in-package #:cl-tty-kit/test)

(defun %blocks (count &optional (partial nil) (pad 0))
  (concatenate 'string
               (make-string count :initial-element (code-char #x2588))
               (if partial (string (code-char partial)) "")
               (make-string pad :initial-element #\Space)))

(describe "format-progress-bar, coarse (whole cells only)"
  (it "fills proportionally to the ratio"
    (expect (format-progress-bar 1/2 4 :fractional nil) :to-equal (%blocks 2 nil 2))
    (expect (format-progress-bar 0 4 :fractional nil) :to-equal "    ")
    (expect (format-progress-bar 1 4 :fractional nil) :to-equal (%blocks 4)))
  (it "clamps the ratio to [0, 1]"
    (expect (format-progress-bar 2 4 :fractional nil) :to-equal (%blocks 4))
    (expect (format-progress-bar -1 4 :fractional nil) :to-equal "    "))
  (it "accepts a custom empty glyph"
    (expect (format-progress-bar 0 3 :fractional nil :empty #\.) :to-equal "..."))
  (it "a zero width yields an empty string"
    (expect (format-progress-bar 1/2 0) :to-equal ""))
  (it "rejects a negative width"
    (expect (lambda () (format-progress-bar 1/2 -1)) :to-throw))
  (it "rejects a malformed ratio, full glyph, or empty glyph"
    (expect-non-type-error (format-progress-bar "bad" 4))
    (expect-non-type-error (format-progress-bar 1/2 4 :full "bad"))
    (expect-non-type-error (format-progress-bar 1/2 4 :empty "bad"))))

(describe "format-progress-bar, fractional (eighth-cell resolution)"
  (it "resolves whole cells identically to the coarse bar"
    (expect (format-progress-bar 1/2 4) :to-equal (%blocks 2 nil 2)))
  (it "renders a single one-eighth cell (U+258F)"
    (expect (format-progress-bar 1/8 1) :to-equal (string (code-char #x258F))))
  (it "renders a five-eighths cell (U+258B)"
    (expect (format-progress-bar 5/8 1) :to-equal (string (code-char #x258B))))
  (it "is always exactly width columns"
    (expect (length (format-progress-bar 1/3 10)) :to-be 10)
    (expect (string-width (format-progress-bar 1/3 10)) :to-be 10)))

(describe "format-columns"
  (it "pads each field to its column width"
    (expect (format-columns '("a" "bb") '(3 4)) :to-equal "a   bb  "))
  (it "aligns per column"
    (expect (format-columns '("a" "b") '(3 3) :aligns '(:right :center))
            :to-equal "  a  b "))
  (it "defaults remaining fields to left alignment when :aligns is shorter"
    (expect (format-columns '("a" "b") '(3 3) :aligns '(:right)) :to-equal "  a b  "))
  (it "accepts a custom :separator"
    (expect (format-columns '("x" "y") '(2 2) :separator "|") :to-equal "x |y "))
  (it "leaves a field wider than its column intact"
    (expect (format-columns '("hello") '(3)) :to-equal "hello"))
  (it "accepts a custom :pad glyph"
    (expect (format-columns '("a") '(3) :pad #\.) :to-equal "a.."))
  (it "rejects mismatched fields/widths lengths"
    (expect (lambda () (format-columns '("a") '(1 2))) :to-throw))
  (it "rejects malformed arguments"
    (expect-non-type-error (format-columns :not-a-list '(3)))
    (expect-non-type-error (format-columns '("a") :not-a-list))
    (expect-non-type-error (format-columns '(:not-a-string) '(3)))
    (expect-non-type-error (format-columns '("a") '(:wide)))
    (expect-non-type-error (format-columns '("a") '(3) :aligns :bad))
    (expect-non-type-error (format-columns '("a") '(3) :aligns '(:bad)))
    (expect-non-type-error (format-columns '("a") '(3) :separator :bad))
    (expect-non-type-error (format-columns '("a") '(3) :pad "bad"))))

(defun %spark (&rest levels)
  (map 'string (lambda (level) (code-char (+ #x2581 level))) levels))

(describe "format-sparkline"
  (it "maps each level to its bar glyph"
    (expect (format-sparkline '(0 1 2 3 4 5 6 7)) :to-equal (%spark 0 1 2 3 4 5 6 7)))
  (it "an empty series yields an empty string"
    (expect (format-sparkline '()) :to-equal ""))
  (it "a flat series renders the lowest bar"
    (expect (format-sparkline '(5 5 5)) :to-equal (%spark 0 0 0)))
  (it "accepts an explicit :min/:max range"
    (expect (format-sparkline '(0 5 10) :min 0 :max 10) :to-equal (%spark 0 4 7)))
  (it "clamps out-of-range values into the range"
    (expect (format-sparkline '(-5 15) :min 0 :max 10) :to-equal (%spark 0 7)))
  (it "accepts a vector as well as a list"
    (expect (format-sparkline #(0 1)) :to-equal (%spark 0 7)))
  (it "rejects malformed arguments"
    (expect-non-type-error (format-sparkline '(:bad)))
    (expect-non-type-error (format-sparkline '(1 2) :min :low))
    (expect-non-type-error (format-sparkline :not-a-sequence))))

(describe "format-table"
  (it "pads every column to its widest field"
    (expect (format-table '(("a" "bb") ("ccc" "d"))) :to-equal '("a   bb" "ccc d ")))
  (it "pads ragged rows with empty trailing fields"
    (expect (format-table '(("a") ("b" "cc"))) :to-equal '("a   " "b cc")))
  (it "supports per-column alignment"
    (expect (format-table '(("a" "b")) :aligns '(:right :right)) :to-equal '("a b")))
  (it "an empty row list yields an empty list"
    (expect (format-table '()) :to-equal '()))
  (it "rejects malformed arguments"
    (expect-non-type-error (format-table :not-a-list))
    ;; A ROWS list whose element is not itself a list, as opposed to a row
    ;; containing a non-string field (the next case below).
    (expect-non-type-error (format-table '("not-a-row")))
    (expect-non-type-error (format-table '((:bad))))
    (expect-non-type-error (format-table '(("a")) :aligns :bad))
    (expect-non-type-error (format-table '(("a")) :aligns '(:bad)))
    (expect-non-type-error (format-table '(("a")) :separator :bad))
    (expect-non-type-error (format-table '(("a")) :pad "bad"))))

(describe "spinner-frame"
  (it "cycles through the named :line frame set"
    (expect (spinner-frame 0 :frames :line) :to-equal "|")
    (expect (spinner-frame 1 :frames :line) :to-equal "/"))
  (it "wraps the index around the frame count"
    (expect (spinner-frame 4 :frames :line) :to-equal "|"))
  (it "defaults to the braille dot frame set"
    (expect (spinner-frame 0) :to-equal (string (code-char #x280B))))
  (it "accepts a custom sequence of strings, list or vector"
    (expect (spinner-frame 1 :frames '("a" "b" "c")) :to-equal "b")
    (expect (spinner-frame 3 :frames #("x" "y")) :to-equal "y"))
  (it "an empty frame set yields an empty string"
    (expect (spinner-frame 0 :frames "") :to-equal ""))
  (it "rejects an unknown named frame set"
    (expect (lambda () (spinner-frame 0 :frames :nope)) :to-throw))
  (it "rejects malformed arguments"
    (expect-non-type-error (spinner-frame 1.5 :frames :line))
    (expect-non-type-error (spinner-frame 0 :frames 42))
    (expect-non-type-error (spinner-frame 0 :frames #(1)))))

(describe "format-sixel"
  (it "encodes a 1x1 red pixel: DCS q, palette, one data byte, ST"
    (expect (format-sixel #(255 0 0) 1 1)
            :to-equal (format nil "~CPq#196;2;100;0;0#196@~C\\" #\Esc #\Esc)))
  (it "a zero-area image is an empty sixel"
    (expect (format-sixel #() 0 0) :to-equal (format nil "~CPq~C\\" #\Esc #\Esc)))
  (it "rejects negative dimensions"
    (expect (lambda () (format-sixel #() -1 0)) :to-throw)
    (expect (lambda () (format-sixel #() 0 -1)) :to-throw))
  (it "rejects an image exceeding the pixel limit"
    (expect (lambda ()
              (format-sixel #() (1+ cl-tty-kit::+max-terminal-image-pixels+) 1))
            :to-throw))
  (it "brackets the output with the DCS introducer and ST terminator"
    (let ((sixel (format-sixel (make-array 12 :initial-element 100) 2 2)))
      (expect (search (format nil "~CPq" #\Esc) sixel) :to-be 0)
      (expect (search (format nil "~C\\" #\Esc) sixel))))
  (it "compresses a run longer than 3 columns of the same color to !N"
    (expect (search "!4" (format-sixel (make-array 12 :initial-element 100) 4 1))))
  (it "separates bands taller than one 6-row band with -"
    (expect (search "-" (format-sixel (make-array 21 :initial-element 50) 1 7))))
  (it "separates two colors within one band with $, and fills a gap with ?"
    (let ((two-color (format-sixel #(255 0 0 0 0 255) 2 1)))
      (expect (search "$" two-color))
      (expect (search "?" two-color))))
  (it "does not leak a band's color state into the next band"
    (expect (format-sixel #(255 0 0 255 0 0 255 0 0 255 0 0 255 0 0 255 0 0 0 0 255) 1 7)
            :to-equal (format nil "~CPq#21;2;0;0;100#196;2;100;0;0#196~~-#21@~C\\"
                              #\Esc #\Esc)))
  (it "rejects a pixel buffer whose length does not match width*height*3"
    (expect (lambda () (format-sixel #(1 2 3) 2 2)) :to-throw))
  (it "rejects a non-vector pixel buffer"
    (expect-non-type-error (format-sixel '(1 2 3 4 5 6) 1 2)))
  (it "rejects an out-of-range octet in the pixel buffer"
    (expect (lambda () (format-sixel #(1 2 :invalid) 1 1)) :to-throw)
    (expect (lambda () (format-sixel #(1 2 256) 1 1)) :to-throw)))

(describe "ansi-kitty-image"
  (it "encodes a 1x1 white RGB pixel"
    (expect (ansi-kitty-image #(255 255 255) 1 1)
            :to-equal (format nil "~C_Ga=T,f=24,s=1,v=1,m=0;////~C\\" #\Esc #\Esc)))
  (it "an RGBA buffer selects f=32"
    (expect (search "f=32" (ansi-kitty-image #(255 0 0 128) 1 1 :format 32))))
  (it "rejects negative dimensions"
    (expect (lambda () (ansi-kitty-image #() -1 0)) :to-throw)
    (expect (lambda () (ansi-kitty-image #() 0 -1)) :to-throw))
  (it "rejects an image exceeding the pixel limit"
    (expect (lambda ()
              (ansi-kitty-image #() (1+ cl-tty-kit::+max-terminal-image-pixels+) 1))
            :to-throw))
  (it "a zero-area image is a single m=0 chunk with an empty payload"
    (expect (ansi-kitty-image #() 0 0)
            :to-equal (format nil "~C_Ga=T,f=24,s=0,v=0,m=0;~C\\" #\Esc #\Esc)))
  (it "brackets the output with the APC introducer, dimensions, and ST terminator"
    (let ((image (ansi-kitty-image (make-array 12 :initial-element 100) 2 2)))
      (expect (search (format nil "~C_Ga=T" #\Esc) image) :to-be 0)
      (expect (search "s=2,v=2" image))
      (expect (search (format nil "~C\\" #\Esc) image))))
  (it "a payload over one chunk splits with m=1 then m=0"
    (let ((image (ansi-kitty-image (make-array (* 100 100 3) :initial-element 50) 100 100)))
      (expect (search "m=1" image))
      (expect (search "m=0" image))))
  (it "rejects a pixel buffer whose length does not match width*height*bytes-per-pixel"
    (expect (lambda () (ansi-kitty-image #(1 2) 1 1)) :to-throw))
  (it "rejects a non-vector pixel buffer"
    (expect-non-type-error (ansi-kitty-image '(1 2 3 4 5 6) 1 2)))
  (it "rejects an unsupported :format"
    (expect-non-type-error (ansi-kitty-image #(1 2 3) 1 1 :format 16)))
  (it "rejects an out-of-range octet in the pixel buffer"
    (expect (lambda () (ansi-kitty-image #(1 2 :invalid) 1 1)) :to-throw)
    (expect (lambda () (ansi-kitty-image #(1 2 256) 1 1)) :to-throw)))

(describe "format-sixel and ansi-kitty-image over a typed octet buffer"
  (it "encode identically to a generic vector of the same octets"
    (let ((rgb (make-array 3 :element-type '(unsigned-byte 8) :initial-contents '(255 0 0))))
      (expect (format-sixel rgb 1 1)
              :to-equal (format nil "~CPq#196;2;100;0;0#196@~C\\" #\Esc #\Esc))
      (expect (ansi-kitty-image rgb 1 1)
              :to-equal (format nil "~C_Ga=T,f=24,s=1,v=1,m=0;/wAA~C\\" #\Esc #\Esc)))))
