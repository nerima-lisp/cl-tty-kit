(in-package #:cl-tty-kit)

(defun %write-screen (screen stream)
  "Write a complete SCREEN repaint to STREAM without command consing."
  (let ((cells (screen-cells screen))
        (width (screen-width screen))
        (height (screen-height screen)))
    (declare (type simple-vector cells)
             (type fixnum width height))
    (%write-ansi-clear-screen stream)
    (%write-ansi-move-cursor 1 1 stream)
    (do ((y 0 (1+ y))
         (row-start 0 (+ row-start width)))
        ((>= y height))
      (declare (type fixnum y row-start))
      (%write-cell-range cells row-start (+ row-start width) stream)
      (unless (= y (1- height))
        (write-char #\Newline stream)))
    stream))

(defun %render-screen-output (screen stream)
  (%with-style-sgr-sequence-cache
    (if stream
        (%write-screen screen stream)
        (with-output-to-string (output)
          (%write-screen screen output)))))

(defun %write-cursor (cursor stream)
  "Write CURSOR state to STREAM without command consing."
  (%write-ansi-move-cursor
    (1+ (cursor-y cursor))
    (1+ (cursor-x cursor))
    stream)
  (%write-ansi-cursor-visibility (cursor-visible-p cursor) stream)
  stream)

(defun %render-cursor-output (cursor stream)
  (if stream
      (%write-cursor cursor stream)
      (with-output-to-string (output)
        (%write-cursor cursor output))))

(defun %write-frame (screen cursor stream)
  (%write-screen screen stream)
  (%write-cursor cursor stream))

(defun %render-frame-output (screen cursor stream)
  (%with-style-sgr-sequence-cache
    (if stream
        (%write-frame screen cursor stream)
        (with-output-to-string (output)
          (%write-frame screen cursor output)))))

(defun %cursor-equal-p (left right)
  (and
    (= (cursor-x left) (cursor-x right))
    (= (cursor-y left) (cursor-y right))
    (eq (cursor-visible-p left) (cursor-visible-p right))))
