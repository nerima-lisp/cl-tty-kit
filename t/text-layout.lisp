(in-package #:cl-tty-kit/test)

(defun %test-truncate-string ()
  ;; A string within the budget is returned untouched.
  (is (string= "hello" (truncate-string "hello" 10)))
  (is (string= "hello" (truncate-string "hello" 5)))
  ;; Plain clipping with no ellipsis.
  (is (string= "hel" (truncate-string "hello" 3)))
  (is (string= "" (truncate-string "hello" 0)))
  (is (string= "" (truncate-string "hello" -4)))
  ;; Ellipsis reserves its own columns so the result stays within WIDTH.
  (is (string= "he..." (truncate-string "hello world" 5 :ellipsis "...")))
  (is (= 5 (string-width (truncate-string "hello world" 5 :ellipsis "..."))))
  ;; An ellipsis too wide for WIDTH is dropped rather than overflowing.
  (is (string= "h" (truncate-string "hello" 1 :ellipsis "...")))
  ;; Wide (double-width) glyphs are never split across the boundary.
  (let ((cjk (format nil "~C~C~C" #\U+4E00 #\U+4E8C #\U+4E09)))
    (is (= 6 (string-width cjk)))
    (is (string= (format nil "~C" #\U+4E00) (truncate-string cjk 3)))
    (is (= 2 (string-width (truncate-string cjk 3)))))
  (signals-non-type-error (truncate-string :not-a-string 3))
  (signals-non-type-error (truncate-string "hello" :wide))
  (signals-non-type-error (truncate-string "hello" 3 :ellipsis :bad)))

(defun %test-pad-string ()
  (is (string= "hi   " (pad-string "hi" 5)))
  (is (string= "hi   " (pad-string "hi" 5 :align :left)))
  (is (string= "   hi" (pad-string "hi" 5 :align :right)))
  (is (string= " hi  " (pad-string "hi" 5 :align :center)))
  (is (string= "..hi.." (pad-string "hi" 6 :align :center :pad #\.)))
  ;; An odd deficit splits unevenly: the shorter (left) side can be zero.
  (is (string= "hi " (pad-string "hi" 3 :align :center)))
  ;; Already wide enough -> unchanged, never truncated.
  (is (string= "hello" (pad-string "hello" 3)))
  (is (string= "hello" (pad-string "hello" 5)))
  ;; Column-accurate padding around a double-width glyph.
  (is (string= (format nil "~C  " #\U+4E00) (pad-string (format nil "~C" #\U+4E00) 4)))
  ;; A multi-column pad character is rejected.
  (signals (error c) (pad-string "hi" 5 :pad #\U+4E00) (is c))
  (signals-non-type-error (pad-string :not-a-string 3))
  (signals-non-type-error (pad-string "hi" :wide))
  (signals-non-type-error (pad-string "hi" 3 :align :diagonal))
  (signals-non-type-error (pad-string "hi" 3 :pad :bad)))

(defun %test-wrap-string ()
  (is (equal '("the quick" "brown fox")
             (wrap-string "the quick brown fox" 9)))
  ;; Runs of spaces collapse to a single separator.
  (is (equal '("a b") (wrap-string "a   b" 5)))
  ;; A word longer than the width is hard-split at a column boundary.
  (is (equal '("abcde" "fghij" "k") (wrap-string "abcdefghijk" 5)))
  ;; Embedded newlines force breaks; a blank line yields an empty string.
  (is (equal '("a" "" "b") (wrap-string (format nil "a~%~%b") 5)))
  ;; Wide glyphs are packed by column width, not character count.
  (let ((cjk (format nil "~C~C~C" #\U+4E00 #\U+4E8C #\U+4E09)))
    (is (equal (list (format nil "~C~C" #\U+4E00 #\U+4E8C)
                      (format nil "~C" #\U+4E09))
                (wrap-string cjk 4))))
  (signals (error c) (wrap-string "x" 0) (is c))
  (signals-non-type-error (wrap-string :not-a-string 3))
  (signals-non-type-error (wrap-string "x" :wide)))

(defun %test-expand-tabs ()
  (is (string= "a   bc  d" (expand-tabs (format nil "a~Cbc~Cd" #\Tab #\Tab) :tab-width 4)))
  (is (string= "        x" (expand-tabs (format nil "~Cx" #\Tab))))
  ;; A newline resets the column.
  (is (string= (format nil "ab~%c   d")
                (expand-tabs (format nil "ab~%c~Cd" #\Tab) :tab-width 4)))
  (is (string= "" (expand-tabs "")))
  (signals (error c) (expand-tabs "x" :tab-width 0) (is c))
  (signals (error c) (expand-tabs "x" :tab-width 1.5) (is c))
  (signals-non-type-error (expand-tabs :not-a-string)))

(defun %test-chop-string ()
  (is (equal '("abc" "def" "g") (chop-string "abcdefg" 3)))
  (is (equal '("abcdefg") (chop-string "abcdefg" 100)))
  (is (equal '() (chop-string "" 3)))
  ;; Chops by column width, keeping wide glyphs whole.
  (let ((cjk (format nil "~C~C~C" #\U+4E00 #\U+4E8C #\U+4E09)))
    (is (equal (list (format nil "~C~C" #\U+4E00 #\U+4E8C)
                      (format nil "~C" #\U+4E09))
                (chop-string cjk 4))))
  ;; A glyph wider than WIDTH on its own becomes a lone over-width chunk
  ;; instead of stalling with zero progress.
  (is (equal (list (format nil "~C" #\U+4E00)) (chop-string (format nil "~C" #\U+4E00) 1)))
  (signals (error c) (chop-string "x" 0) (is c))
  (signals-non-type-error (chop-string :not-a-string 3))
  (signals-non-type-error (chop-string "x" :wide)))

(defun %test-strip-ansi ()
  (is (string= "hi" (strip-ansi (concatenate 'string (ansi-bold) "hi"
                                             (ansi-reset-style)))))
  (is (string= "txt" (strip-ansi (ansi-hyperlink "http://x" "txt"))))
  (is (string= "abc" (strip-ansi "abc")))
  ;; The visible width of styled text is measurable after stripping.
  (is (= 2 (string-width (strip-ansi (concatenate 'string (ansi-bold) "hi"
                                                  (ansi-reset-style))))))
  (let ((nested (concatenate 'string
                             "a"
                             (string #\Esc)
                             "[12"
                             (string #\Esc)
                             "]52;c;secret"
                             (string (code-char 7))
                             "b")))
    (is (string= "ab" (strip-ansi nested))))
  ;; A trailing bare ESC (nothing after it) is dropped, not indexed past the
  ;; end of the string.
  (is (string= "a" (strip-ansi (concatenate 'string "a" (string #\Esc)))))
  ;; An unterminated CSI or OSC (no final byte / no BEL or ST before the
  ;; string ends) is dropped wholesale rather than left dangling.
  (is (string= "a" (strip-ansi (concatenate 'string "a" (string #\Esc) "[1"))))
  (is (string= "a" (strip-ansi (concatenate 'string "a" (string #\Esc) "]52;abc"))))
  (signals-non-type-error (strip-ansi :not-a-string)))

(defun %test-ambiguous-width ()
  ;; U+00A7 (section sign) is East Asian Ambiguous: narrow by default, wide when
  ;; the policy is enabled.
  (is (= 1 (char-width (code-char #xA7))))
  (is (= 2 (string-width "abc" :start 1 :end 3)))
  (signals (error c) (char-width -1) (is c))
  (signals (error c) (char-width #x110000) (is c))
  (signals (error c) (char-width :not-a-code-point) (is c))
  (signals (error c) (string-width "abc" :start -1) (is c))
  (signals (error c) (string-width "abc" :start 2 :end 1) (is c))
  (signals (error c) (string-width "abc" :end 4) (is c))
  (signals (error c) (string-width "abc" :start 1.5) (is c))
  (let ((*east-asian-ambiguous-wide* t))
    (is (= 2 (char-width (code-char #xA7))))
    ;; ASCII is unaffected by the policy.
    (is (= 1 (char-width #\A))))
  ;; A format-control (:CF) code point is zero-width, except U+00AD (soft
  ;; hyphen), which terminals render as a visible hyphen rather than
  ;; dropping -- the one explicit exception to the :CF rule.
  (is (= 0 (char-width (code-char #x200D))))
  (is (= 1 (char-width (code-char #xAD))))
  ;; The Hangul Jamo range (U+1160-U+11FF) is zero-width by explicit range,
  ;; not by general category.
  (is (= 0 (char-width (code-char #x1160))))
  ;; C0/C1 control code points (including DEL) are zero-width.
  (is (= 0 (char-width (code-char #x7F))))
  (is (= 0 (char-width (code-char #x80)))))

(defun %test-graphemes ()
  (let ((combining (coerce (list #\e (code-char #x0301) #\a) 'string)))
    ;; The combining acute clusters with its base; 'a' is separate.
    (is (equal (list (coerce (list #\e (code-char #x0301)) 'string) "a")
               (string-graphemes combining)))
    (is (= 2 (grapheme-count combining))))
  (is (equal '("a" "b" "c") (string-graphemes "abc")))
  (is (= 0 (grapheme-count "")))
  ;; Cluster width is the base width; combining marks add nothing.
  (is (= 1 (grapheme-width (coerce (list #\e (code-char #x0301)) 'string))))
  (is (= 2 (grapheme-width (string (code-char #x4E00)))))
  (is (= 0 (grapheme-width ""))))

(defun test-text-layout ()
  (%test-truncate-string)
  (%test-pad-string)
  (%test-wrap-string)
  (%test-expand-tabs)
  (%test-chop-string)
  (%test-strip-ansi)
  (%test-ambiguous-width)
  (%test-graphemes)
  t)
