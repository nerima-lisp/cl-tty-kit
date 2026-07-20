(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun %sixel-gradient-pixels (width height)
  "Build a flat RGB buffer with a horizontal red-to-blue gradient."
  (let ((pixels (make-array (* width height 3) :element-type '(unsigned-byte 8))))
    (dotimes (y height pixels)
      (dotimes (x width)
        (let ((index (* 3 (+ (* y width) x))))
          (setf (aref pixels index) (round (* 255 (/ (- width 1 x) (1- width))))
                (aref pixels (+ index 1)) 0
                (aref pixels (+ index 2)) (round (* 255 (/ x (1- width))))))))))

(defun sixel-image-example ()
  "Encode a small red-to-blue gradient image as a sixel DCS string."
  (cl-tty-kit:format-sixel (%sixel-gradient-pixels 12 6) 12 6))

(defun run-sixel-image-example ()
  (let ((sixel (sixel-image-example)))
    ;; A sixel-capable terminal renders the DCS as an image; elsewhere it is
    ;; inert. Print a summary, then the sequence itself.
    (format t "12x6 red-to-blue gradient -> ~D-byte sixel:~%~A~%"
            (length sixel) sixel)))

(when *cl-tty-kit-run-example-on-load*
  (run-sixel-image-example))
