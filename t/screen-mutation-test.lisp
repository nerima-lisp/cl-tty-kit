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
(defun %test-screen-mutation-sequence ()
  (let ((screen (make-screen 3 2)))
    (is (= 3 (screen-width screen)))
    (is (= 2 (screen-height screen)))
    (screen-cells-is screen (0 0 #\Space))

    (screen-put-cell screen 1 0 #\X)
    (screen-cells-is screen (1 0 #\X))

    (let ((resized (screen-resize screen 4 3 :initial-cell #\.)))
      (is (eq screen resized))
      (is (= 4 (screen-width screen)))
      (is (= 3 (screen-height screen)))
      (screen-cells-is screen (0 0 #\Space) (1 0 #\X) (3 2 #\.)))

    (screen-put-cell screen 3 2 #\Z :style '(:bold))
    (screen-resize screen 2 1)
    (is (= 2 (screen-width screen)))
    (is (= 1 (screen-height screen)))
    (screen-cells-is screen (0 0 #\Space) (1 0 #\X))

    (let ((template (make-cell :char #\R :style '(:underline))))
      (screen-resize screen 3 2 :initial-cell template)
      (is (eq template (screen-cell screen 2 1)))
      (screen-cells-is screen (2 1 #\R :style '(:underline))))

    (screen-clear screen)
    (screen-cells-is screen (1 0 #\Space))
    (screen-clear screen :cell #\.)
    (screen-cells-is screen (0 0 #\.) (2 1 #\.))
    (screen-clear screen :cell nil)
    (screen-cells-is screen (0 0 #\Space) (2 1 #\Space))

    (let ((source (make-cell :char #\A :style '(:bold))))
      (screen-put-cell screen 0 1 source)
      (is (eq source (screen-cell screen 0 1)))
      (screen-cells-is screen (0 1 #\A :style '(:bold))))

    (setf (screen-cell screen 2 1) #\T)
    (screen-cells-is screen (2 1 #\T))

    (let ((source (make-cell :char #\C :style '(:bold))))
      (screen-put-cell screen 1 1 source :style '(:italic))
      (screen-cells-is screen (1 1 #\C :style '(:italic))))

    (let ((source (make-cell :char #\D :style '(:bold))))
      (screen-put-cell screen 2 0 source :style nil)
      (screen-cells-is screen (2 0 #\D)))

    (let ((written (screen-write-string screen 0 0 "abc")))
      (is (eq screen written))
      (screen-cells-is screen (0 0 #\a) (1 0 #\b) (2 0 #\c)))

    (let ((reused (make-screen 4 1)))
      (screen-write-string reused 0 0 "AAAB" :style '(:bold))
      (is (eq (screen-cell reused 0 0) (screen-cell reused 1 0)))
      (is (eq (screen-cell reused 1 0) (screen-cell reused 2 0)))
      (is (not (eq (screen-cell reused 2 0) (screen-cell reused 3 0))))
      (screen-cells-is reused
        (0 0 #\A :style '(:bold))
        (3 0 #\B :style '(:bold))))

    (screen-write-string screen 0 1 "xy" :style '(:underline))
    (screen-cells-is screen (0 1 #\x :style '(:underline)) (1 1 #\y :style '(:underline)))

    (let ((filled (screen-fill-rect screen 0 0 2 2 #\*)))
      (is (eq screen filled))
      (is (eq (screen-cell screen 0 0) (screen-cell screen 1 1)))
      (screen-cells-is screen (0 0 #\*) (1 0 #\*) (0 1 #\*) (1 1 #\*)))

    (let ((source (make-cell :char #\Q :style '(:bold))))
      (screen-fill-rect screen 1 0 2 1 source)
      (is (eq source (screen-cell screen 1 0)))
      (is (eq (screen-cell screen 1 0) (screen-cell screen 2 0)))
      (screen-cells-is screen (1 0 #\Q :style '(:bold)) (2 0 #\Q :style '(:bold))))

    (let ((source (make-cell :char #\S :style '(:bold))))
      (screen-fill-rect screen 0 1 2 1 source :style '(:italic))
      (screen-cells-is screen (0 1 #\S :style '(:italic)) (1 1 #\S :style '(:italic))))

    (screen-write-string screen 0 0 "prefix" :start 2 :end 5)
    (screen-cells-is screen (0 0 #\e) (1 0 #\f) (2 0 #\i))

    (let ((source (make-cell :char #\Z :style '(:bold))))
      (screen-clear screen :cell source)
      (is (eq source (screen-cell screen 2 1)))
      (screen-cells-is screen (2 1 #\Z :style '(:bold))))

    (let* ((style (list :bold))
           (cell (make-cell :char #\N :style style)))
      (screen-put-cell screen 0 0 cell :style '(:italic))
      (setf (car style) :reverse)
      (screen-cells-is screen (0 0 #\N :style '(:italic))))

    (let* ((style (list :bold))
           (cell (make-cell :char #\P :style '(:underline))))
      (screen-put-cell screen 1 0 cell :style style)
      (setf (car style) :italic)
      (screen-cells-is screen (1 0 #\P :style '(:bold))))

    (bounds-error-is (condition 3 0 3 2) (screen-cell screen 3 0))
    (bounds-error-is (condition -1 0 3 2) (screen-cell screen -1 0))
    (bounds-error-is (condition 0 -1 3 2) (screen-cell screen 0 -1))
    (dimensions-error-is (condition -1 2) (screen-resize screen -1 2))
    (dimensions-error-is (condition -1 2) (screen-fill-rect screen 0 0 -1 2 #\X))))

(defun %test-screen-initial-cell-sharing ()
  (let ((filled (make-screen 2 1 :initial-cell #\X)))
    (screen-cells-is filled (0 0 #\X) (1 0 #\X))
    (is (eq (aref (cl-tty-kit::screen-cells filled) 0) (aref (cl-tty-kit::screen-cells filled) 1))))
  (let ((source (make-cell :char #\J :style (quote (:bold)))))
    (let ((filled (make-screen 1 1 :initial-cell source)))
      (is (eq source (screen-cell filled 0 0)))
      (cell-is (filled 0 0) #\J (quote (:bold)))))
  (let* ((source (make-cell :char #\N :style (quote (:underline))))
         (filled (make-screen 2 1 :initial-cell source)))
    (is (eq (aref (cl-tty-kit::screen-cells filled) 0) (aref (cl-tty-kit::screen-cells filled) 1)))
    (is (eq source (screen-cell filled 0 0)))
    (is
      (not
        (fboundp
          (quote
            (setf cell-char)))))
    (is
      (not
        (fboundp
          (quote
            (setf cell-style)))))
    (cell-is (filled 1 0) #\N (quote (:underline))))
  (let ((source (make-cell :char #\L :style (quote (:bold))))
        (filled (make-screen 2 1 :initial-cell #\Space)))
    (screen-clear filled :cell source)
    (is (= 2 (length (cl-tty-kit::screen-cells filled))))
    (is (eq (aref (cl-tty-kit::screen-cells filled) 0) (aref (cl-tty-kit::screen-cells filled) 1)))
    (is (eq source (screen-cell filled 0 0)))
    (screen-cells-is
      filled
      (0 0 #\L :style (quote (:bold)))
      (1 0 #\L :style (quote (:bold))))))

(defun %test-screen-write-string-edge-cases ()
  (let ((partial (make-screen 6 1 :initial-cell #\.)))
    (screen-write-string partial 1 0 "prefix" :start 2 :end 5)
    (screen-cells-is
      partial
      (0 0 #\.)
      (1 0 #\e)
      (2 0 #\f)
      (3 0 #\i)
      (4 0 #\.)
      (5 0 #\.)))
  (let ((unchanged (make-screen 3 1 :initial-cell #\.)))
    (screen-write-string unchanged 1 0 "prefix" :start 3 :end 3)
    (screen-cells-is unchanged (0 0 #\.) (1 0 #\.) (2 0 #\.)))
  (let ((unchanged (make-screen 3 1 :initial-cell #\.)))
    (signals
      (error condition)
      (screen-write-string unchanged 0 0 "prefix" :start 4 :end 2)
      (declare (ignore condition)))
    (signals
      (error condition)
      (screen-write-string unchanged 0 0 "prefix" :start -1)
      (declare (ignore condition)))
    (signals
      (error condition)
      (screen-write-string unchanged 0 0 "prefix" :end 7)
      (declare (ignore condition)))
    (screen-cells-is unchanged (0 0 #\.) (1 0 #\.) (2 0 #\.))))

(defun %test-screen-write-string-style-cow ()
  (let* ((style (list :bold '(:fg 33)))
         (styled (make-screen 2 1)))
    (screen-write-string styled 0 0 "OK" :style style)
    (setf (first style) :italic
          (second style) '(:fg 44))
    (screen-cells-is
      styled
      (0 0 #\O :style '(:bold (:fg 33)))
      (1 0 #\K :style '(:bold (:fg 33))))))

(defun %test-screen-wide-glyph-placement ()
  (let ((ideograph (code-char #x65E5)))
    (let ((wide (make-screen 3 1 :initial-cell #\.)))
      (screen-write-string wide 0 0 (coerce (list ideograph #\X) 'string))
      (screen-cells-is wide (0 0 ideograph) (1 0 #\Space) (2 0 #\X)))
    (let ((wide (make-screen 4 1 :initial-cell #\.)))
      (screen-write-string wide 0 0 (coerce (list #\X ideograph #\Y) 'string))
      (screen-cells-is wide (0 0 #\X) (1 0 ideograph) (2 0 #\Space) (3 0 #\Y)))
    (let ((wide (make-screen 2 1)))
      (screen-write-string wide 0 0 (string ideograph) :style '(:bold))
      (screen-cells-is
        wide
        (0 0 ideograph :style '(:bold))
        (1 0 #\Space :style '(:bold))))
    (bounds-error-is
      (condition 1 0 1 1)
      (screen-write-string (make-screen 1 1) 0 0 (string ideograph)))))

(defun %test-cell-copy-on-write ()
  (let ((cell (make-cell :char #\Q :style (quote (:bold))))
        (copy nil))
    (progn
      (setf copy (copy-cell cell))
      (is (not (eq cell copy)))
      (is (not (fboundp (quote (setf cell-char)))))
      (is (not (fboundp (quote (setf cell-style))))))
    (is (char= #\Q (cell-char copy)))
    (is-equal (quote (:bold)) (cell-style copy)))
  (let* ((style (list :bold))
         (cell (make-cell :char #\S :style style))
         (copy (copy-cell cell)))
    (setf (car style) :italic)
    (is-equal (quote (:bold)) (cell-style cell))
    (is-equal (quote (:bold)) (cell-style copy)))
  (let* ((style (list :underline))
         (cell (make-cell :char #\M :style style)))
    (setf (car style) :reverse)
    (is-equal (quote (:underline)) (cell-style cell)))
  (let* ((style (list :bold (list :fg 33) (list :bg 99)))
         (cell (make-cell :char #\K :style style))
         (copy (copy-cell cell)))
    (setf (second (second style)) 44 (second (third style)) 88)
    (is-equal (quote (:bold (:fg 33) (:bg 99))) (cell-style cell))
    (is-equal (quote (:bold (:fg 33) (:bg 99))) (cell-style copy)))
  (let* ((cell (make-cell :char #\V :style (quote (:bold (:fg 33)))))
         (exposed-style (cell-style cell)))
    (setf (car exposed-style) :italic
          (second (second exposed-style)) 44)
    (is-equal (quote (:bold (:fg 33))) (cell-style cell))))

(defun %test-render-diff-style-order-independence ()
  (let ((cells-a (make-screen 1 1))
        (cells-b (make-screen 1 1)))
    (screen-put-cell cells-a 0 0 #\X :style '(:bold :underline))
    (screen-put-cell cells-b 0 0 #\X :style '(:underline :bold))
    (is (string= "" (render-diff cells-a cells-b))))
  (let ((cells-a (make-screen 1 1))
        (cells-b (make-screen 1 1)))
    (screen-put-cell cells-a 0 0 #\X :style '(:bold (:fg 196) (:bg 17)))
    (screen-put-cell cells-b 0 0 #\X :style '((:bg 17) (:fg 196) :bold))
    (is (string= "" (render-diff cells-a cells-b)))))

(defun %test-cell-style-normalization ()
  (let ((cell (make-cell :char #\C :style '(:bold (:fg 196) (:bg 17)))))
    (is-equal '(:bold (:fg 196) (:bg 17)) (cell-style cell)))
  (let ((cell (make-cell :char #\C :style '((:fg 12) (:fg 196) (:bg 1) (:bg 17)))))
    (is-equal '((:fg 196) (:bg 17)) (cell-style cell)))
  (let ((cell (make-cell :char #\C :style '(:underline (:fg 1 2 3) (:bg 4 5 6)))))
    (is-equal '(:underline (:fg 1 2 3) (:bg 4 5 6)) (cell-style cell)))
  (let ((cell (make-cell :char #\C :style '(:bold (:fg 256) (:bg 1 2) (:fg 7)))))
    (is-equal '(:bold (:fg 7)) (cell-style cell)))
  (let ((cell (make-cell :char #\C :style '((:fg . 1) :bold))))
    (is-equal '(:bold) (cell-style cell)))
  (is (null (make-style '(:fg . 1))))
  (let ((cell (make-cell)))
    (is (char= #\Space (cell-char cell)))
    (is (null (cell-style cell))))
  (signals
    (error condition)
    (make-cell :char "C")
    (declare (ignore condition)))
  (signals
    (error condition)
    (copy-cell :not-a-cell)
    (declare (ignore condition)))
  (let ((cell (make-cell :char #\C :style '(:fg 33))))
    (is-equal '((:fg 33)) (cell-style cell)))
  (let ((cell (make-cell :char #\C :style nil)))
    (is (null (cell-style cell))))
  (is-equal
    '(:bold (:fg 196) (:bg 1 2 3))
    (make-style :bold (style-fg 12) (style-fg 196) (style-bg 1 2 3)))
  (let ((cell
        (make-cell
          :char
          #\C
          :style
          (make-style :underline (style-fg 4 5 6) (style-bg 17)))))
    (is-equal '(:underline (:fg 4 5 6) (:bg 17)) (cell-style cell)))
  (signals
    (error condition)
    (style-fg 256)
    (declare (ignore condition)))
  (signals
    (error condition)
    (style-fg 1 2 999)
    (declare (ignore condition)))
  (signals
    (error condition)
    (style-bg 1 2)
    (declare (ignore condition))))

(defun %test-screen-bounds-and-dimension-errors ()
  (let ((zero-area (make-screen 2 2 :initial-cell #\.)))
    (screen-fill-rect zero-area 5 5 0 2 #\X)
    (screen-fill-rect zero-area -3 -4 2 0 #\Y)
    (screen-cells-is zero-area
      (0 0 #\.)
      (1 1 #\.)))

  (let ((overflow (make-screen 3 1 :initial-cell #\.)))
    (bounds-error-is (condition 4 0 3 1)
        (screen-write-string overflow 1 0 "abcd"))
    (screen-cells-is overflow
      (0 0 #\.)
      (1 0 #\.)
      (2 0 #\.)))

  (let ((overflow (make-screen 3 2 :initial-cell #\.)))
    (bounds-error-is (condition 3 1 3 2)
        (screen-fill-rect overflow 1 0 3 2 #\#))
    (screen-cells-is overflow
      (0 0 #\.)
      (1 0 #\.)
      (2 1 #\.)))

  (dimensions-error-is (condition -1 2)
      (make-screen -1 2))
  (dimensions-error-is (condition 2 -1)
      (make-screen 2 -1))
  ;; A dimension too large to ever allocate signals the documented condition
  ;; rather than a raw type-error/make-array failure: a non-fixnum bignum side
  ;; and a fixnum side whose product exceeds ARRAY-TOTAL-SIZE-LIMIT.
  (dimensions-error-is (condition #.(expt 10 30) 1)
      (make-screen #.(expt 10 30) 1))
  (dimensions-error-is (condition #.array-total-size-limit 2)
      (make-screen #.array-total-size-limit 2)))

(defun test-screen ()
  (%test-screen-public-validation)
  (%test-screen-fill)
  (%test-screen-copy)
  (%test-screen-row-string)
  (%test-screen-scroll)
  (%test-screen-blit)
  ;; Self blits preserve the source rectangle for both vertical and horizontal
  ;; overlap, as required by the sequence REPLACE contract.
  (let ((screen (%screen-rows "ABC" "DEF" "GHI")))
    (screen-blit screen screen :dest-y 1 :height 2)
    (is (string= (format nil "ABC~%ABC~%DEF") (screen-to-string screen))))
  (let ((screen (%screen-rows "ABCDE")))
    (screen-blit screen screen :dest-x 1 :width 4)
    (is (string= "AABCD" (screen-row-string screen 0))))
  (%test-screen-write-lines)
  (%test-screen-write-wrapped)
  (%test-screen-to-string)
  (%test-screen-write-aligned)
  (%test-screen-crop)
  (%test-screen-mutation-sequence)
  (%test-screen-initial-cell-sharing)
  (%test-screen-write-string-edge-cases)
  (%test-screen-write-string-style-cow)
  (%test-screen-wide-glyph-placement)
  (%test-cell-copy-on-write)
  (%test-render-diff-style-order-independence)
  (%test-cell-style-normalization)
  (%test-screen-bounds-and-dimension-errors))
