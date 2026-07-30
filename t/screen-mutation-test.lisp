(in-package #:cl-tty-kit/test)

;;; --------------------------------------------------------------------------
;;; Mutation, copy-on-write, and error-path coverage for SCREEN and CELL.
;;;
;;; Split out of t/screen-test.lisp, which keeps the read-oriented API tests
;;; (fill, copy, row-string, scroll, blit, crop, ...); this file groups the
;;; tests that share a theme instead -- every mutating SCREEN operation's
;;; effect on cell state, the copy-on-write contract CELL/SCREEN make about
;;; caller-owned style lists, and the bounds/dimension error paths both
;;; halves of the API share. Uses BOUNDS-ERROR-IS/DIMENSIONS-ERROR-IS,
;;; defined in t/screen-test.lisp, loaded first.
;;; --------------------------------------------------------------------------

(describe "screen mutation sequence"
  (it "threads a screen through resize, put-cell, clear, write-string, and fill-rect"
    (let ((screen (make-screen 3 2)))
      (expect (screen-width screen) :to-be 3)
      (expect (screen-height screen) :to-be 2)
      (expect-cell (screen 0 0) #\Space)

      (screen-put-cell screen 1 0 #\X)
      (expect-cell (screen 1 0) #\X)

      (let ((resized (screen-resize screen 4 3 :initial-cell #\.)))
        (expect resized :to-be screen)
        (expect (screen-width screen) :to-be 4)
        (expect (screen-height screen) :to-be 3)
        (expect-cell (screen 0 0) #\Space)
        (expect-cell (screen 1 0) #\X)
        (expect-cell (screen 3 2) #\.))

      (screen-put-cell screen 3 2 #\Z :style '(:bold))
      (screen-resize screen 2 1)
      (expect (screen-width screen) :to-be 2)
      (expect (screen-height screen) :to-be 1)
      (expect-cell (screen 0 0) #\Space)
      (expect-cell (screen 1 0) #\X)

      (let ((template (make-cell :char #\R :style '(:underline))))
        (screen-resize screen 3 2 :initial-cell template)
        (expect (screen-cell screen 2 1) :to-be template)
        (expect-cell (screen 2 1) #\R '(:underline)))

      (screen-clear screen)
      (expect-cell (screen 1 0) #\Space)
      (screen-clear screen :cell #\.)
      (expect-cell (screen 0 0) #\.)
      (expect-cell (screen 2 1) #\.)
      (screen-clear screen :cell nil)
      (expect-cell (screen 0 0) #\Space)
      (expect-cell (screen 2 1) #\Space)

      (let ((source (make-cell :char #\A :style '(:bold))))
        (screen-put-cell screen 0 1 source)
        (expect (screen-cell screen 0 1) :to-be source)
        (expect-cell (screen 0 1) #\A '(:bold)))

      (setf (screen-cell screen 2 1) #\T)
      (expect-cell (screen 2 1) #\T)

      (let ((source (make-cell :char #\C :style '(:bold))))
        (screen-put-cell screen 1 1 source :style '(:italic))
        (expect-cell (screen 1 1) #\C '(:italic)))

      (let ((source (make-cell :char #\D :style '(:bold))))
        (screen-put-cell screen 2 0 source :style nil)
        (expect-cell (screen 2 0) #\D))

      (let ((written (screen-write-string screen 0 0 "abc")))
        (expect written :to-be screen)
        (expect-cell (screen 0 0) #\a)
        (expect-cell (screen 1 0) #\b)
        (expect-cell (screen 2 0) #\c))

      (let ((reused (make-screen 4 1)))
        (screen-write-string reused 0 0 "AAAB" :style '(:bold))
        (expect (screen-cell reused 0 0) :to-be (screen-cell reused 1 0))
        (expect (screen-cell reused 1 0) :to-be (screen-cell reused 2 0))
        (expect (screen-cell reused 2 0) :not :to-be (screen-cell reused 3 0))
        (expect-cell (reused 0 0) #\A '(:bold))
        (expect-cell (reused 3 0) #\B '(:bold)))

      (screen-write-string screen 0 1 "xy" :style '(:underline))
      (expect-cell (screen 0 1) #\x '(:underline))
      (expect-cell (screen 1 1) #\y '(:underline))

      (let ((filled (screen-fill-rect screen 0 0 2 2 #\*)))
        (expect filled :to-be screen)
        (expect (screen-cell screen 0 0) :to-be (screen-cell screen 1 1))
        (expect-cell (screen 0 0) #\*)
        (expect-cell (screen 1 0) #\*)
        (expect-cell (screen 0 1) #\*)
        (expect-cell (screen 1 1) #\*))

      (let ((source (make-cell :char #\Q :style '(:bold))))
        (screen-fill-rect screen 1 0 2 1 source)
        (expect (screen-cell screen 1 0) :to-be source)
        (expect (screen-cell screen 1 0) :to-be (screen-cell screen 2 0))
        (expect-cell (screen 1 0) #\Q '(:bold))
        (expect-cell (screen 2 0) #\Q '(:bold)))

      (let ((source (make-cell :char #\S :style '(:bold))))
        (screen-fill-rect screen 0 1 2 1 source :style '(:italic))
        (expect-cell (screen 0 1) #\S '(:italic))
        (expect-cell (screen 1 1) #\S '(:italic)))

      (screen-write-string screen 0 0 "prefix" :start 2 :end 5)
      (expect-cell (screen 0 0) #\e)
      (expect-cell (screen 1 0) #\f)
      (expect-cell (screen 2 0) #\i)

      (let ((source (make-cell :char #\Z :style '(:bold))))
        (screen-clear screen :cell source)
        (expect (screen-cell screen 2 1) :to-be source)
        (expect-cell (screen 2 1) #\Z '(:bold)))

      (let* ((style (list :bold))
             (cell (make-cell :char #\N :style style)))
        (screen-put-cell screen 0 0 cell :style '(:italic))
        (setf (car style) :reverse)
        (expect-cell (screen 0 0) #\N '(:italic)))

      (let* ((style (list :bold))
             (cell (make-cell :char #\P :style '(:underline))))
        (screen-put-cell screen 1 0 cell :style style)
        (setf (car style) :italic)
        (expect-cell (screen 1 0) #\P '(:bold)))

      (bounds-error-is (condition 3 0 3 2) (screen-cell screen 3 0))
      (bounds-error-is (condition -1 0 3 2) (screen-cell screen -1 0))
      (bounds-error-is (condition 0 -1 3 2) (screen-cell screen 0 -1))
      (dimensions-error-is (condition -1 2) (screen-resize screen -1 2))
      (dimensions-error-is (condition -1 2) (screen-fill-rect screen 0 0 -1 2 #\X)))))

(describe "screen initial-cell sharing"
  (it "shares the same cell object across every position filled from a character :initial-cell"
    (let ((filled (make-screen 2 1 :initial-cell #\X)))
      (expect-cell (filled 0 0) #\X)
      (expect-cell (filled 1 0) #\X)
      (expect (aref (cl-tty-kit::screen-cells filled) 0)
              :to-be (aref (cl-tty-kit::screen-cells filled) 1))))
  (it "reuses the exact cell object supplied as :initial-cell"
    (let ((source (make-cell :char #\J :style '(:bold))))
      (let ((filled (make-screen 1 1 :initial-cell source)))
        (expect (screen-cell filled 0 0) :to-be source)
        (expect-cell (filled 0 0) #\J '(:bold)))))
  (it "shares the supplied cell object across every position, with no setf accessors defined"
    (let* ((source (make-cell :char #\N :style '(:underline)))
           (filled (make-screen 2 1 :initial-cell source)))
      (expect (aref (cl-tty-kit::screen-cells filled) 0)
              :to-be (aref (cl-tty-kit::screen-cells filled) 1))
      (expect (screen-cell filled 0 0) :to-be source)
      (expect (fboundp '(setf cell-char)) :to-be-falsy)
      (expect (fboundp '(setf cell-style)) :to-be-falsy)
      (expect-cell (filled 1 0) #\N '(:underline))))
  (it "reuses the exact cell object supplied to screen-clear's :cell across every position"
    (let ((source (make-cell :char #\L :style '(:bold)))
          (filled (make-screen 2 1 :initial-cell #\Space)))
      (screen-clear filled :cell source)
      (expect (length (cl-tty-kit::screen-cells filled)) :to-be 2)
      (expect (aref (cl-tty-kit::screen-cells filled) 0)
              :to-be (aref (cl-tty-kit::screen-cells filled) 1))
      (expect (screen-cell filled 0 0) :to-be source)
      (expect-cell (filled 0 0) #\L '(:bold))
      (expect-cell (filled 1 0) #\L '(:bold)))))

(describe "screen-write-string edge cases"
  (it "writes a :start/:end substring at an offset, leaving surrounding cells alone"
    (let ((partial (make-screen 6 1 :initial-cell #\.)))
      (screen-write-string partial 1 0 "prefix" :start 2 :end 5)
      (expect-cell (partial 0 0) #\.)
      (expect-cell (partial 1 0) #\e)
      (expect-cell (partial 2 0) #\f)
      (expect-cell (partial 3 0) #\i)
      (expect-cell (partial 4 0) #\.)
      (expect-cell (partial 5 0) #\.)))
  (it "writes nothing when :start equals :end"
    (let ((unchanged (make-screen 3 1 :initial-cell #\.)))
      (screen-write-string unchanged 1 0 "prefix" :start 3 :end 3)
      (expect-cell (unchanged 0 0) #\.)
      (expect-cell (unchanged 1 0) #\.)
      (expect-cell (unchanged 2 0) #\.)))
  (it "signals an error and leaves the screen unchanged for invalid :start/:end combinations"
    (let ((unchanged (make-screen 3 1 :initial-cell #\.)))
      (expect (lambda () (screen-write-string unchanged 0 0 "prefix" :start 4 :end 2))
              :to-throw 'error)
      (expect (lambda () (screen-write-string unchanged 0 0 "prefix" :start -1))
              :to-throw 'error)
      (expect (lambda () (screen-write-string unchanged 0 0 "prefix" :end 7))
              :to-throw 'error)
      (expect-cell (unchanged 0 0) #\.)
      (expect-cell (unchanged 1 0) #\.)
      (expect-cell (unchanged 2 0) #\.))))

(describe "screen-write-string style copy-on-write"
  (it "copies :style so later caller-side mutation does not affect already-written cells"
    (let* ((style (list :bold '(:fg 33)))
           (styled (make-screen 2 1)))
      (screen-write-string styled 0 0 "OK" :style style)
      (setf (first style) :italic
            (second style) '(:fg 44))
      (expect-cell (styled 0 0) #\O '(:bold (:fg 33)))
      (expect-cell (styled 1 0) #\K '(:bold (:fg 33))))))

(describe "screen wide-glyph placement"
  (it "reserves a trailing blank cell after a wide glyph, followed by a narrow char"
    (let ((ideograph (code-char #x65E5)))
      (let ((wide (make-screen 3 1 :initial-cell #\.)))
        (screen-write-string wide 0 0 (coerce (list ideograph #\X) 'string))
        (expect-cell (wide 0 0) ideograph)
        (expect-cell (wide 1 0) #\Space)
        (expect-cell (wide 2 0) #\X))))
  (it "reserves a trailing blank cell when a narrow char precedes a wide glyph"
    (let ((ideograph (code-char #x65E5)))
      (let ((wide (make-screen 4 1 :initial-cell #\.)))
        (screen-write-string wide 0 0 (coerce (list #\X ideograph #\Y) 'string))
        (expect-cell (wide 0 0) #\X)
        (expect-cell (wide 1 0) ideograph)
        (expect-cell (wide 2 0) #\Space)
        (expect-cell (wide 3 0) #\Y))))
  (it "applies style to both the wide glyph cell and its blank companion"
    (let ((ideograph (code-char #x65E5)))
      (let ((wide (make-screen 2 1)))
        (screen-write-string wide 0 0 (string ideograph) :style '(:bold))
        (expect-cell (wide 0 0) ideograph '(:bold))
        (expect-cell (wide 1 0) #\Space '(:bold)))))
  (it "signals screen-index-out-of-bounds when a wide glyph would overflow the last column"
    (let ((ideograph (code-char #x65E5)))
      (bounds-error-is
        (condition 1 0 1 1)
        (screen-write-string (make-screen 1 1) 0 0 (string ideograph))))))

(describe "cell copy-on-write"
  (it "produces a distinct cell object with equal char/style, with no setf accessors defined"
    (let ((cell (make-cell :char #\Q :style '(:bold)))
          (copy nil))
      (progn
        (setf copy (copy-cell cell))
        (expect copy :not :to-be cell)
        (expect (fboundp '(setf cell-char)) :to-be-falsy)
        (expect (fboundp '(setf cell-style)) :to-be-falsy))
      (expect (cell-char copy) :to-be #\Q)
      (expect (cell-style copy) :to-equal '(:bold))))
  (it "keeps the copy's style independent of the source cell after mutating the caller-owned list"
    (let* ((style (list :bold))
           (cell (make-cell :char #\S :style style))
           (copy (copy-cell cell)))
      (setf (car style) :italic)
      (expect (cell-style cell) :to-equal '(:bold))
      (expect (cell-style copy) :to-equal '(:bold))))
  (it "keeps a cell's own style independent of the caller-owned list after construction"
    (let* ((style (list :underline))
           (cell (make-cell :char #\M :style style)))
      (setf (car style) :reverse)
      (expect (cell-style cell) :to-equal '(:underline))))
  (it "deep-copies nested style parameter lists so mutating them after copy does not leak"
    (let* ((style (list :bold (list :fg 33) (list :bg 99)))
           (cell (make-cell :char #\K :style style))
           (copy (copy-cell cell)))
      (setf (second (second style)) 44 (second (third style)) 88)
      (expect (cell-style cell) :to-equal '(:bold (:fg 33) (:bg 99)))
      (expect (cell-style copy) :to-equal '(:bold (:fg 33) (:bg 99)))))
  (it "does not expose the internal style list for in-place mutation by callers"
    (let* ((cell (make-cell :char #\V :style '(:bold (:fg 33))))
           (exposed-style (cell-style cell)))
      (setf (car exposed-style) :italic
            (second (second exposed-style)) 44)
      (expect (cell-style cell) :to-equal '(:bold (:fg 33))))))

(describe "render-diff style order independence"
  (it "reports no diff when only the order of independent style attributes differs"
    (let ((cells-a (make-screen 1 1))
          (cells-b (make-screen 1 1)))
      (screen-put-cell cells-a 0 0 #\X :style '(:bold :underline))
      (screen-put-cell cells-b 0 0 #\X :style '(:underline :bold))
      (expect (render-diff cells-a cells-b) :to-equal "")))
  (it "reports no diff when only the order of fg/bg parameters differs"
    (let ((cells-a (make-screen 1 1))
          (cells-b (make-screen 1 1)))
      (screen-put-cell cells-a 0 0 #\X :style '(:bold (:fg 196) (:bg 17)))
      (screen-put-cell cells-b 0 0 #\X :style '((:bg 17) (:fg 196) :bold))
      (expect (render-diff cells-a cells-b) :to-equal ""))))

(describe "cell style normalization"
  (it "keeps a style list already in canonical order without duplicate channels"
    (let ((cell (make-cell :char #\C :style '(:bold (:fg 196) (:bg 17)))))
      (expect (cell-style cell) :to-equal '(:bold (:fg 196) (:bg 17)))))
  (it "keeps only the last occurrence of each repeated color channel"
    (let ((cell (make-cell :char #\C :style '((:fg 12) (:fg 196) (:bg 1) (:bg 17)))))
      (expect (cell-style cell) :to-equal '((:fg 196) (:bg 17)))))
  (it "preserves 24-bit rgb triples for fg/bg channels"
    (let ((cell (make-cell :char #\C :style '(:underline (:fg 1 2 3) (:bg 4 5 6)))))
      (expect (cell-style cell) :to-equal '(:underline (:fg 1 2 3) (:bg 4 5 6)))))
  (it "drops malformed fg/bg channel values, keeping the last valid occurrence"
    (let ((cell (make-cell :char #\C :style '(:bold (:fg 256) (:bg 1 2) (:fg 7)))))
      (expect (cell-style cell) :to-equal '(:bold (:fg 7)))))
  (it "drops a malformed dotted channel entry, keeping other valid attributes"
    (let ((cell (make-cell :char #\C :style '((:fg . 1) :bold))))
      (expect (cell-style cell) :to-equal '(:bold))))
  (it "make-style returns nil for a wholly malformed style list"
    (expect (make-style '(:fg . 1)) :to-be-null))
  (it "defaults to a space character with no style"
    (let ((cell (make-cell)))
      (expect (cell-char cell) :to-be #\Space)
      (expect (cell-style cell) :to-be-null)))
  (it "signals an error for a non-character :char"
    (expect (lambda () (make-cell :char "C")) :to-throw 'error))
  (it "signals an error when copying a non-cell"
    (expect (lambda () (copy-cell :not-a-cell)) :to-throw 'error))
  (it "wraps a bare channel keyword/value pair missing its outer list in canonical form"
    (let ((cell (make-cell :char #\C :style '(:fg 33))))
      (expect (cell-style cell) :to-equal '((:fg 33)))))
  (it "keeps a nil style as nil"
    (let ((cell (make-cell :char #\C :style nil)))
      (expect (cell-style cell) :to-be-null)))
  (it "make-style keeps the last of repeated channel builders"
    (expect (make-style :bold (style-fg 12) (style-fg 196) (style-bg 1 2 3))
            :to-equal '(:bold (:fg 196) (:bg 1 2 3))))
  (it "accepts a style built via make-style/style-fg/style-bg helpers"
    (let ((cell (make-cell
                  :char #\C
                  :style (make-style :underline (style-fg 4 5 6) (style-bg 17)))))
      (expect (cell-style cell) :to-equal '(:underline (:fg 4 5 6) (:bg 17)))))
  (it "style-fg signals an error for an out-of-range 256-color index"
    (expect (lambda () (style-fg 256)) :to-throw 'error))
  (it "style-fg signals an error for an out-of-range rgb component"
    (expect (lambda () (style-fg 1 2 999)) :to-throw 'error))
  (it "style-bg signals an error for a malformed argument count"
    (expect (lambda () (style-bg 1 2)) :to-throw 'error)))

(describe "screen bounds and dimension errors"
  (it "is a no-op for a fully off-screen fill-rect regardless of sign on x/y"
    (let ((zero-area (make-screen 2 2 :initial-cell #\.)))
      (screen-fill-rect zero-area 5 5 0 2 #\X)
      (screen-fill-rect zero-area -3 -4 2 0 #\Y)
      (expect-cell (zero-area 0 0) #\.)
      (expect-cell (zero-area 1 1) #\.)))
  (it "signals bounds-error-is with recorded coordinates for a write overflowing the right edge, leaving the screen unchanged"
    (let ((overflow (make-screen 3 1 :initial-cell #\.)))
      (bounds-error-is (condition 4 0 3 1)
          (screen-write-string overflow 1 0 "abcd"))
      (expect-cell (overflow 0 0) #\.)
      (expect-cell (overflow 1 0) #\.)
      (expect-cell (overflow 2 0) #\.)))
  (it "signals bounds-error-is with recorded coordinates for a fill-rect overflowing the bottom edge, leaving the screen unchanged"
    (let ((overflow (make-screen 3 2 :initial-cell #\.)))
      (bounds-error-is (condition 3 1 3 2)
          (screen-fill-rect overflow 1 0 3 2 #\#))
      (expect-cell (overflow 0 0) #\.)
      (expect-cell (overflow 1 0) #\.)
      (expect-cell (overflow 2 1) #\.)))
  (it "signals dimensions-invalid for a negative width"
    (dimensions-error-is (condition -1 2)
        (make-screen -1 2)))
  (it "signals dimensions-invalid for a negative height"
    (dimensions-error-is (condition 2 -1)
        (make-screen 2 -1)))
  ;; A dimension too large to ever allocate signals the documented condition
  ;; rather than a raw type-error/make-array failure: a non-fixnum bignum side
  ;; and a fixnum side whose product exceeds ARRAY-TOTAL-SIZE-LIMIT.
  (it "signals dimensions-invalid instead of a raw error for dimensions too large to ever allocate"
    (dimensions-error-is (condition #.(expt 10 30) 1)
        (make-screen #.(expt 10 30) 1))
    (dimensions-error-is (condition #.array-total-size-limit 2)
        (make-screen #.array-total-size-limit 2))))
