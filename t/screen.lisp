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

(defun %screen-rows (&rest rows)
  "Build a screen from string ROWS, writing each non-space character into place."
  (let* ((height (length rows))
         (width (if rows (length (first rows)) 0))
         (screen (make-screen width height)))
    (loop for row in rows
          for y from 0
          do (loop for char across row
                   for x from 0
                   unless (char= char #\Space)
                     do (screen-put-cell screen x y char)))
    screen))

(defun %test-screen-public-validation ()
  (let ((screen (make-screen 3 2 :initial-cell #\.)))
    (signals-non-type-error (make-screen 1 1 :initial-cell :bad))
    (signals-non-type-error (screen-clear screen :cell :bad))
    (signals-non-type-error (screen-resize screen 3 3 :initial-cell :bad))
    (signals-non-type-error (setf (screen-cell screen 0 0) :bad))
    (signals-non-type-error (screen-put-cell screen 0 0 :bad))
    (signals-non-type-error (screen-fill-rect screen 0 0 1 1 :bad))
    (signals-non-type-error (screen-fill screen :bad))
    (signals-non-type-error (screen-scroll screen :bad))
    (signals-non-type-error (screen-copy :not-a-screen))
    (signals-non-type-error (screen-cell :not-a-screen 0 0))
    (signals-non-type-error (screen-row-string :not-a-screen 0))
    (signals-non-type-error (screen-row-string screen 0 :end nil))
    (signals-non-type-error (screen-write-string screen 0 0 :bad))
    (signals-non-type-error (screen-write-string screen 0 0 "x" :end nil))
    (signals-non-type-error (screen-crop screen :not-a-rect))
    (signals-non-type-error (screen-blit :not-a-screen screen))
    (signals-non-type-error (screen-blit screen :not-a-screen))
    (signals-non-type-error (screen-blit screen screen :dest-x :bad)))
  (let ((screen (%screen-rows "A" "B" "C")))
    (signals-non-type-error (screen-scroll screen 1 :fill :bad))
    (is (string= (format nil "A~%B~%C") (screen-to-string screen)))))

(defun %test-screen-fill ()
  (let ((screen (make-screen 2 2)))
    (screen-fill screen #\#)
    (screen-cells-is screen (0 0 #\#) (1 0 #\#) (0 1 #\#) (1 1 #\#))
    (screen-fill screen #\X :style '(:bold))
    (cell-is (screen 0 0) #\X '(:bold))
    (cell-is (screen 1 1) #\X '(:bold)))
  ;; An empty screen is a no-op rather than an error.
  (is (eq :ok (progn (screen-fill (make-screen 0 0) #\#) :ok))))

(defun %test-screen-copy ()
  (let* ((screen (%screen-rows "AB" "CD"))
         (copy (screen-copy screen)))
    (is (= (screen-width screen) (screen-width copy)))
    (is (= (screen-height screen) (screen-height copy)))
    (is (string= "" (render-diff copy screen)))
    ;; Independent cells: mutating the copy leaves the original alone.
    (screen-put-cell copy 0 0 #\Z)
    (cell-is (screen 0 0) #\A)
    (cell-is (copy 0 0) #\Z)))

(defun %test-screen-row-string ()
  (let ((screen (%screen-rows "HELLO" "world")))
    (is (string= "HELLO" (screen-row-string screen 0)))
    (is (string= "world" (screen-row-string screen 1)))
    (is (string= "ELL" (screen-row-string screen 0 :start 1 :end 4)))
    (is (string= "" (screen-row-string screen 0 :start 2 :end 2)))
    (signals (screen-index-out-of-bounds c) (screen-row-string screen 2) (is c))
    (signals (screen-index-out-of-bounds c)
        (screen-row-string screen 0 :end 6)
      (is c))
    (signals (screen-index-out-of-bounds c)
        (screen-row-string screen 0 :start -1)
      (is c))
    (signals (screen-index-out-of-bounds c)
        (screen-row-string screen 0 :start 2 :end 1)
      (is c))))

(defun %test-screen-scroll ()
  (let ((screen (%screen-rows "A" "B" "C")))
    (screen-scroll screen 1)
    (is (string= "B" (screen-row-string screen 0)))
    (is (string= "C" (screen-row-string screen 1)))
    (is (string= " " (screen-row-string screen 2))))
  (let ((screen (%screen-rows "A" "B" "C")))
    (screen-scroll screen -1 :fill #\.)
    (is (string= "." (screen-row-string screen 0)))
    (is (string= "A" (screen-row-string screen 1)))
    (is (string= "B" (screen-row-string screen 2))))
  ;; A shift at least the height clears everything.
  (let ((screen (%screen-rows "A" "B" "C")))
    (screen-scroll screen 5 :fill #\-)
    (is (string= "-" (screen-row-string screen 0)))
    (is (string= "-" (screen-row-string screen 2))))
  ;; Zero scroll is a no-op.
  (let ((screen (%screen-rows "A" "B")))
    (screen-scroll screen 0)
    (is (string= "A" (screen-row-string screen 0))))
  ;; A zero-width or zero-height screen is a no-op regardless of COUNT.
  (let ((screen (make-screen 0 3)))
    (is (eq screen (screen-scroll screen 2)))
    (is (= 0 (screen-width screen)))
    (is (= 3 (screen-height screen))))
  (let ((screen (make-screen 3 0)))
    (is (eq screen (screen-scroll screen -2)))
    (is (= 3 (screen-width screen)))
    (is (= 0 (screen-height screen)))))

(defun %test-screen-blit ()
  (let ((dest (make-screen 4 2 :initial-cell #\.))
        (src (%screen-rows "XY" "ZW")))
    (screen-blit dest src :dest-x 1 :dest-y 0)
    (is (string= ".XY." (screen-row-string dest 0)))
    (is (string= ".ZW." (screen-row-string dest 1)))
    ;; Independent cells after a blit.
    (screen-put-cell src 0 0 #\Q)
    (cell-is (dest 1 0) #\X))
  ;; Sub-region and clipping past the destination edge.
  (let ((dest (make-screen 3 1 :initial-cell #\.))
        (src (%screen-rows "ABCDE")))
    (screen-blit dest src :src-x 3 :width 5)
    (is (string= "DE." (screen-row-string dest 0))))
  (let ((dest (make-screen 2 1 :initial-cell #\.))
        (src (%screen-rows "AB")))
    (screen-blit dest src :dest-x 1)
    (is (string= ".A" (screen-row-string dest 0))))
  ;; A negative offset clips the top or left edge instead of signaling --
  ;; OFFSET need only be an integer, not non-negative.
  (let ((dest (make-screen 2 2 :initial-cell #\.))
        (src (make-screen 2 2 :initial-cell #\X)))
    (screen-blit dest src :dest-y -1)
    (is (string= (format nil "XX~%..") (screen-to-string dest))))
  (let ((dest (make-screen 2 2 :initial-cell #\.))
        (src (make-screen 2 2 :initial-cell #\X)))
    (screen-blit dest src :src-y -1)
    (is (string= (format nil "..~%XX") (screen-to-string dest))))
  (let ((dest (make-screen 2 2 :initial-cell #\.))
        (src (make-screen 2 2 :initial-cell #\X)))
    (screen-blit dest src :dest-x -1)
    (is (string= (format nil "X.~%X.") (screen-to-string dest))))
  (let ((dest (make-screen 2 2 :initial-cell #\.))
        (src (make-screen 2 2 :initial-cell #\X)))
    (screen-blit dest src :src-x -1)
    (is (string= (format nil ".X~%.X") (screen-to-string dest)))))

(defun %test-screen-write-lines ()
  (let ((screen (make-screen 4 3)))
    (screen-write-lines screen 0 0 '("AB" "CDE" "FGHIJ"))
    ;; Third line is clipped to the 4-column width.
    (is (string= (format nil "AB  ~%CDE ~%FGHI") (screen-to-string screen))))
  ;; Writing at an offset clips to the remaining width.
  (let ((screen (make-screen 4 1 :initial-cell #\.)))
    (screen-write-lines screen 1 0 '("XYZW"))
    (is (string= ".XYZ" (screen-row-string screen 0))))
  ;; Rows past the bottom are skipped rather than signaling.
  (let ((screen (make-screen 3 2)))
    (screen-write-lines screen 0 0 '("aa" "bb" "cc" "dd"))
    (is (string= (format nil "aa ~%bb ") (screen-to-string screen))))
  ;; Style is applied to written cells.
  (let ((screen (make-screen 3 1)))
    (screen-write-lines screen 0 0 '("hi") :style '(:bold))
    (cell-is (screen 0 0) #\h '(:bold)))
  ;; An X at or past the right edge is a silent no-op, not an error --
  ;; distinct from the type-validation cases below, since 5 is itself a
  ;; perfectly valid non-negative integer.
  (let ((screen (make-screen 3 1 :initial-cell #\.)))
    (screen-write-lines screen 5 0 '("hi"))
    (is (string= "..." (screen-row-string screen 0))))
  ;; A negative X is likewise a silent no-op, not an error.
  (let ((screen (make-screen 3 1 :initial-cell #\.)))
    (screen-write-lines screen -1 0 '("hi"))
    (is (string= "..." (screen-row-string screen 0))))
  ;; A negative Y drops rows above the top; later rows still land once their
  ;; own Y reaches 0.
  (let ((screen (make-screen 3 2 :initial-cell #\.)))
    (screen-write-lines screen 0 -1 '("aa" "bb"))
    (is (string= (format nil "bb.~%...") (screen-to-string screen))))
  ;; An empty line is a silent no-op for its own row; later lines still land.
  (let ((screen (make-screen 3 2 :initial-cell #\.)))
    (screen-write-lines screen 0 0 '("" "hi"))
    (is (string= (format nil "...~%hi.") (screen-to-string screen))))
  (let ((screen (make-screen 4 1)))
    (signals-non-type-error (screen-write-lines :not-a-screen 0 0 '("ok")))
    (signals-non-type-error (screen-write-lines screen :x 0 '("ok")))
    (signals-non-type-error (screen-write-lines screen 0 :y '("ok")))
    (signals-non-type-error (screen-write-lines screen 0 0 '("ok" . "bad")))
    (signals-non-type-error (screen-write-lines screen 0 0 '("ok" :bad)))))

(defun %test-screen-write-wrapped ()
  (let ((screen (make-screen 6 3)))
    (multiple-value-bind (result count)
        (screen-write-wrapped screen 0 0 6 "the quick brown fox")
      (is (eq screen result))
      ;; Four wrapped lines, three of which fit on the 3-row screen.
      (is (= 3 count))
      (is (string= (format nil "the   ~%quick ~%brown ")
                   (screen-to-string screen)))))
  ;; An X at or past the right edge is a silent no-op reporting COUNT 0.
  (let ((screen (make-screen 3 1 :initial-cell #\.)))
    (multiple-value-bind (result count)
        (screen-write-wrapped screen 5 0 3 "hi")
      (is (eq screen result))
      (is (= 0 count))
      (is (string= "..." (screen-row-string screen 0)))))
  ;; A negative X is likewise a no-op reporting COUNT 0.
  (let ((screen (make-screen 3 1 :initial-cell #\.)))
    (multiple-value-bind (result count)
        (screen-write-wrapped screen -1 0 3 "hi")
      (is (eq screen result))
      (is (= 0 count))
      (is (string= "..." (screen-row-string screen 0)))))
  ;; A negative Y is likewise a no-op reporting COUNT 0.
  (let ((screen (make-screen 3 1 :initial-cell #\.)))
    (multiple-value-bind (result count)
        (screen-write-wrapped screen 0 -1 3 "hi")
      (is (eq screen result))
      (is (= 0 count))
      (is (string= "..." (screen-row-string screen 0)))))
  (let ((screen (make-screen 4 1)))
    (signals-non-type-error (screen-write-wrapped :not-a-screen 0 0 3 "text"))
    (signals-non-type-error (screen-write-wrapped screen :x 0 3 "text"))
    (signals-non-type-error (screen-write-wrapped screen 0 :y 3 "text"))))

(defun %test-screen-to-string ()
  (let ((screen (%screen-rows "AB" "CD")))
    (is (string= (format nil "AB~%CD") (screen-to-string screen))))
  (is (string= "" (screen-to-string (make-screen 0 0))))
  (signals-non-type-error (screen-to-string :not-a-screen)))

(defun %test-screen-write-aligned ()
  (let ((rect (make-rect :width 7 :height 3)))
    (let ((screen (make-screen 7 3)))
      (screen-write-aligned screen rect "hi" :align :center :vertical :middle)
      (is (string= (format nil "       ~%  hi   ~%       ")
                   (screen-to-string screen))))
    (let ((screen (make-screen 7 3)))
      (screen-write-aligned screen rect "hi" :align :right :vertical :bottom)
      (is (string= (format nil "       ~%       ~%     hi")
                   (screen-to-string screen))))
    (let ((screen (make-screen 7 3)))
      (screen-write-aligned screen rect "hi")
      (is (string= (format nil "hi     ~%       ~%       ")
                   (screen-to-string screen)))))
  ;; Text longer than the rect is clipped to its width.
  (let ((screen (make-screen 3 1)))
    (screen-write-aligned screen (make-rect :width 3 :height 1) "hello")
    (is (string= "hel" (screen-row-string screen 0))))
  ;; A zero-width or zero-height rect is a silent no-op.
  (let ((screen (make-screen 3 1 :initial-cell #\.)))
    (screen-write-aligned screen (make-rect :width 0 :height 1) "x")
    (is (string= "..." (screen-row-string screen 0))))
  (let ((screen (make-screen 3 1 :initial-cell #\.)))
    (screen-write-aligned screen (make-rect :width 3 :height 0) "x")
    (is (string= "..." (screen-row-string screen 0))))
  ;; Empty text is a silent no-op.
  (let ((screen (make-screen 3 1 :initial-cell #\.)))
    (screen-write-aligned screen (make-rect :width 3 :height 1) "")
    (is (string= "..." (screen-row-string screen 0))))
  ;; Style is applied.
  (let ((screen (make-screen 4 1)))
    (screen-write-aligned screen (make-rect :width 4 :height 1) "x"
                          :align :right :style '(:bold))
    (cell-is (screen 3 0) #\x '(:bold)))
  (let ((screen (make-screen 4 1))
        (rect (make-rect :width 4 :height 1)))
    (signals-non-type-error (screen-write-aligned :not-a-screen rect "x"))
    (signals-non-type-error (screen-write-aligned screen :not-a-rect "x"))
    (signals-non-type-error (screen-write-aligned screen rect :not-a-string))
    (signals-non-type-error (screen-write-aligned screen rect "x" :align :diagonal))
    (signals-non-type-error (screen-write-aligned screen rect "x" :vertical :sideways))))

(defun %test-screen-crop ()
  (let* ((screen (%screen-rows "ABCD" "EFGH" "IJKL"))
         (crop (screen-crop screen (make-rect :x 1 :y 1 :width 2 :height 2))))
    (is (= 2 (screen-width crop)))
    (is (= 2 (screen-height crop)))
    (is (string= (format nil "FG~%JK") (screen-to-string crop)))
    ;; Independent cells.
    (screen-put-cell crop 0 0 #\Z)
    (cell-is (screen 1 1) #\F))
  ;; A rect running off the edge yields only the overlap.
  (let* ((screen (%screen-rows "AB" "CD"))
         (crop (screen-crop screen (make-rect :x 1 :y 0 :width 5 :height 5))))
    (is (= 1 (screen-width crop)))
    (is (= 2 (screen-height crop)))
    (is (string= (format nil "B~%D") (screen-to-string crop))))
  ;; A fully off-screen rect yields an empty screen.
  (let ((crop (screen-crop (%screen-rows "AB") (make-rect :x 9 :y 9 :width 2 :height 2))))
    (is (= 0 (screen-width crop)))
    (is (= 0 (screen-height crop)))))

(defun %test-screen-mutation-sequence ()
  (let ((screen (make-screen 3 2)))
    (is (= 3 (screen-width screen)))
    (is (= 2 (screen-height screen)))
    (screen-cells-is screen
      (0 0 #\Space))

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

    (screen-write-string screen 0 0 "prefix" :start 2 :end 5)
    (screen-cells-is screen
      (0 0 #\e)
      (1 0 #\f)
      (2 0 #\i))

    (let ((source (make-cell :char #\Z :style '(:bold))))
      (screen-clear screen :cell source)
      (setf (cell-char source) #\Y
            (cell-style source) '(:italic))
      (screen-cells-is screen
        (2 1 #\Z :style '(:bold))))

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

    (bounds-error-is (condition 3 0 3 2)
        (screen-cell screen 3 0))

    ;; A negative X or Y is out of bounds too, not just an overflow.
    (bounds-error-is (condition -1 0 3 2)
        (screen-cell screen -1 0))
    (bounds-error-is (condition 0 -1 3 2)
        (screen-cell screen 0 -1))

    (dimensions-error-is (condition -1 2)
        (screen-resize screen -1 2))
    (dimensions-error-is (condition -1 2)
        (screen-fill-rect screen 0 0 -1 2 #\X))))

(defun %test-screen-initial-cell-cow ()
  (let ((filled (make-screen 2 1 :initial-cell #\X)))
    (screen-cells-is filled
      (0 0 #\X)
      (1 0 #\X)))

  (let ((source (make-cell :char #\J :style '(:bold))))
    (let ((filled (make-screen 1 1 :initial-cell source)))
      (setf (cell-char source) #\K
            (cell-style source) '(:italic))
      (cell-is (filled 0 0) #\J '(:bold))))

  (let* ((source (make-cell :char #\N :style '(:underline)))
         (filled (make-screen 2 1 :initial-cell source)))
    (is (not (eq (aref (screen-cells filled) 0)
                 (aref (screen-cells filled) 1))))
    (setf (cell-char (aref (screen-cells filled) 0)) #\O)
    (cell-is (filled 1 0) #\N '(:underline)))

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
      (1 0 #\L :style '(:bold)))))

(defun %test-screen-write-string-edge-cases ()
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

  (let ((unchanged (make-screen 3 1 :initial-cell #\.)))
    (signals (error condition)
        (screen-write-string unchanged 0 0 "prefix" :start 4 :end 2)
      (declare (ignore condition)))
    (signals (error condition)
        (screen-write-string unchanged 0 0 "prefix" :start -1)
      (declare (ignore condition)))
    (signals (error condition)
        (screen-write-string unchanged 0 0 "prefix" :end 7)
      (declare (ignore condition)))
    (screen-cells-is unchanged
      (0 0 #\.)
      (1 0 #\.)
      (2 0 #\.))))

(defun %test-screen-write-string-style-cow ()
  (let* ((style (list :bold '(:fg 33)))
         (styled (make-screen 2 1)))
    (screen-write-string styled 0 0 "OK" :style style)
    (setf (first style) :italic
          (second style) '(:fg 44))
    (screen-cells-is styled
      (0 0 #\O :style '(:bold (:fg 33)))
      (1 0 #\K :style '(:bold (:fg 33))))))

(defun %test-screen-wide-glyph-placement ()
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
        (screen-write-string (make-screen 1 1) 0 0 (string ideograph)))))

(defun %test-cell-copy-on-write ()
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

  (let* ((style (list :bold '(:fg 33) '(:bg 99)))
         (cell (make-cell :char #\K :style style))
         (copy (copy-cell cell)))
    (setf (second style) '(:fg 44)
          (third style) '(:bg 88))
    (is-equal '(:bold (:fg 33) (:bg 99))
              (cell-style cell))
    (is-equal '(:bold (:fg 33) (:bg 99))
              (cell-style copy))))

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

  (let ((cell (make-cell :char #\C
                         :style '((:fg . 1) :bold))))
    (is-equal '(:bold)
              (cell-style cell)))

  (is (null (make-style '(:fg . 1))))

  (let ((cell (make-cell)))
    (is (char= #\Space (cell-char cell)))
    (is (null (cell-style cell))))

  (signals (error condition) (make-cell :char "C")
    (declare (ignore condition)))
  (signals (error condition) (copy-cell :not-a-cell)
    (declare (ignore condition)))

  (let ((cell (make-cell :char #\C
                         :style '(:fg 33))))
    (is-equal '((:fg 33))
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
  (%test-screen-write-lines)
  (%test-screen-write-wrapped)
  (%test-screen-to-string)
  (%test-screen-write-aligned)
  (%test-screen-crop)
  (%test-screen-mutation-sequence)
  (%test-screen-initial-cell-cow)
  (%test-screen-write-string-edge-cases)
  (%test-screen-write-string-style-cow)
  (%test-screen-wide-glyph-placement)
  (%test-cell-copy-on-write)
  (%test-render-diff-style-order-independence)
  (%test-cell-style-normalization)
  (%test-screen-bounds-and-dimension-errors))
