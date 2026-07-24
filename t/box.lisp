(in-package #:cl-tty-kit/test)

(defun %chars (&rest code-points)
  (map 'string #'code-char code-points))

(defun %test-box-single ()
  (let* ((screen (make-screen 3 3))
         (result (screen-draw-box screen 0 0 3 3)))
    (is (eq screen result))
    ;; H=2500 V=2502 TL=250C TR=2510 BL=2514 BR=2518
    (is (string= (%chars #x250C #x2500 #x2510) (screen-row-string screen 0)))
    (is (string= (%chars #x2502 #x0020 #x2502) (screen-row-string screen 1)))
    (is (string= (%chars #x2514 #x2500 #x2518) (screen-row-string screen 2)))))

(defun %test-box-ascii ()
  (let ((screen (make-screen 4 3)))
    (screen-draw-box screen 0 0 4 3 :border :ascii)
    (is (string= "+--+" (screen-row-string screen 0)))
    (is (string= "|  |" (screen-row-string screen 1)))
    (is (string= "+--+" (screen-row-string screen 2)))))

(defun %test-box-offset-and-style ()
  (let ((screen (make-screen 5 4)))
    (screen-draw-box screen 1 1 3 2 :border :ascii :style '(:bold))
    (is (string= "     " (screen-row-string screen 0)))
    (is (string= " +-+ " (screen-row-string screen 1)))
    (is (string= " +-+ " (screen-row-string screen 2)))
    (cell-is (screen 1 1) #\+ '(:bold))
    (cell-is (screen 2 1) #\- '(:bold))))

(defun %test-box-lines ()
  (let ((screen (make-screen 4 3)))
    (screen-draw-horizontal-line screen 0 0 4 :border :ascii)
    (is (string= "----" (screen-row-string screen 0)))
    (screen-draw-vertical-line screen 0 0 3 :border :ascii)
    (is (char= #\| (cell-char (screen-cell screen 0 1))))
    (is (char= #\| (cell-char (screen-cell screen 0 2))))
    ;; A zero-length line is a no-op even off-screen.
    (is (eq screen (screen-draw-horizontal-line screen 10 10 0)))))

(defun %test-box-degenerate ()
  ;; One-cell-tall box collapses to a horizontal line.
  (let ((screen (make-screen 3 1)))
    (screen-draw-box screen 0 0 3 1 :border :ascii)
    (is (string= "---" (screen-row-string screen 0))))
  ;; One-cell-wide box collapses to a vertical line.
  (let ((screen (make-screen 1 3)))
    (screen-draw-box screen 0 0 1 3 :border :ascii)
    (is (char= #\| (cell-char (screen-cell screen 0 0))))
    (is (char= #\| (cell-char (screen-cell screen 0 2))))))

(defun %test-box-errors ()
  (let ((screen (make-screen 3 3)))
    (signals (screen-index-out-of-bounds c)
        (screen-draw-box screen 0 0 4 3)
      (is c))
    (signals (screen-dimensions-invalid c)
        (screen-draw-box screen 0 0 -1 3)
      (is c))
    (signals (error c) (screen-draw-box screen 0 0 3 3 :border :nope) (is c))
    (signals-non-type-error (screen-draw-box screen 0 0 3 3 :title :bad))
    (signals-non-type-error (screen-draw-box screen 0 0 3 3 :title-align :bad))
    ;; A zero-area box is a no-op even with an off-screen origin.
    (is (eq screen (screen-draw-box screen 9 9 0 0)))))

(defun %test-box-title ()
  ;; Centered title punched into the top border.
  (let ((screen (make-screen 9 3)))
    (screen-draw-box screen 0 0 9 3 :border :ascii :title "Hi")
    (is (string= "+--Hi---+" (screen-row-string screen 0))))
  ;; Left- and right-aligned titles.
  (let ((screen (make-screen 9 3)))
    (screen-draw-box screen 0 0 9 3 :border :ascii :title "Hi" :title-align :left)
    (is (string= "+Hi-----+" (screen-row-string screen 0))))
  (let ((screen (make-screen 9 3)))
    (screen-draw-box screen 0 0 9 3 :border :ascii :title "Hi" :title-align :right)
    (is (string= "+-----Hi+" (screen-row-string screen 0))))
  ;; A title too wide for the interior is clipped.
  (let ((screen (make-screen 6 3)))
    (screen-draw-box screen 0 0 6 3 :border :ascii :title "verylong")
    (is (char= #\+ (cell-char (screen-cell screen 0 0))))
    (is (char= #\+ (cell-char (screen-cell screen 5 0)))))
  ;; Title style is applied.
  (let ((screen (make-screen 9 3)))
    (screen-draw-box screen 0 0 9 3 :border :ascii :title "Hi"
                     :title-style '(:bold))
    (cell-is (screen 3 0) #\H '(:bold))))

(defun test-box ()
  (%test-box-single)
  (%test-box-ascii)
  (%test-box-offset-and-style)
  (%test-box-lines)
  (%test-box-degenerate)
  (%test-box-errors)
  (%test-box-title)
  t)
