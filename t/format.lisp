(in-package #:cl-tty-kit/test)

(defun %blocks (count &optional (partial nil) (pad 0))
  (concatenate 'string
               (make-string count :initial-element (code-char #x2588))
               (if partial (string (code-char partial)) "")
               (make-string pad :initial-element #\Space)))

(defun %test-progress-bar-coarse ()
  (is (string= (%blocks 2 nil 2) (format-progress-bar 1/2 4 :fractional nil)))
  (is (string= "    " (format-progress-bar 0 4 :fractional nil)))
  (is (string= (%blocks 4) (format-progress-bar 1 4 :fractional nil)))
  ;; Ratio is clamped to [0, 1].
  (is (string= (%blocks 4) (format-progress-bar 2 4 :fractional nil)))
  (is (string= "    " (format-progress-bar -1 4 :fractional nil)))
  ;; Custom empty glyph.
  (is (string= "..." (format-progress-bar 0 3 :fractional nil :empty #\.)))
  (is (string= "" (format-progress-bar 1/2 0)))
  (signals (error c) (format-progress-bar 1/2 -1) (is c))
  (signals-non-type-error (format-progress-bar "bad" 4))
  (signals-non-type-error (format-progress-bar 1/2 4 :full "bad"))
  (signals-non-type-error (format-progress-bar 1/2 4 :empty "bad")))

(defun %test-progress-bar-fractional ()
  ;; Whole cells resolve identically to the coarse bar.
  (is (string= (%blocks 2 nil 2) (format-progress-bar 1/2 4)))
  ;; A single one-eighth cell (U+258F).
  (is (string= (string (code-char #x258F)) (format-progress-bar 1/8 1)))
  ;; Five-eighths cell (U+258B).
  (is (string= (string (code-char #x258B)) (format-progress-bar 5/8 1)))
  ;; The result is always exactly WIDTH columns.
  (is (= 10 (length (format-progress-bar 1/3 10))))
  (is (= 10 (string-width (format-progress-bar 1/3 10)))))

(defun %test-format-columns ()
  (is (string= "a   bb  " (format-columns '("a" "bb") '(3 4))))
  (is (string= "  a  b " (format-columns '("a" "b") '(3 3)
                                          :aligns '(:right :center))))
  (is (string= "x |y " (format-columns '("x" "y") '(2 2) :separator "|")))
  ;; A field wider than its column is left intact.
  (is (string= "hello" (format-columns '("hello") '(3))))
  ;; Custom pad glyph.
  (is (string= "a.." (format-columns '("a") '(3) :pad #\.)))
  (signals (error c) (format-columns '("a") '(1 2)) (is c))
  (signals-non-type-error (format-columns '(:not-a-string) '(3)))
  (signals-non-type-error (format-columns '("a") '(:wide)))
  (signals-non-type-error (format-columns '("a") '(3) :aligns :bad))
  (signals-non-type-error (format-columns '("a") '(3) :aligns '(:bad)))
  (signals-non-type-error (format-columns '("a") '(3) :separator :bad))
  (signals-non-type-error (format-columns '("a") '(3) :pad "bad")))

(defun %spark (&rest levels)
  (map 'string (lambda (level) (code-char (+ #x2581 level))) levels))

(defun %test-sparkline ()
  (is (string= (%spark 0 1 2 3 4 5 6 7)
               (format-sparkline '(0 1 2 3 4 5 6 7))))
  (is (string= "" (format-sparkline '())))
  ;; A flat series renders the lowest bar.
  (is (string= (%spark 0 0 0) (format-sparkline '(5 5 5))))
  ;; Explicit range.
  (is (string= (%spark 0 4 7) (format-sparkline '(0 5 10) :min 0 :max 10)))
  ;; Values are clamped into the range.
  (is (string= (%spark 0 7) (format-sparkline '(-5 15) :min 0 :max 10)))
  ;; Accepts a vector too.
  (is (string= (%spark 0 7) (format-sparkline #(0 1))))
  (signals-non-type-error (format-sparkline '(:bad)))
  (signals-non-type-error (format-sparkline '(1 2) :min :low)))

(defun %test-format-table ()
  (is (equal '("a   bb" "ccc d ")
             (format-table '(("a" "bb") ("ccc" "d")))))
  ;; Ragged rows are padded with empty trailing fields.
  (is (equal '("a   " "b cc")
             (format-table '(("a") ("b" "cc")))))
  ;; Per-column alignment.
  (is (equal '("a b")
             (format-table '(("a" "b")) :aligns '(:right :right))))
  (signals-non-type-error (format-table '((:bad))))
  (signals-non-type-error (format-table '(("a")) :aligns :bad))
  (signals-non-type-error (format-table '(("a")) :aligns '(:bad)))
  (signals-non-type-error (format-table '(("a")) :separator :bad))
  (signals-non-type-error (format-table '(("a")) :pad "bad"))
  (is (equal '() (format-table '()))))

(defun %test-spinner-frame ()
  (is (string= "|" (spinner-frame 0 :frames :line)))
  (is (string= "/" (spinner-frame 1 :frames :line)))
  ;; INDEX wraps around the frame count.
  (is (string= "|" (spinner-frame 4 :frames :line)))
  (is (string= (string (code-char #x280B)) (spinner-frame 0)))
  ;; A custom sequence of strings.
  (is (string= "b" (spinner-frame 1 :frames '("a" "b" "c"))))
  (is (string= "y" (spinner-frame 3 :frames #("x" "y"))))
  (is (string= "" (spinner-frame 0 :frames "")))
  (signals (error c) (spinner-frame 0 :frames :nope) (is c))
  (signals-non-type-error (spinner-frame 1.5 :frames :line))
  (signals-non-type-error (spinner-frame 0 :frames 42))
  (signals-non-type-error (spinner-frame 0 :frames #(1))))

(defun %test-sixel ()
  ;; 1x1 red: DCS q, palette (196 = cube red), one data byte '@', ST.
  (is (string= (format nil "~CPq#196;2;100;0;0#196@~C\\" #\Esc #\Esc)
               (format-sixel #(255 0 0) 1 1)))
  ;; A zero-area image is an empty sixel.
  (is (string= (format nil "~CPq~C\\" #\Esc #\Esc)
               (format-sixel #() 0 0)))
  (signals (error c) (format-sixel #() -1 0) (is c))
  (signals (error c) (format-sixel #() 0 -1) (is c))
  (signals (error c)
      (format-sixel #() (1+ cl-tty-kit::+max-terminal-image-pixels+) 1)
    (is c))
  ;; Structure: DCS introducer at the start, ST at the end.
  (let ((sixel (format-sixel (make-array 12 :initial-element 100) 2 2)))
    (is (eql 0 (search (format nil "~CPq" #\Esc) sixel)))
    (is (search (format nil "~C\\" #\Esc) sixel)))
  ;; A buffer whose length does not match WIDTH*HEIGHT*3 signals.
  (signals (error c) (format-sixel #(1 2 3) 2 2) (is c))
  (signals-non-type-error (format-sixel '(1 2 3 4 5 6) 1 2))
  (signals (error c) (format-sixel #(1 2 :invalid) 1 1) (is c))
  (signals (error c) (format-sixel #(1 2 256) 1 1) (is c)))

(defun %test-kitty-image ()
  ;; 1x1 white RGB: base64 of #(255 255 255) is "////".
  (is (string= (format nil "~C_Ga=T,f=24,s=1,v=1,m=0;////~C\\" #\Esc #\Esc)
               (ansi-kitty-image #(255 255 255) 1 1)))
  ;; RGBA selects f=32.
  (is (search "f=32" (ansi-kitty-image #(255 0 0 128) 1 1 :format 32)))
  (signals (error c) (ansi-kitty-image #() -1 0) (is c))
  (signals (error c) (ansi-kitty-image #() 0 -1) (is c))
  (signals (error c)
      (ansi-kitty-image #() (1+ cl-tty-kit::+max-terminal-image-pixels+) 1)
    (is c))
  ;; Structure: APC introducer, dimensions, ST terminator.
  (let ((image (ansi-kitty-image (make-array 12 :initial-element 100) 2 2)))
    (is (eql 0 (search (format nil "~C_Ga=T" #\Esc) image)))
    (is (search "s=2,v=2" image))
    (is (search (format nil "~C\\" #\Esc) image)))
  ;; A payload over one chunk splits with m=1 then m=0.
  (let ((image (ansi-kitty-image (make-array (* 100 100 3) :initial-element 50)
                                 100 100)))
    (is (search "m=1" image))
    (is (search "m=0" image)))
  ;; A buffer whose length does not match WIDTH*HEIGHT*bytes-per-pixel signals.
  (signals (error c) (ansi-kitty-image #(1 2) 1 1) (is c))
  (signals-non-type-error (ansi-kitty-image '(1 2 3 4 5 6) 1 2))
  (signals-non-type-error (ansi-kitty-image #(1 2 3) 1 1 :format 16))
  (signals (error c) (ansi-kitty-image #(1 2 :invalid) 1 1) (is c))
  (signals (error c) (ansi-kitty-image #(1 2 256) 1 1) (is c)))

(defun test-format ()
  (%test-progress-bar-coarse)
  (%test-progress-bar-fractional)
  (%test-format-columns)
  (%test-sparkline)
  (%test-format-table)
  (%test-spinner-frame)
  (%test-sixel)
  (%test-kitty-image)
  t)
