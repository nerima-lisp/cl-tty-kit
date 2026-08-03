(in-package #:cl-tty-kit/test)

(defmacro bounds-error-is ((condition x y width height) form)
  "The cl-weave counterpart of the retired SIGNALS-based version: asserts FORM
signals SCREEN-INDEX-OUT-OF-BOUNDS with the given X/Y/WIDTH/HEIGHT recorded on
the condition. Shared by t/screen-test.lisp and t/screen-mutation-test.lisp,
so this file must load first."
  `(expect (lambda () ,form)
           :to-throw (lambda (,condition)
                       (and (typep ,condition 'screen-index-out-of-bounds)
                            (= ,x (screen-index-out-of-bounds-x ,condition))
                            (= ,y (screen-index-out-of-bounds-y ,condition))
                            (= ,width (screen-index-out-of-bounds-width ,condition))
                            (= ,height (screen-index-out-of-bounds-height ,condition))))))

(defmacro dimensions-error-is ((condition width height) form)
  "The cl-weave counterpart of the retired SIGNALS-based version: asserts FORM
signals SCREEN-DIMENSIONS-INVALID with the given WIDTH/HEIGHT recorded on the
condition."
  `(expect (lambda () ,form)
           :to-throw (lambda (,condition)
                       (and (typep ,condition 'screen-dimensions-invalid)
                            (= ,width (screen-dimensions-invalid-width ,condition))
                            (= ,height (screen-dimensions-invalid-height ,condition))))))

(defun %screen-rows (&rest rows)
  "Build a screen from string ROWS, writing each non-space character into place."
  (let* ((height (length rows))
         (width
        (if rows (length (first rows))
          0))
         (screen (make-screen width height)))
    (loop for row in rows
          for y from 0
          do (loop for char across row
            for x from 0
            unless (char= char #\Space)
              do (screen-put-cell screen x y char)))
    screen))

(describe "screen public API argument validation"
  (it "signals a non-type-error for malformed :cell/:style arguments across the API"
    (let ((screen (make-screen 3 2 :initial-cell #\.)))
      (expect-non-type-error (make-screen 1 1 :initial-cell :bad))
      (expect-non-type-error (screen-clear screen :cell :bad))
      (expect-non-type-error (screen-resize screen 3 3 :initial-cell :bad))
      (expect-non-type-error (setf (screen-cell screen 0 0) :bad))
      (expect-non-type-error (screen-put-cell screen 0 0 :bad))
      (expect-non-type-error (screen-fill-rect screen 0 0 1 1 :bad))
      (expect-non-type-error (screen-fill screen :bad))
      (expect-non-type-error (screen-scroll screen :bad))
      (expect-non-type-error (screen-copy :not-a-screen))
      (expect-non-type-error (screen-cell :not-a-screen 0 0))
      (expect-non-type-error (screen-row-string :not-a-screen 0))
      (expect-non-type-error (screen-row-string screen 0 :end nil))
      (expect-non-type-error (screen-write-string screen 0 0 :bad))
      (expect-non-type-error (screen-write-string screen 0 0 "x" :end nil))
      (expect-non-type-error (screen-crop screen :not-a-rect))
      (expect-non-type-error (screen-blit :not-a-screen screen))
      (expect-non-type-error (screen-blit screen :not-a-screen))
      (expect-non-type-error (screen-blit screen screen :dest-x :bad))))
  (it "signals a non-type-error for a malformed :fill on screen-scroll, leaving content unchanged"
    (let ((screen (%screen-rows "A" "B" "C")))
      (expect-non-type-error (screen-scroll screen 1 :fill :bad))
      (expect (screen-to-string screen) :to-equal (format nil "A~%B~%C")))))

(describe "screen-fill"
  (it "fills every cell with a character"
    (let ((screen (make-screen 2 2)))
      (screen-fill screen #\#)
      (expect-cell (screen 0 0) #\#)
      (expect-cell (screen 1 0) #\#)
      (expect-cell (screen 0 1) #\#)
      (expect-cell (screen 1 1) #\#)))
  (it "applies :style to every filled cell"
    (let ((screen (make-screen 2 2)))
      (screen-fill screen #\X :style '(:bold))
      (expect-cell (screen 0 0) #\X '(:bold))
      (expect-cell (screen 1 1) #\X '(:bold))))
  ;; An empty screen is a no-op rather than an error.
  (it "is a no-op on a zero-area screen"
    (expect (progn (screen-fill (make-screen 0 0) #\#) :ok) :to-be :ok)))
(describe "screen mutation batching"
  (it "coalesces multiple cell writes into one generation"
    (let ((screen (make-screen 4 2)))
      (let ((generation (cl-tty-kit::screen-generation screen)))
        (with-screen-batch (screen)
          (screen-put-cell screen 0 0 #\A)
          (screen-put-cell screen 1 0 #\B)
          (screen-put-cell screen 3 1 #\C))
        (expect (cl-tty-kit::screen-generation screen) :to-equal (1+ generation)))))
  (it "keeps nested and empty batches safe"
    (let ((screen (make-screen 2 1)))
      (let ((generation (cl-tty-kit::screen-generation screen)))
        (with-screen-batch (screen)
          (with-screen-batch (screen)
            (screen-put-cell screen 0 0 #\X)))
        (expect (cl-tty-kit::screen-generation screen) :to-equal (1+ generation)))
      (let ((generation (cl-tty-kit::screen-generation screen)))
        (with-screen-batch (screen))
        (expect (cl-tty-kit::screen-generation screen) :to-equal generation)))))

(describe "screen-copy"
  (it "copies dimensions and cell values, then diverges independently after a mutation"
    (let* ((screen (%screen-rows "AB" "CD"))
           (copy (screen-copy screen)))
      (expect (screen-width copy) :to-be (screen-width screen))
      (expect (screen-height copy) :to-be (screen-height screen))
      (expect (render-diff copy screen) :to-equal "")
      (expect (screen-cell copy 1 1) :to-be (screen-cell screen 1 1))
      (screen-put-cell copy 0 0 #\Z)
      (expect (screen-cell copy 0 0) :not :to-be (screen-cell screen 0 0))
      (expect-cell (screen 0 0) #\A)
      (expect-cell (copy 0 0) #\Z))))

(describe "screen-row-string"
  (it "returns the row as a string, with :start/:end substring support"
    (let ((screen (%screen-rows "HELLO" "world")))
      (expect (screen-row-string screen 0) :to-equal "HELLO")
      (expect (screen-row-string screen 1) :to-equal "world")
      (expect (screen-row-string screen 0 :start 1 :end 4) :to-equal "ELL")
      (expect (screen-row-string screen 0 :start 2 :end 2) :to-equal "")))
  (it "signals screen-index-out-of-bounds for an out-of-range row or invalid :start/:end"
    (let ((screen (%screen-rows "HELLO" "world")))
      (expect (lambda () (screen-row-string screen 2)) :to-throw 'screen-index-out-of-bounds)
      (expect (lambda () (screen-row-string screen 0 :end 6)) :to-throw 'screen-index-out-of-bounds)
      (expect (lambda () (screen-row-string screen 0 :start -1)) :to-throw 'screen-index-out-of-bounds)
      (expect (lambda () (screen-row-string screen 0 :start 2 :end 1)) :to-throw 'screen-index-out-of-bounds))))

(describe "screen-scroll"
  (it "shifts rows up, clearing the trailing rows"
    (let ((screen (%screen-rows "A" "B" "C")))
      (screen-scroll screen 1)
      (expect (screen-row-string screen 0) :to-equal "B")
      (expect (screen-row-string screen 1) :to-equal "C")
      (expect (screen-row-string screen 2) :to-equal " ")))
  (it "shifts rows down with a :fill character"
    (let ((screen (%screen-rows "A" "B" "C")))
      (screen-scroll screen -1 :fill #\.)
      (expect (screen-row-string screen 0) :to-equal ".")
      (expect (screen-row-string screen 1) :to-equal "A")
      (expect (screen-row-string screen 2) :to-equal "B")))
  (it "clears everything when the shift is at least the screen height"
    (let ((screen (%screen-rows "A" "B" "C")))
      (screen-scroll screen 5 :fill #\-)
      (expect (screen-row-string screen 0) :to-equal "-")
      (expect (screen-row-string screen 2) :to-equal "-")))
  (it "is a no-op for a zero count"
    (let ((screen (%screen-rows "A" "B")))
      (screen-scroll screen 0)
      (expect (screen-row-string screen 0) :to-equal "A")))
  (it "is a no-op for a zero-width screen regardless of count"
    (let ((screen (make-screen 0 3)))
      (expect (screen-scroll screen 2) :to-be screen)
      (expect (screen-width screen) :to-be 0)
      (expect (screen-height screen) :to-be 3)))
  (it "is a no-op for a zero-height screen regardless of count"
    (let ((screen (make-screen 3 0)))
      (expect (screen-scroll screen -2) :to-be screen)
      (expect (screen-width screen) :to-be 3)
      (expect (screen-height screen) :to-be 0))))

(describe "screen-blit"
  (it "blits a source region at a destination offset, reusing cell values without aliasing"
    (let ((dest (make-screen 4 2 :initial-cell #\.))
          (src (%screen-rows "XY" "ZW")))
      (screen-blit dest src :dest-x 1 :dest-y 0)
      (expect (screen-row-string dest 0) :to-equal ".XY.")
      (expect (screen-row-string dest 1) :to-equal ".ZW.")
      ;; Blitting reuses immutable cell values but never aliases screen vectors.
      (expect (screen-cell dest 1 0) :to-be (screen-cell src 0 0))
      (screen-put-cell src 0 0 #\Q)
      (expect-cell (dest 1 0) #\X)))
  (it "clips a sub-region reading past the source width"
    (let ((dest (make-screen 3 1 :initial-cell #\.))
          (src (%screen-rows "ABCDE")))
      (screen-blit dest src :src-x 3 :width 5)
      (expect (screen-row-string dest 0) :to-equal "DE.")))
  (it "clips at the destination right edge"
    (let ((dest (make-screen 2 1 :initial-cell #\.))
          (src (%screen-rows "AB")))
      (screen-blit dest src :dest-x 1)
      (expect (screen-row-string dest 0) :to-equal ".A")))
  ;; A negative offset clips the top or left edge instead of signaling --
  ;; OFFSET need only be an integer, not non-negative.
  (it "clips the top edge for a negative :dest-y"
    (let ((dest (make-screen 2 2 :initial-cell #\.))
          (src (make-screen 2 2 :initial-cell #\X)))
      (screen-blit dest src :dest-y -1)
      (expect (screen-to-string dest) :to-equal (format nil "XX~%.."))))
  (it "clips consistently for a negative :src-y"
    (let ((dest (make-screen 2 2 :initial-cell #\.))
          (src (make-screen 2 2 :initial-cell #\X)))
      (screen-blit dest src :src-y -1)
      (expect (screen-to-string dest) :to-equal (format nil "..~%XX"))))
  (it "clips the left edge for a negative :dest-x"
    (let ((dest (make-screen 2 2 :initial-cell #\.))
          (src (make-screen 2 2 :initial-cell #\X)))
      (screen-blit dest src :dest-x -1)
      (expect (screen-to-string dest) :to-equal (format nil "X.~%X."))))
  (it "clips consistently for a negative :src-x"
    (let ((dest (make-screen 2 2 :initial-cell #\.))
          (src (make-screen 2 2 :initial-cell #\X)))
      (screen-blit dest src :src-x -1)
      (expect (screen-to-string dest) :to-equal (format nil ".X~%.X"))))
  ;; Self blits preserve the source rectangle for both vertical and horizontal
  ;; overlap, as required by the sequence REPLACE contract.
  (it "preserves the source rectangle across a vertically overlapping self-blit"
    (let ((screen (%screen-rows "ABC" "DEF" "GHI")))
      (screen-blit screen screen :dest-y 1 :height 2)
      (expect (screen-to-string screen) :to-equal (format nil "ABC~%ABC~%DEF"))))
  (it "preserves the source rectangle across a horizontally overlapping self-blit"
    (let ((screen (%screen-rows "ABCDE")))
      (screen-blit screen screen :dest-x 1 :width 4)
      (expect (screen-row-string screen 0) :to-equal "AABCD"))))

(describe "screen-write-lines"
  (it "writes each line into successive rows, clipping to the screen width"
    (let ((screen (make-screen 4 3)))
      (screen-write-lines screen 0 0 '("AB" "CDE" "FGHIJ"))
      ;; Third line is clipped to the 4-column width.
      (expect (screen-to-string screen) :to-equal (format nil "AB  ~%CDE ~%FGHI"))))
  (it "clips to the remaining width when writing at an offset"
    (let ((screen (make-screen 4 1 :initial-cell #\.)))
      (screen-write-lines screen 1 0 '("XYZW"))
      (expect (screen-row-string screen 0) :to-equal ".XYZ")))
  ;; Rows past the bottom are skipped rather than signaling.
  (it "skips rows past the bottom edge rather than signaling"
    (let ((screen (make-screen 3 2)))
      (screen-write-lines screen 0 0 '("aa" "bb" "cc" "dd"))
      (expect (screen-to-string screen) :to-equal (format nil "aa ~%bb "))))
  ;; Style is applied to written cells.
  (it "applies :style to written cells"
    (let ((screen (make-screen 3 1)))
      (screen-write-lines screen 0 0 '("hi") :style '(:bold))
      (expect-cell (screen 0 0) #\h '(:bold))))
  ;; The normalized style remains independent from the caller-owned list.
  (it "copies :style so later caller-side mutation does not affect written cells"
    (let* ((style (list :bold))
           (screen (make-screen 3 2)))
      (screen-write-lines screen 0 0 '("A" "B") :style style)
      (setf (car style) :italic)
      (expect-cell (screen 0 0) #\A '(:bold))
      (expect-cell (screen 0 1) #\B '(:bold))))
  ;; An X at or past the right edge is a silent no-op, not an error --
  ;; distinct from the type-validation cases below, since 5 is itself a
  ;; perfectly valid non-negative integer.
  (it "is a silent no-op for an X at or past the right edge"
    (let ((screen (make-screen 3 1 :initial-cell #\.)))
      (screen-write-lines screen 5 0 '("hi"))
      (expect (screen-row-string screen 0) :to-equal "...")))
  ;; A negative X is likewise a silent no-op, not an error.
  (it "is a silent no-op for a negative X"
    (let ((screen (make-screen 3 1 :initial-cell #\.)))
      (screen-write-lines screen -1 0 '("hi"))
      (expect (screen-row-string screen 0) :to-equal "...")))
  ;; A negative Y drops rows above the top; later rows still land once their
  ;; own Y reaches 0.
  (it "drops rows above the top for a negative Y, landing later rows once Y reaches 0"
    (let ((screen (make-screen 3 2 :initial-cell #\.)))
      (screen-write-lines screen 0 -1 '("aa" "bb"))
      (expect (screen-to-string screen) :to-equal (format nil "bb.~%..."))))
  ;; An empty line is a silent no-op for its own row; later lines still land.
  (it "is a silent no-op for an empty line, still landing later lines"
    (let ((screen (make-screen 3 2 :initial-cell #\.)))
      (screen-write-lines screen 0 0 '("" "hi"))
      (expect (screen-to-string screen) :to-equal (format nil "...~%hi."))))
  (it "signals a non-type-error for malformed arguments"
    (let ((screen (make-screen 4 1)))
      (expect-non-type-error (screen-write-lines :not-a-screen 0 0 '("ok")))
      (expect-non-type-error (screen-write-lines screen :x 0 '("ok")))
      (expect-non-type-error (screen-write-lines screen 0 :y '("ok")))
      (expect-non-type-error (screen-write-lines screen 0 0 '("ok" . "bad")))
      (expect-non-type-error (screen-write-lines screen 0 0 '("ok" :bad))))))

(describe "screen-write-wrapped"
  (it "wraps a paragraph into lines, reporting the visible line count"
    (let ((screen (make-screen 6 3)))
      (multiple-value-bind (result count)
          (screen-write-wrapped screen 0 0 6 "the quick brown fox")
        (expect result :to-be screen)
        ;; Four wrapped lines, three of which fit on the 3-row screen.
        (expect count :to-be 3)
        (expect (screen-to-string screen)
                :to-equal (format nil "the   ~%quick ~%brown ")))))
  ;; WRAP-STRING supplies its ordinary lines without padding.  Preserve existing
  ;; cells after a short write, applying STYLE only to the written cell.
  (it "preserves existing cells after a short write, styling only the written cell"
    (let* ((style (list :bold))
           (screen (make-screen 6 1 :initial-cell #\.)))
      (multiple-value-bind (result count)
          (screen-write-wrapped screen 1 0 4 "x" :style style)
        (setf (car style) :italic)
        (expect result :to-be screen)
        (expect count :to-be 1)
        (expect (screen-row-string screen 0) :to-equal ".x....")
        (expect-cell (screen 1 0) #\x '(:bold))
        (expect-cell (screen 2 0) #\.))))
  ;; Available space at the right edge clips the written text but does not clear
  ;; an already-existing cell in the remaining visible space.
  (it "clips written text at the right edge without clearing the remaining visible cell"
    (let ((screen (make-screen 5 1 :initial-cell #\.)))
      (multiple-value-bind (result count)
          (screen-write-wrapped screen 3 0 4 "x")
        (expect result :to-be screen)
        (expect count :to-be 1)
        (expect (screen-row-string screen 0) :to-equal "...x."))))
  ;; Blank source paragraphs yield visible wrapped lines for COUNT, but their
  ;; empty strings leave the corresponding screen row untouched, even with STYLE.
  (it "counts blank paragraphs as visible lines without touching their row"
    (let ((screen (make-screen 5 3 :initial-cell #\.)))
      (multiple-value-bind (result count)
          (screen-write-wrapped screen 0 0 5 (format nil "top~%~%end") :style '(:underline))
        (expect result :to-be screen)
        (expect count :to-be 3)
        (expect (screen-to-string screen)
                :to-equal (format nil "top..~%.....~%end.."))
        (expect-cell (screen 0 0) #\t '(:underline))
        (expect-cell (screen 0 1) #\.))))
  ;; An X at or past the right edge is a silent no-op reporting COUNT 0.
  (it "is a silent no-op reporting count 0 for an X at or past the right edge"
    (let ((screen (make-screen 3 1 :initial-cell #\.)))
      (multiple-value-bind (result count)
          (screen-write-wrapped screen 5 0 3 "hi")
        (expect result :to-be screen)
        (expect count :to-be 0)
        (expect (screen-row-string screen 0) :to-equal "..."))))
  ;; A negative X is likewise a no-op reporting COUNT 0.
  (it "is a no-op reporting count 0 for a negative X"
    (let ((screen (make-screen 3 1 :initial-cell #\.)))
      (multiple-value-bind (result count)
          (screen-write-wrapped screen -1 0 3 "hi")
        (expect result :to-be screen)
        (expect count :to-be 0)
        (expect (screen-row-string screen 0) :to-equal "..."))))
  ;; A completely off-screen negative Y produces no output.
  (it "produces no output for a completely off-screen negative Y"
    (let ((screen (make-screen 3 1 :initial-cell #\.)))
      (multiple-value-bind (result count)
          (screen-write-wrapped screen 0 -1 3 "hi")
        (expect result :to-be screen)
        (expect count :to-be 0)
        (expect (screen-row-string screen 0) :to-equal "..."))))
  ;; Negative Y clips leading wrapped lines and counts only visible output.
  (it "clips leading wrapped lines for a negative Y, counting only visible output"
    (let ((screen (make-screen 5 2 :initial-cell #\.)))
      (multiple-value-bind (result count)
          (screen-write-wrapped screen 0 -1 5 "one two three")
        (expect result :to-be screen)
        (expect count :to-be 2)
        (expect (screen-to-string screen)
                :to-equal (format nil "two..~%three")))))
  ;; Reaching the final screen row does not scan a later source paragraph.
  (it "does not scan a later source paragraph once the final screen row is reached"
    (let ((calls 0)
          (original (symbol-function 'cl-tty-kit:string-width))
          (screen (make-screen 3 1)))
      (unwind-protect
           (progn
             (setf (symbol-function 'cl-tty-kit:string-width)
                   (lambda (&rest arguments)
                     (incf calls)
                     (apply original arguments)))
             (multiple-value-bind (result count)
                 (screen-write-wrapped screen 0 0 1 (format nil "a b~%c d"))
               (expect result :to-be screen)
               (expect count :to-be 1)
               (expect (screen-row-string screen 0) :to-equal "a  ")
               ;; "a" is buffered and "b" fills the only visible row; the
               ;; following paragraph is never measured.
               (expect calls :to-be 2)))
        (setf (symbol-function 'cl-tty-kit:string-width) original))))
  ;; The writer stops at the screen edge before measuring later words.
  (it "stops at the screen edge before measuring later words"
    (let ((calls 0)
          (original (symbol-function 'cl-tty-kit:string-width))
          (screen (make-screen 3 1)))
      (unwind-protect
           (progn
             (setf (symbol-function 'cl-tty-kit:string-width)
                   (lambda (&rest arguments)
                     (incf calls)
                     (apply original arguments)))
             (multiple-value-bind (result count)
                 (screen-write-wrapped screen 0 0 1 "a b c d e")
               (expect result :to-be screen)
               (expect count :to-be 1)
               (expect (screen-row-string screen 0) :to-equal "a  ")
               ;; "a" is buffered and "b" triggers the first line; no later
               ;; word is measured once the sole screen row has been filled.
               (expect calls :to-be 2)))
        (setf (symbol-function 'cl-tty-kit:string-width) original))))
  (it "stops measuring a long word once the screen width is filled"
    (let ((calls 0)
          (original (symbol-function 'cl-tty-kit::%width-prefix-end))
          (screen (make-screen 3 1)))
      (unwind-protect
           (progn
             (setf (symbol-function 'cl-tty-kit::%width-prefix-end)
                   (lambda (&rest arguments)
                     (incf calls)
                     (apply original arguments)))
             (multiple-value-bind (result count)
                 (screen-write-wrapped screen 0 0 3 "abcdefghijkl")
               (expect result :to-be screen)
               (expect count :to-be 1)
               (expect (screen-row-string screen 0) :to-equal "abc")
               (expect calls :to-be 2)))
        (setf (symbol-function 'cl-tty-kit::%width-prefix-end) original))))
  (it "signals a non-type-error for malformed arguments"
    (let ((screen (make-screen 4 1)))
      (expect-non-type-error (screen-write-wrapped :not-a-screen 0 0 3 "text"))
      (expect-non-type-error (screen-write-wrapped screen :x 0 3 "text"))
      (expect-non-type-error (screen-write-wrapped screen 0 :y 3 "text")))))

(describe "screen-to-string"
  (it "renders each row joined by newlines"
    (let ((screen (%screen-rows "AB" "CD")))
      (expect (screen-to-string screen) :to-equal (format nil "AB~%CD"))))
  (it "renders an empty string for a zero-width, zero-height screen"
    (expect (screen-to-string (make-screen 0 0)) :to-equal ""))
  (it "renders a single blank line for a zero-width, nonzero-height screen"
    (expect (screen-to-string (make-screen 0 2)) :to-equal (format nil "~%")))
  (it "signals a non-type-error for a non-screen argument"
    (expect-non-type-error (screen-to-string :not-a-screen))))

(describe "screen-write-aligned"
  (it "centers text with :align :center :vertical :middle"
    (let ((screen (make-screen 7 3))
          (rect (make-rect :width 7 :height 3)))
      (screen-write-aligned screen rect "hi" :align :center :vertical :middle)
      (expect (screen-to-string screen)
              :to-equal (format nil "       ~%  hi   ~%       "))))
  (it "aligns text with :align :right :vertical :bottom"
    (let ((screen (make-screen 7 3))
          (rect (make-rect :width 7 :height 3)))
      (screen-write-aligned screen rect "hi" :align :right :vertical :bottom)
      (expect (screen-to-string screen)
              :to-equal (format nil "       ~%       ~%     hi"))))
  (it "defaults to top-left alignment"
    (let ((screen (make-screen 7 3))
          (rect (make-rect :width 7 :height 3)))
      (screen-write-aligned screen rect "hi")
      (expect (screen-to-string screen)
              :to-equal (format nil "hi     ~%       ~%       "))))
  ;; Text longer than the rect is clipped to its width.
  (it "clips text longer than the rect to its width"
    (let ((screen (make-screen 3 1)))
      (screen-write-aligned screen (make-rect :width 3 :height 1) "hello")
      (expect (screen-row-string screen 0) :to-equal "hel")))
  ;; A full-width glyph uses two terminal cells for alignment and clipping.
  (dolist (case (list (list :left "表    ")
                      (list :center " 表   ")
                      (list :right "   表 ")))
    (destructuring-bind (align expected) case
      (it (format nil "aligns a full-width glyph using two terminal cells for :align ~A" align)
        (let ((screen (make-screen 5 1)))
          (screen-write-aligned screen (make-rect :width 5 :height 1) "表"
                                :align align)
          (expect (screen-row-string screen 0) :to-equal expected)))))
  (it "leaves a single-cell rect untouched when the glyph needs two cells"
    (let ((screen (make-screen 1 1 :initial-cell #\.)))
      (screen-write-aligned screen (make-rect :width 1 :height 1) "表")
      (expect (screen-row-string screen 0) :to-equal ".")))
  ;; A zero-width or zero-height rect is a silent no-op.
  (it "is a silent no-op for a zero-width rect"
    (let ((screen (make-screen 3 1 :initial-cell #\.)))
      (screen-write-aligned screen (make-rect :width 0 :height 1) "x")
      (expect (screen-row-string screen 0) :to-equal "...")))
  (it "is a silent no-op for a zero-height rect"
    (let ((screen (make-screen 3 1 :initial-cell #\.)))
      (screen-write-aligned screen (make-rect :width 3 :height 0) "x")
      (expect (screen-row-string screen 0) :to-equal "...")))
  ;; Empty text is a silent no-op.
  (it "is a silent no-op for empty text"
    (let ((screen (make-screen 3 1 :initial-cell #\.)))
      (screen-write-aligned screen (make-rect :width 3 :height 1) "")
      (expect (screen-row-string screen 0) :to-equal "...")))
  ;; Style is applied.
  (it "applies :style to the written cell"
    (let ((screen (make-screen 4 1)))
      (screen-write-aligned screen (make-rect :width 4 :height 1) "x"
                            :align :right :style '(:bold))
      (expect-cell (screen 3 0) #\x '(:bold))))
  (it "signals a non-type-error for malformed arguments"
    (let ((screen (make-screen 4 1))
          (rect (make-rect :width 4 :height 1)))
      (expect-non-type-error (screen-write-aligned :not-a-screen rect "x"))
      (expect-non-type-error (screen-write-aligned screen :not-a-rect "x"))
      (expect-non-type-error (screen-write-aligned screen rect :not-a-string))
      (expect-non-type-error (screen-write-aligned screen rect "x" :align :diagonal))
      (expect-non-type-error (screen-write-aligned screen rect "x" :vertical :sideways)))))

(describe "screen-crop"
  (it "crops a sub-rectangle into an independent screen sharing then diverging cells"
    (let* ((screen (%screen-rows "ABCD" "EFGH" "IJKL"))
           (crop (screen-crop screen (make-rect :x 1 :y 1 :width 2 :height 2))))
      (expect (screen-width crop) :to-be 2)
      (expect (screen-height crop) :to-be 2)
      (expect (screen-to-string crop) :to-equal (format nil "FG~%JK"))
      ;; Independent cells.
      (screen-put-cell crop 0 0 #\Z)
      (expect-cell (screen 1 1) #\F)))
  ;; A rect running off the edge yields only the overlap.
  (it "clips a rect running off the edge to the overlap"
    (let* ((screen (%screen-rows "AB" "CD"))
           (crop (screen-crop screen (make-rect :x 1 :y 0 :width 5 :height 5))))
      (expect (screen-width crop) :to-be 1)
      (expect (screen-height crop) :to-be 2)
      (expect (screen-to-string crop) :to-equal (format nil "B~%D"))))
  ;; A fully off-screen rect yields an empty screen.
  (it "produces an empty screen for a fully off-screen rect"
    (let ((crop (screen-crop (%screen-rows "AB") (make-rect :x 9 :y 9 :width 2 :height 2))))
      (expect (screen-width crop) :to-be 0)
      (expect (screen-height crop) :to-be 0))))
