(in-package #:cl-tty-kit)

(defmacro %write-screen (screen stream)
  "Write a complete SCREEN repaint to STREAM without command consing."
  `(let ((screen ,screen)
         (stream ,stream))
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
       stream)))

(defmacro %render-screen-output (screen stream)
  `(let ((screen ,screen)
         (stream ,stream))
     (%with-style-sgr-sequence-cache
       (if stream
           (%write-screen screen stream)
           (with-output-to-string (output)
             (%write-screen screen output))))))

(defmacro %write-cursor (cursor stream)
  "Write CURSOR state to STREAM without command consing."
  `(let ((cursor ,cursor)
         (stream ,stream))
     (%write-ansi-move-cursor
       (1+ (cursor-y cursor))
       (1+ (cursor-x cursor))
       stream)
     (%write-ansi-cursor-visibility (cursor-visible-p cursor) stream)
     stream))

(defmacro %render-cursor-output (cursor stream)
  `(let ((cursor ,cursor)
         (stream ,stream))
     (if stream
         (%write-cursor cursor stream)
         (with-output-to-string (output)
           (%write-cursor cursor output)))))

(defmacro %write-frame (screen cursor stream)
  `(let ((screen ,screen)
         (cursor ,cursor)
         (stream ,stream))
     (%write-screen screen stream)
     (%write-cursor cursor stream)))

(defmacro %render-frame-output (screen cursor stream)
  `(let ((screen ,screen)
         (cursor ,cursor)
         (stream ,stream))
     (%with-style-sgr-sequence-cache
       (if stream
           (%write-frame screen cursor stream)
           (with-output-to-string (output)
             (%write-frame screen cursor output))))))

(defmacro %cursor-equal-p (left right)
  `(let ((left ,left)
         (right ,right))
     (and
       (= (cursor-x left) (cursor-x right))
       (= (cursor-y left) (cursor-y right))
       (eq (cursor-visible-p left) (cursor-visible-p right)))))
