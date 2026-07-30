(in-package #:cl-tty-kit/test)

(describe "truncate-string"
  (it "returns a string within the budget untouched"
    (expect (truncate-string "hello" 10) :to-equal "hello")
    (expect (truncate-string "hello" 5) :to-equal "hello"))
  (it "clips plainly with no ellipsis"
    (expect (truncate-string "hello" 3) :to-equal "hel")
    (expect (truncate-string "hello" 0) :to-equal "")
    (expect (truncate-string "hello" -4) :to-equal ""))
  (it "reserves columns for the ellipsis so the result stays within width"
    (expect (truncate-string "hello world" 5 :ellipsis "...") :to-equal "he...")
    (expect (string-width (truncate-string "hello world" 5 :ellipsis "...")) :to-be 5))
  (it "still appends a zero-width but nonempty ellipsis"
    (let* ((ellipsis (string (code-char #x0301)))
           (result (truncate-string "hello" 2 :ellipsis ellipsis)))
      (expect result :to-equal (concatenate 'string "he" ellipsis))
      (expect (string-width result) :to-be 2)))
  (it "drops an ellipsis too wide for width rather than overflowing"
    (expect (truncate-string "hello" 1 :ellipsis "...") :to-equal "h"))
  (it "never splits a wide (double-width) glyph across the boundary"
    (let ((cjk (format nil "~C~C~C" #\U+4E00 #\U+4E8C #\U+4E09)))
      (expect (string-width cjk) :to-be 6)
      (expect (truncate-string cjk 3) :to-equal (format nil "~C" #\U+4E00))
      (expect (string-width (truncate-string cjk 3)) :to-be 2)))
  (it "rejects malformed arguments"
    (expect-non-type-error (truncate-string :not-a-string 3))
    (expect-non-type-error (truncate-string "hello" :wide))
    (expect-non-type-error (truncate-string "hello" 3 :ellipsis :bad))))

(describe "pad-string"
  (it "left-pads by default"
    (expect (pad-string "hi" 5) :to-equal "hi   ")
    (expect (pad-string "hi" 5 :align :left) :to-equal "hi   "))
  (it "right-aligns"
    (expect (pad-string "hi" 5 :align :right) :to-equal "   hi"))
  (it "centers, with a custom pad glyph"
    (expect (pad-string "hi" 5 :align :center) :to-equal " hi  ")
    (expect (pad-string "hi" 6 :align :center :pad #\.) :to-equal "..hi.."))
  (it "an odd deficit splits unevenly, with the shorter (left) side possibly zero"
    (expect (pad-string "hi" 3 :align :center) :to-equal "hi "))
  (it "is unchanged, never truncated, when already wide enough"
    (expect (pad-string "hello" 3) :to-equal "hello")
    (expect (pad-string "hello" 5) :to-equal "hello"))
  (it "pads by column, accurately around a double-width glyph"
    (let ((cjk (format nil "~C" #\U+4E00)))
      (expect (pad-string cjk 4) :to-equal (format nil "~C  " #\U+4E00))
      (expect (pad-string cjk 5 :align :right) :to-equal (format nil "   ~C" #\U+4E00))
      (expect (pad-string cjk 5 :align :center) :to-equal (format nil " ~C  " #\U+4E00))))
  (it "rejects a multi-column pad character"
    (expect (lambda () (pad-string "hi" 5 :pad #\U+4E00)) :to-throw))
  (it "rejects malformed arguments"
    (expect-non-type-error (pad-string :not-a-string 3))
    (expect-non-type-error (pad-string "hi" :wide))
    (expect-non-type-error (pad-string "hi" 3 :align :diagonal))
    (expect-non-type-error (pad-string "hi" 3 :pad :bad))))

(describe "wrap-string"
  (it "wraps at word boundaries within the width"
    (expect (wrap-string "the quick brown fox" 9) :to-equal '("the quick" "brown fox")))
  (it "collapses runs of spaces to a single separator"
    (expect (wrap-string "a   b" 5) :to-equal '("a b")))
  (it "measures an unsplit word once before placement"
    (let ((calls 0)
          (original (symbol-function 'cl-tty-kit:string-width)))
      (unwind-protect
           (progn
             (setf (symbol-function 'cl-tty-kit:string-width)
                   (lambda (&rest arguments)
                     (incf calls)
                     (apply original arguments)))
             (expect (wrap-string "a bb ccc" 10) :to-equal '("a bb ccc"))
             (expect calls :to-be 3))
        (setf (symbol-function 'cl-tty-kit:string-width) original))))
  (it "hard-splits a word longer than the width at a column boundary"
    (expect (wrap-string "abcdefghijk" 5) :to-equal '("abcde" "fghij" "k")))
  (it "embedded newlines force breaks; a blank line yields an empty string"
    (expect (wrap-string (format nil "a~%~%b") 5) :to-equal '("a" "" "b")))
  (it "a trailing newline preserves the final empty paragraph"
    (expect (wrap-string (format nil "a~%") 5) :to-equal '("a" ""))
    (expect (wrap-string (format nil "~%") 5) :to-equal '("" "")))
  (it "packs wide glyphs by column width, not character count"
    (let ((cjk (format nil "~C~C~C" #\U+4E00 #\U+4E8C #\U+4E09)))
      (expect (wrap-string cjk 4)
              :to-equal (list (format nil "~C~C" #\U+4E00 #\U+4E8C)
                              (format nil "~C" #\U+4E09)))))
  (it "rejects a zero width and malformed arguments"
    (expect (lambda () (wrap-string "x" 0)) :to-throw)
    (expect-non-type-error (wrap-string :not-a-string 3))
    (expect-non-type-error (wrap-string "x" :wide))))

(describe "expand-tabs"
  (it "expands tabs to the next tab stop"
    (expect (expand-tabs (format nil "a~Cbc~Cd" #\Tab #\Tab) :tab-width 4) :to-equal "a   bc  d")
    (expect (expand-tabs (format nil "~Cx" #\Tab)) :to-equal "        x"))
  (it "a newline resets the column"
    (expect (expand-tabs (format nil "ab~%c~Cd" #\Tab) :tab-width 4)
            :to-equal (format nil "ab~%c   d")))
  (it "an empty string is unchanged"
    (expect (expand-tabs "") :to-equal ""))
  (it "rejects a non-positive or fractional :tab-width, and malformed arguments"
    (expect (lambda () (expand-tabs "x" :tab-width 0)) :to-throw)
    (expect (lambda () (expand-tabs "x" :tab-width 1.5)) :to-throw)
    (expect-non-type-error (expand-tabs :not-a-string))))

(describe "chop-string"
  (it "chops into fixed-width chunks"
    (expect (chop-string "abcdefg" 3) :to-equal '("abc" "def" "g"))
    (expect (chop-string "abcdefg" 100) :to-equal '("abcdefg"))
    (expect (chop-string "" 3) :to-equal '()))
  (it "chops by column width, keeping wide glyphs whole"
    (let ((cjk (format nil "~C~C~C" #\U+4E00 #\U+4E8C #\U+4E09)))
      (expect (chop-string cjk 4)
              :to-equal (list (format nil "~C~C" #\U+4E00 #\U+4E8C)
                              (format nil "~C" #\U+4E09)))))
  (it "a glyph wider than width becomes a lone over-width chunk instead of stalling"
    (expect (chop-string (format nil "~C" #\U+4E00) 1)
            :to-equal (list (format nil "~C" #\U+4E00))))
  (it "rejects a zero width and malformed arguments"
    (expect (lambda () (chop-string "x" 0)) :to-throw)
    (expect-non-type-error (chop-string :not-a-string 3))
    (expect-non-type-error (chop-string "x" :wide))))

(describe "strip-ansi"
  (it "strips SGR style escapes"
    (expect (strip-ansi (concatenate 'string (ansi-bold) "hi" (ansi-reset-style)))
            :to-equal "hi"))
  (it "strips an OSC 8 hyperlink down to its visible text"
    (expect (strip-ansi (ansi-hyperlink "http://x" "txt")) :to-equal "txt"))
  (it "leaves unstyled text alone"
    (expect (strip-ansi "abc") :to-equal "abc"))
  (it "leaves styled text's visible width measurable after stripping"
    (expect (string-width (strip-ansi (concatenate 'string (ansi-bold) "hi" (ansi-reset-style))))
            :to-be 2))
  (it "strips a nested CSI-then-OSC sequence"
    (let ((nested (concatenate 'string "a" (string #\Esc) "[12" (string #\Esc)
                               "]52;c;secret" (string (code-char 7)) "b")))
      (expect (strip-ansi nested) :to-equal "ab")))
  (it "drops a trailing bare ESC rather than indexing past the end of the string"
    (expect (strip-ansi (concatenate 'string "a" (string #\Esc))) :to-equal "a"))
  (it "drops an unterminated CSI or OSC wholesale rather than leaving it dangling"
    (expect (strip-ansi (concatenate 'string "a" (string #\Esc) "[1")) :to-equal "a")
    (expect (strip-ansi (concatenate 'string "a" (string #\Esc) "]52;abc")) :to-equal "a"))
  (it "rejects a non-string argument"
    (expect-non-type-error (strip-ansi :not-a-string))))

(describe "char-width and string-width, including the East Asian Ambiguous policy"
  (it "the section sign (U+00A7) is narrow by default"
    (expect (char-width (code-char #xA7)) :to-be 1))
  (it "string-width sums a substring's column widths"
    (expect (string-width "abc" :start 1 :end 3) :to-be 2))
  (it "rejects an out-of-range or malformed code point"
    (expect (lambda () (char-width -1)) :to-throw)
    (expect (lambda () (char-width #x110000)) :to-throw)
    (expect (lambda () (char-width :not-a-code-point)) :to-throw))
  (it "rejects malformed string-width bounds"
    (expect (lambda () (string-width "abc" :start -1)) :to-throw)
    (expect (lambda () (string-width "abc" :start 2 :end 1)) :to-throw)
    (expect (lambda () (string-width "abc" :end 4)) :to-throw)
    (expect (lambda () (string-width "abc" :start 1.5)) :to-throw))
  (it "the section sign becomes wide when *east-asian-ambiguous-wide* is bound"
    (let ((*east-asian-ambiguous-wide* t))
      (expect (char-width (code-char #xA7)) :to-be 2)
      ;; ASCII is unaffected by the policy.
      (expect (char-width #\A) :to-be 1)))
  (it "a format-control (:Cf) code point is zero-width, except the soft hyphen"
    (expect (char-width (code-char #x200D)) :to-be 0)
    ;; U+00AD (soft hyphen): terminals render it as a visible hyphen rather
    ;; than dropping it -- the one explicit exception to the :Cf rule.
    (expect (char-width (code-char #xAD)) :to-be 1))
  (it "the Hangul Jamo range (U+1160-U+11FF) is zero-width by explicit range"
    (expect (char-width (code-char #x1160)) :to-be 0))
  (it "C0/C1 control code points (including DEL) are zero-width"
    (expect (char-width (code-char #x7F)) :to-be 0)
    (expect (char-width (code-char #x80)) :to-be 0)))

(describe "string-graphemes and grapheme-count/width"
  (it "clusters a combining mark with its base character"
    (let ((combining (coerce (list #\e (code-char #x0301) #\a) 'string)))
      (expect (string-graphemes combining)
              :to-equal (list (coerce (list #\e (code-char #x0301)) 'string) "a"))
      (expect (grapheme-count combining) :to-be 2)))
  (it "splits plain ASCII into one grapheme per character"
    (expect (string-graphemes "abc") :to-equal '("a" "b" "c")))
  (it "an empty string has zero graphemes"
    (expect (grapheme-count "") :to-be 0))
  (it "cluster width is the base width; combining marks add nothing"
    (expect (grapheme-width (coerce (list #\e (code-char #x0301)) 'string)) :to-be 1)
    (expect (grapheme-width (string (code-char #x4E00))) :to-be 2)
    (expect (grapheme-width "") :to-be 0)))
