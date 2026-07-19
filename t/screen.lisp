(in-package #:cl-tty-kit/test)

(defmacro bounds-error-is ((condition x y width height) form)
  `(signals (screen-index-out-of-bounds ,condition) ,form
     (is (= ,x (screen-index-out-of-bounds-x ,condition)))
     (is (= ,y (screen-index-out-of-bounds-y ,condition)))
     (is (= ,width (screen-index-out-of-bounds-width ,condition)))
     (is (= ,height (screen-index-out-of-bounds-height ,condition)))))

(defmacro dimensions-error-is ((condition width height) form)
  `(signals (screen-dimensions-invalid ,condition) ,form
     (is (= ,width (screen-dimensions-invalid-width ,condition)))
     (is (= ,height (screen-dimensions-invalid-height ,condition)))))

(defun test-screen ()
  (let ((screen (make-screen 3 2)))
    (is (= 3 (screen-width screen)))
    (is (= 2 (screen-height screen)))
    (screen-cells-is screen
      (0 0 #\Space))

    (let ((filled (make-screen 2 1 :initial-cell #\X)))
      (screen-cells-is filled
        (0 0 #\X)
        (1 0 #\X)))

    (let ((source (make-cell :char #\J :style '(:bold))))
      (let ((filled (make-screen 1 1 :initial-cell source)))
        (setf (cell-char source) #\K
              (cell-style source) '(:italic))
        (cell-is (filled 0 0) #\J '(:bold))))

    (let ((source (make-cell :char #\L :style '(:bold)))
          (filled (make-screen 2 1 :initial-cell #\Space)))
      (screen-clear filled :cell source)
      (is (= 2 (length (screen-cells filled))))
      (is (not (eq (aref (screen-cells filled) 0)
                   (aref (screen-cells filled) 1))))
      (setf (cell-char source) #\M
            (cell-style source) '(:italic))
      (screen-cells-is filled
        (0 0 #\L :style '(:bold))
        (1 0 #\L :style '(:bold))))

    (screen-put-cell screen 1 0 #\X)
    (screen-cells-is screen
      (1 0 #\X))

    (let ((resized (screen-resize screen 4 3 :initial-cell #\.)))
      (is (eq screen resized))
      (is (= 4 (screen-width screen)))
      (is (= 3 (screen-height screen)))
      (screen-cells-is screen
        (0 0 #\Space)
        (1 0 #\X)
        (3 2 #\.)))

    (screen-put-cell screen 3 2 #\Z :style '(:bold))
    (screen-resize screen 2 1)
    (is (= 2 (screen-width screen)))
    (is (= 1 (screen-height screen)))
    (screen-cells-is screen
      (0 0 #\Space)
      (1 0 #\X))

    (let ((template (make-cell :char #\R :style '(:underline))))
      (screen-resize screen 3 2 :initial-cell template)
      (setf (cell-char template) #\S
            (cell-style template) '(:italic))
      (screen-cells-is screen
        (2 1 #\R :style '(:underline))))

    (screen-clear screen)
    (screen-cells-is screen
      (1 0 #\Space))
    (screen-clear screen :cell #\.)
    (screen-cells-is screen
      (0 0 #\.)
      (2 1 #\.))
    (screen-clear screen :cell nil)
    (screen-cells-is screen
      (0 0 #\Space)
      (2 1 #\Space))

    (let ((source (make-cell :char #\A :style '(:bold))))
      (screen-put-cell screen 0 1 source)
      (setf (cell-char source) #\B
            (cell-style source) '(:italic))
      (screen-cells-is screen
        (0 1 #\A :style '(:bold))))

    (setf (screen-cell screen 2 1) #\T)
    (screen-cells-is screen
      (2 1 #\T))

    (let ((source (make-cell :char #\C :style '(:bold))))
      (screen-put-cell screen 1 1 source :style '(:italic))
      (screen-cells-is screen
        (1 1 #\C :style '(:italic))))

    (let ((source (make-cell :char #\D :style '(:bold))))
      (screen-put-cell screen 2 0 source :style nil)
      (screen-cells-is screen
        (2 0 #\D)))

    (let ((written (screen-write-string screen 0 0 "abc")))
      (is (eq screen written))
      (screen-cells-is screen
        (0 0 #\a)
        (1 0 #\b)
        (2 0 #\c)))

    (screen-write-string screen 0 1 "xy" :style '(:underline))
    (screen-cells-is screen
      (0 1 #\x :style '(:underline))
      (1 1 #\y :style '(:underline)))

    (let ((filled (screen-fill-rect screen 0 0 2 2 #\*)))
      (is (eq screen filled))
      (screen-cells-is screen
        (0 0 #\*)
        (1 0 #\*)
        (0 1 #\*)
        (1 1 #\*)))

    (let ((source (make-cell :char #\Q :style '(:bold))))
      (screen-fill-rect screen 1 0 2 1 source)
      (setf (cell-char source) #\R
            (cell-style source) '(:italic))
      (screen-cells-is screen
        (1 0 #\Q :style '(:bold))
        (2 0 #\Q :style '(:bold))))

    (let ((source (make-cell :char #\S :style '(:bold))))
      (screen-fill-rect screen 0 1 2 1 source :style '(:italic))
      (screen-cells-is screen
        (0 1 #\S :style '(:italic))
        (1 1 #\S :style '(:italic))))

    (let ((zero-area (make-screen 2 2 :initial-cell #\.)))
      (screen-fill-rect zero-area 5 5 0 2 #\X)
      (screen-fill-rect zero-area -3 -4 2 0 #\Y)
      (screen-cells-is zero-area
        (0 0 #\.)
        (1 1 #\.)))

    (screen-write-string screen 0 0 "prefix" :start 2 :end 5)
    (screen-cells-is screen
      (0 0 #\e)
      (1 0 #\f)
      (2 0 #\i))

    (let ((partial (make-screen 6 1 :initial-cell #\.)))
      (screen-write-string partial 1 0 "prefix" :start 2 :end 5)
      (screen-cells-is partial
        (0 0 #\.)
        (1 0 #\e)
        (2 0 #\f)
        (3 0 #\i)
        (4 0 #\.)
        (5 0 #\.)))

    (let ((unchanged (make-screen 3 1 :initial-cell #\.)))
      (screen-write-string unchanged 1 0 "prefix" :start 3 :end 3)
      (screen-cells-is unchanged
        (0 0 #\.)
        (1 0 #\.)
        (2 0 #\.)))

    (let* ((style (list :bold '(:fg 33)))
           (styled (make-screen 2 1)))
      (screen-write-string styled 0 0 "OK" :style style)
      (setf (first style) :italic
            (second style) '(:fg 44))
      (screen-cells-is styled
        (0 0 #\O :style '(:bold (:fg 33)))
        (1 0 #\K :style '(:bold (:fg 33)))))

    (let ((ideograph (code-char #x65E5)))
      (let ((wide (make-screen 3 1 :initial-cell #\.)))
        (screen-write-string wide 0 0 (coerce (list ideograph #\X) 'string))
        (screen-cells-is wide
          (0 0 ideograph)
          (1 0 #\Space)
          (2 0 #\X)))

      (let ((wide (make-screen 4 1 :initial-cell #\.)))
        (screen-write-string wide 0 0 (coerce (list #\X ideograph #\Y) 'string))
        (screen-cells-is wide
          (0 0 #\X)
          (1 0 ideograph)
          (2 0 #\Space)
          (3 0 #\Y)))

      (let ((wide (make-screen 2 1)))
        (screen-write-string wide 0 0 (string ideograph) :style '(:bold))
        (screen-cells-is wide
          (0 0 ideograph :style '(:bold))
          (1 0 #\Space :style '(:bold))))

      (bounds-error-is (condition 1 0 1 1)
          (screen-write-string (make-screen 1 1) 0 0 (string ideograph))))

    (let ((source (make-cell :char #\Z :style '(:bold))))
      (screen-clear screen :cell source)
      (setf (cell-char source) #\Y
            (cell-style source) '(:italic))
      (screen-cells-is screen
        (2 1 #\Z :style '(:bold))))

    (let ((cell (make-cell :char #\Q :style '(:bold)))
          (copy nil))
      (setf copy (copy-cell cell)
            (cell-char cell) #\R
            (cell-style cell) '(:italic))
      (is (char= #\Q (cell-char copy)))
      (is-equal '(:bold) (cell-style copy)))

    (let* ((style (list :bold))
           (cell (make-cell :char #\S :style style))
           (copy (copy-cell cell)))
      (setf (car style) :italic)
      (is-equal '(:bold) (cell-style cell))
      (is-equal '(:bold) (cell-style copy)))

    (let* ((style (list :underline))
           (cell (make-cell :char #\M :style style)))
      (setf (car style) :reverse)
      (is-equal '(:underline) (cell-style cell)))

    (let* ((style (list :bold))
           (cell (make-cell :char #\N :style style)))
      (screen-put-cell screen 0 0 cell :style '(:italic))
      (setf (car style) :reverse)
      (screen-cells-is screen
        (0 0 #\N :style '(:italic))))

    (let* ((style (list :bold))
           (cell (make-cell :char #\P :style '(:underline))))
      (screen-put-cell screen 1 0 cell :style style)
      (setf (car style) :italic)
      (screen-cells-is screen
        (1 0 #\P :style '(:bold))))

    (let ((cells-a (make-screen 1 1))
          (cells-b (make-screen 1 1)))
      (screen-put-cell cells-a 0 0 #\X :style '(:bold :underline))
      (screen-put-cell cells-b 0 0 #\X :style '(:underline :bold))
      (is (string= "" (render-diff cells-a cells-b))))

    (let ((cell (make-cell :char #\C :style '(:bold (:fg 196) (:bg 17)))))
      (is-equal '(:bold (:fg 196) (:bg 17))
                (cell-style cell)))

    (let ((cell (make-cell :char #\C
                           :style '((:fg 12) (:fg 196) (:bg 1) (:bg 17)))))
      (is-equal '((:fg 196) (:bg 17))
                (cell-style cell)))

    (let ((cell (make-cell :char #\C
                           :style '(:underline (:fg 1 2 3) (:bg 4 5 6)))))
      (is-equal '(:underline (:fg 1 2 3) (:bg 4 5 6))
                (cell-style cell)))

    (let ((cell (make-cell :char #\C
                           :style '(:bold (:fg 256) (:bg 1 2) (:fg 7)))))
      (is-equal '(:bold (:fg 7))
                (cell-style cell)))

    (let ((cell (make-cell)))
      (is (char= #\Space (cell-char cell)))
      (is (null (cell-style cell))))

    (let ((cell (make-cell :char #\C
                           :style '(:fg 33))))
      (is-equal '(:fg (:fg 33))
                (cell-style cell)))

    (let ((cell (make-cell :char #\C :style nil)))
      (is (null (cell-style cell))))

    (is-equal '(:bold (:fg 196) (:bg 1 2 3))
              (make-style :bold
                          (style-fg 12)
                          (style-fg 196)
                          (style-bg 1 2 3)))

    (let ((cell (make-cell :char #\C
                           :style (make-style :underline
                                              (style-fg 4 5 6)
                                              (style-bg 17)))))
      (is-equal '(:underline (:fg 4 5 6) (:bg 17))
                (cell-style cell)))

    (signals (error condition) (style-fg 256)
      (declare (ignore condition)))
    (signals (error condition) (style-fg 1 2 999)
      (declare (ignore condition)))
    (signals (error condition) (style-bg 1 2)
      (declare (ignore condition)))

    (let* ((style (list :bold '(:fg 33) '(:bg 99)))
           (cell (make-cell :char #\K :style style))
           (copy (copy-cell cell)))
      (setf (second style) '(:fg 44)
            (third style) '(:bg 88))
      (is-equal '(:bold (:fg 33) (:bg 99))
                (cell-style cell))
      (is-equal '(:bold (:fg 33) (:bg 99))
                (cell-style copy)))

    (let ((cells-a (make-screen 1 1))
          (cells-b (make-screen 1 1)))
      (screen-put-cell cells-a 0 0 #\X :style '(:bold (:fg 196) (:bg 17)))
      (screen-put-cell cells-b 0 0 #\X :style '((:bg 17) (:fg 196) :bold))
      (is (string= "" (render-diff cells-a cells-b))))

    (bounds-error-is (condition 3 0 3 2)
        (screen-cell screen 3 0))

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
    (dimensions-error-is (condition -1 2)
        (screen-resize screen -1 2))
    (dimensions-error-is (condition -1 2)
        (screen-fill-rect screen 0 0 -1 2 #\X))
    ;; A dimension too large to ever allocate signals the documented condition
    ;; rather than a raw type-error/make-array failure: a non-fixnum bignum side
    ;; and a fixnum side whose product exceeds ARRAY-TOTAL-SIZE-LIMIT.
    (dimensions-error-is (condition #.(expt 10 30) 1)
        (make-screen #.(expt 10 30) 1))
    (dimensions-error-is (condition #.array-total-size-limit 2)
        (make-screen #.array-total-size-limit 2))))
