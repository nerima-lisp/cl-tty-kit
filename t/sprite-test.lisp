(in-package #:cl-tty-kit/test)

(describe "sprite-blit"
  (it "composites a rectangular sprite at an offset, leaving surrounding cells untouched"
    (let ((screen (make-screen 6 4 :initial-cell #\.)))
      (expect (sprite-blit screen (format nil "AB~%CD") 1 1) :to-be screen)
      (expect (screen-to-string screen)
              :to-equal (format nil "......~%.AB...~%.CD...~%......"))))
  (it "treats the default transparent marker (space) as pass-through"
    (let ((screen (make-screen 5 1 :initial-cell #\.)))
      (sprite-blit screen " X " 0 0)
      (expect (screen-row-string screen 0) :to-equal ".X...")))
  (it "treats a caller-chosen :transparent character as pass-through"
    (let ((screen (make-screen 5 1 :initial-cell #\.)))
      (sprite-blit screen "-X-" 0 0 :transparent #\-)
      (expect (screen-row-string screen 0) :to-equal ".X...")))
  (it "does not treat a real space as transparent when :transparent overrides it"
    (let ((screen (make-screen 3 1 :initial-cell #\.)))
      (sprite-blit screen " X " 0 0 :transparent #\-)
      (expect (screen-row-string screen 0) :to-equal " X ")))
  (it "treats missing columns on a ragged (shorter) line as transparent"
    (let ((screen (make-screen 4 2 :initial-cell #\.)))
      (sprite-blit screen (format nil "AB~%C") 0 0)
      (expect (screen-to-string screen) :to-equal (format nil "AB..~%C..."))))
  (it "applies :style to non-transparent cells only"
    (let ((screen (make-screen 3 1)))
      (sprite-blit screen "X Y" 0 0 :style '(:bold))
      (expect-cell (screen 0 0) #\X '(:bold))
      (expect-cell (screen 1 0) #\Space)
      (expect-cell (screen 2 0) #\Y '(:bold))))
  (it "is a no-op for an empty string"
    (let ((screen (make-screen 3 1 :initial-cell #\.)))
      (sprite-blit screen "" 0 0)
      (expect (screen-row-string screen 0) :to-equal "...")))
  (it "is a no-op for text consisting only of blank lines"
    (let ((screen (make-screen 3 2 :initial-cell #\.)))
      (sprite-blit screen (format nil "~%") 0 0)
      (expect (screen-to-string screen) :to-equal (format nil "...~%..."))))
  (it "clips the left edge for a negative x"
    (let ((screen (make-screen 3 1 :initial-cell #\.)))
      (sprite-blit screen "AB" -1 0)
      (expect (screen-row-string screen 0) :to-equal "B..")))
  (it "clips the top edge for a negative y"
    (let ((screen (make-screen 1 3 :initial-cell #\.)))
      (sprite-blit screen (format nil "A~%B") 0 -1)
      (expect (screen-to-string screen) :to-equal (format nil "B~%.~%."))))
  (it "clips the right edge when the sprite runs past the screen width"
    (let ((screen (make-screen 3 1 :initial-cell #\.)))
      (sprite-blit screen "ABCDE" 1 0)
      (expect (screen-row-string screen 0) :to-equal ".AB")))
  (it "clips the bottom edge when the sprite runs past the screen height"
    (let ((screen (make-screen 1 3 :initial-cell #\.)))
      (sprite-blit screen (format nil "A~%B~%C~%D") 0 1)
      (expect (screen-to-string screen) :to-equal (format nil ".~%A~%B"))))
  (it "is a no-op when placed entirely off-screen"
    (let ((screen (make-screen 3 3 :initial-cell #\.)))
      (sprite-blit screen "XY" 9 9)
      (expect (screen-to-string screen) :to-equal (format nil "...~%...~%..."))))
  (it "signals a non-type-error for malformed arguments"
    (let ((screen (make-screen 3 3)))
      (expect-non-type-error (sprite-blit :not-a-screen "x" 0 0))
      (expect-non-type-error (sprite-blit screen :not-a-string 0 0))
      (expect-non-type-error (sprite-blit screen "x" :bad 0))
      (expect-non-type-error (sprite-blit screen "x" 0 :bad))
      (expect-non-type-error (sprite-blit screen "x" 0 0 :transparent "bad"))))
  (it "touches the changed row span once and isolates styles per destination cell"
  (let* ((screen (make-screen 4 4 :initial-cell #\.))
         (style (list :bold (list :fg 33)))
         (initial-generation (cl-tty-kit::screen-generation screen)))
    (sprite-blit screen (format nil "AB~%~% CD~%") -1 1 :style style)
    (let ((generation (cl-tty-kit::screen-generation screen)))
      (expect generation :to-equal (1+ initial-generation))
      (expect (aref (cl-tty-kit::screen-row-generations screen) 0)
              :to-equal initial-generation)
      (loop for row from 1 below 4
            do (expect (aref (cl-tty-kit::screen-row-generations screen) row)
                       :to-equal generation)))
    (expect (screen-to-string screen)
            :to-equal (format nil "....~%B...~%....~%CD.."))
    (expect (cell-style (screen-cell screen 0 1))
            :to-equal '(:bold (:fg 33))')
    (it "does not touch generation for transparent or fully clipped sprites"
  (let* ((screen (make-screen 3 2 :initial-cell #\.))
         (generation (cl-tty-kit::screen-generation screen))
         (row-generations
           (copy-seq (cl-tty-kit::screen-row-generations screen))))
    (sprite-blit screen (format nil "   ~% ") 0 0 :style '(:bold)')
    (sprite-blit screen "XY" 9 9 :style '(:underline)')
    (expect (cl-tty-kit::screen-generation screen) :to-equal generation)
    (expect (cl-tty-kit::screen-row-generations screen)
            :to-equal row-generations)
    (expect (screen-to-string screen) :to-equal (format nil "...~%..."))))
    (expect (cl-tty-kit::cell-raw-style (screen-cell screen 0 1))
            :not :to-be (cl-tty-kit::cell-raw-style (screen-cell screen 0 3)))))
  (it "signals a non-type-error for malformed arguments"
    (let ((screen (make-screen 3 3)))
      (expect-non-type-error (sprite-blit :not-a-screen "x" 0 0))
      (expect-non-type-error (sprite-blit screen :not-a-string 0 0))
      (expect-non-type-error (sprite-blit screen "x" :bad 0))
      (expect-non-type-error (sprite-blit screen "x" 0 :bad))
      (expect-non-type-error (sprite-blit screen "x" 0 0 :transparent "bad")))))
