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
    (is (= 2 (string-width (truncate-string cjk 3))))))

(defun %test-pad-string ()
  (is (string= "hi   " (pad-string "hi" 5)))
  (is (string= "hi   " (pad-string "hi" 5 :align :left)))
  (is (string= "   hi" (pad-string "hi" 5 :align :right)))
  (is (string= " hi  " (pad-string "hi" 5 :align :center)))
  (is (string= "..hi.." (pad-string "hi" 6 :align :center :pad #\.)))
  ;; Already wide enough -> unchanged, never truncated.
  (is (string= "hello" (pad-string "hello" 3)))
  (is (string= "hello" (pad-string "hello" 5)))
  ;; Column-accurate padding around a double-width glyph.
  (is (string= (format nil "~C  " #\U+4E00) (pad-string (format nil "~C" #\U+4E00) 4)))
  ;; A multi-column pad character is rejected.
  (signals (error c) (pad-string "hi" 5 :pad #\U+4E00) (is c)))

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
  (signals (error c) (wrap-string "x" 0) (is c)))

(defun %test-expand-tabs ()
  (is (string= "a   bc  d" (expand-tabs (format nil "a~Cbc~Cd" #\Tab #\Tab) :tab-width 4)))
  (is (string= "        x" (expand-tabs (format nil "~Cx" #\Tab))))
  ;; A newline resets the column.
  (is (string= (format nil "ab~%c   d")
               (expand-tabs (format nil "ab~%c~Cd" #\Tab) :tab-width 4)))
  (is (string= "" (expand-tabs "")))
  (signals (error c) (expand-tabs "x" :tab-width 0) (is c)))

(defun %test-chop-string ()
  (is (equal '("abc" "def" "g") (chop-string "abcdefg" 3)))
  (is (equal '("abcdefg") (chop-string "abcdefg" 100)))
  (is (equal '() (chop-string "" 3)))
  ;; Chops by column width, keeping wide glyphs whole.
  (let ((cjk (format nil "~C~C~C" #\U+4E00 #\U+4E8C #\U+4E09)))
    (is (equal (list (format nil "~C~C" #\U+4E00 #\U+4E8C)
                     (format nil "~C" #\U+4E09))
               (chop-string cjk 4))))
  (signals (error c) (chop-string "x" 0) (is c)))

(defun %test-strip-ansi ()
  (is (string= "hi" (strip-ansi (concatenate 'string (ansi-bold) "hi"
                                             (ansi-reset-style)))))
  (is (string= "txt" (strip-ansi (ansi-hyperlink "http://x" "txt"))))
  (is (string= "abc" (strip-ansi "abc")))
  ;; The visible width of styled text is measurable after stripping.
  (is (= 2 (string-width (strip-ansi (concatenate 'string (ansi-bold) "hi"
                                                  (ansi-reset-style)))))))

(defun %test-ambiguous-width ()
  ;; U+00A7 (section sign) is East Asian Ambiguous: narrow by default, wide when
  ;; the policy is enabled.
  (is (= 1 (char-width (code-char #xA7))))
  (let ((*east-asian-ambiguous-wide* t))
    (is (= 2 (char-width (code-char #xA7))))
    ;; ASCII is unaffected by the policy.
    (is (= 1 (char-width #\A)))))

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
