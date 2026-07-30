(in-package #:cl-tty-kit/test)

(defun %chars (&rest code-points)
  (map 'string #'code-char code-points))

(describe "screen-draw-box"
  (it "draws a single-line Unicode box border and returns the screen"
    (let* ((screen (make-screen 3 3))
           (result (screen-draw-box screen 0 0 3 3)))
      (expect result :to-be screen)
      ;; H=2500 V=2502 TL=250C TR=2510 BL=2514 BR=2518
      (expect (screen-row-string screen 0) :to-equal (%chars #x250C #x2500 #x2510))
      (expect (screen-row-string screen 1) :to-equal (%chars #x2502 #x0020 #x2502))
      (expect (screen-row-string screen 2) :to-equal (%chars #x2514 #x2500 #x2518))))
  (it "draws an ASCII border"
    (let ((screen (make-screen 4 3)))
      (screen-draw-box screen 0 0 4 3 :border :ascii)
      (expect (screen-row-string screen 0) :to-equal "+--+")
      (expect (screen-row-string screen 1) :to-equal "|  |")
      (expect (screen-row-string screen 2) :to-equal "+--+")))
  (it "draws offset from the origin, with style applied to the border"
    (let ((screen (make-screen 5 4)))
      (screen-draw-box screen 1 1 3 2 :border :ascii :style '(:bold))
      (expect (screen-row-string screen 0) :to-equal "     ")
      (expect (screen-row-string screen 1) :to-equal " +-+ ")
      (expect (screen-row-string screen 2) :to-equal " +-+ ")
      (expect-cell (screen 1 1) #\+ '(:bold))
      (expect-cell (screen 2 1) #\- '(:bold))))
  (it "collapses a one-row-tall box to a horizontal line"
    (let ((screen (make-screen 3 1)))
      (screen-draw-box screen 0 0 3 1 :border :ascii)
      (expect (screen-row-string screen 0) :to-equal "---")))
  (it "collapses a one-column-wide box to a vertical line"
    (let ((screen (make-screen 1 3)))
      (screen-draw-box screen 0 0 1 3 :border :ascii)
      (expect (cell-char (screen-cell screen 0 0)) :to-be #\|)
      (expect (cell-char (screen-cell screen 0 2)) :to-be #\|)))
  (it "is a no-op for a zero-area box even at an off-screen origin"
    (let ((screen (make-screen 3 3)))
      (expect (screen-draw-box screen 9 9 0 0) :to-be screen)))
  (it "signals screen-index-out-of-bounds when the box would overflow the screen"
    (let ((screen (make-screen 3 3)))
      (expect (lambda () (screen-draw-box screen 0 0 4 3))
              :to-throw 'screen-index-out-of-bounds)))
  (it "signals screen-dimensions-invalid for a negative width"
    (let ((screen (make-screen 3 3)))
      (expect (lambda () (screen-draw-box screen 0 0 -1 3))
              :to-throw 'screen-dimensions-invalid)))
  (it "signals an error for an unknown :border"
    (let ((screen (make-screen 3 3)))
      (expect (lambda () (screen-draw-box screen 0 0 3 3 :border :nope)) :to-throw)))
  (it "signals a non-type-error for a malformed :title"
    (let ((screen (make-screen 3 3)))
      (expect (lambda () (screen-draw-box screen 0 0 3 3 :title :bad))
              :to-throw (lambda (c) (not (typep c 'type-error))))))
  (it "signals a non-type-error for a malformed :title-align"
    (let ((screen (make-screen 3 3)))
      (expect (lambda () (screen-draw-box screen 0 0 3 3 :title-align :bad))
              :to-throw (lambda (c) (not (typep c 'type-error)))))))

(describe "screen-draw-horizontal-line and screen-draw-vertical-line"
  (it "draws a horizontal ASCII line"
    (let ((screen (make-screen 4 3)))
      (screen-draw-horizontal-line screen 0 0 4 :border :ascii)
      (expect (screen-row-string screen 0) :to-equal "----")))
  (it "draws a vertical ASCII line"
    (let ((screen (make-screen 4 3)))
      (screen-draw-vertical-line screen 0 0 3 :border :ascii)
      (expect (cell-char (screen-cell screen 0 1)) :to-be #\|)
      (expect (cell-char (screen-cell screen 0 2)) :to-be #\|)))
  (it "is a no-op for a zero-length line even off-screen"
    (let ((screen (make-screen 4 3)))
      (expect (screen-draw-horizontal-line screen 10 10 0) :to-be screen))))

(describe "screen-draw-box titles"
  (it "centers the title in the top border by default"
    (let ((screen (make-screen 9 3)))
      (screen-draw-box screen 0 0 9 3 :border :ascii :title "Hi")
      (expect (screen-row-string screen 0) :to-equal "+--Hi---+")))
  (it "left-aligns the title when requested"
    (let ((screen (make-screen 9 3)))
      (screen-draw-box screen 0 0 9 3 :border :ascii :title "Hi" :title-align :left)
      (expect (screen-row-string screen 0) :to-equal "+Hi-----+")))
  (it "right-aligns the title when requested"
    (let ((screen (make-screen 9 3)))
      (screen-draw-box screen 0 0 9 3 :border :ascii :title "Hi" :title-align :right)
      (expect (screen-row-string screen 0) :to-equal "+-----Hi+")))
  (it "clips a title too wide for the interior"
    (let ((screen (make-screen 6 3)))
      (screen-draw-box screen 0 0 6 3 :border :ascii :title "verylong")
      (expect (cell-char (screen-cell screen 0 0)) :to-be #\+)
      (expect (cell-char (screen-cell screen 5 0)) :to-be #\+)))
  (it "leaves a plain border for an empty title"
    (let ((screen (make-screen 9 3)))
      (screen-draw-box screen 0 0 9 3 :border :ascii :title "")
      (expect (screen-row-string screen 0) :to-equal "+-------+")))
  (it "applies :title-style to the title"
    (let ((screen (make-screen 9 3)))
      (screen-draw-box screen 0 0 9 3 :border :ascii :title "Hi" :title-style '(:bold))
      (expect-cell (screen 3 0) #\H '(:bold))))
  (it "falls back to :style for the title when :title-style is absent"
    (let ((screen (make-screen 9 3)))
      (screen-draw-box screen 0 0 9 3 :border :ascii :title "Hi" :style '(:underline))
      (expect-cell (screen 3 0) #\H '(:underline)))))
