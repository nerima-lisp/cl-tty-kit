(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Sixel image encoding
;;;
;;; FORMAT-SIXEL turns a raw RGB pixel buffer into a sixel DCS string a
;;; sixel-capable terminal renders as an image. Colors are quantized to the
;;; xterm 256 palette (via RGB-TO-256), the image is emitted in the sixel format
;;; of 6-pixel-tall bands, with per-band color runs cached in one pass.
;;; --------------------------------------------------------------------------

(defparameter +sixel-band-height+ 6
  "The number of pixel rows encoded per sixel band (a sixel byte's six bits).")

(defparameter +max-terminal-image-pixels+ (* 4096 4096)
  "Maximum number of pixels accepted by terminal image encoders.")

(defun %sixel-percent (value)
  "Scale an 8-bit color channel VALUE to sixel's 0-100 percentage."
  (round (* value 100) 255))

(defun %sixel-color-indices (pixels width height)
  "Return per-pixel xterm-256 palette indices and a sorted palette list.
RGB-TO-256 is intentionally called once per pixel; band rendering reuses the
indices instead of requantizing every color pass."
  (let ((indices (make-array (* width height)
                             :element-type '(unsigned-byte 8)))
        (seen (make-array 256 :element-type 'bit :initial-element 0)))
    (dotimes (pixel-index (* width height))
      (let* ((rgb-index (* pixel-index 3))
             (color (rgb-to-256 (aref pixels rgb-index)
                                (aref pixels (+ rgb-index 1))
                                (aref pixels (+ rgb-index 2)))))
        (setf (aref indices pixel-index) color
              (aref seen color) 1)))
    (let ((palette '()))
      (dotimes (color 256)
        (when (= 1 (aref seen color))
          (push color palette)))
      (values indices (nreverse palette)))))

(defun %sixel-emit-run (out char count)
  "Write COUNT copies of sixel data CHAR to OUT, run-length compressed."
  (cond
    ((<= count 0))
    ((<= count 3)
     (dotimes (index count) (write-char char out)))
    (t
     (format out "!~D~C" count char))))

(progn
  (defstruct (%sixel-band-state
              (:constructor %make-sixel-band-state))
    (next-x 0 :type (integer 0))
    run-char
    (run-count 0 :type (integer 0))
    runs)

  (defstruct (%sixel-band-workspace
              (:constructor %make-sixel-band-workspace))
    (states (make-array 256 :initial-element nil))
    (seen (make-array 256 :element-type (quote bit) :initial-element 0))
    colors
    (column-bits (make-array 256
                             :element-type (quote (unsigned-byte 8))
                             :initial-element 0))
    (column-seen (make-array 256 :element-type (quote bit) :initial-element 0))
    column-colors)

  (defun %sixel-band-workspace-reset (workspace)
    (dolist (color (%sixel-band-workspace-colors workspace))
      (let ((state (aref (%sixel-band-workspace-states workspace) color)))
        (setf (sbit (%sixel-band-workspace-seen workspace) color) 0
              (%sixel-band-state-next-x state) 0
              (%sixel-band-state-run-char state) nil
              (%sixel-band-state-run-count state) 0
              (%sixel-band-state-runs state) nil)))
    (setf (%sixel-band-workspace-colors workspace) nil
          (%sixel-band-workspace-column-colors workspace) nil)
    workspace))

(defun %sixel-band-state-flush (state)
  (when (%sixel-band-state-run-char state)
    (push (cons (%sixel-band-state-run-char state)
                (%sixel-band-state-run-count state))
          (%sixel-band-state-runs state))
    (setf (%sixel-band-state-run-char state) nil
          (%sixel-band-state-run-count state) 0)))

(defun %sixel-band-state-add-run (state char count)
  (cond
    ((<= count 0))
    ((eql char (%sixel-band-state-run-char state))
     (incf (%sixel-band-state-run-count state) count))
    (t
     (%sixel-band-state-flush state)
     (setf (%sixel-band-state-run-char state) char
           (%sixel-band-state-run-count state) count))))

(defun %sixel-band-state-add-column (state x char)
  (let ((gap (- x (%sixel-band-state-next-x state))))
    (%sixel-band-state-add-run state #\? gap)
    (%sixel-band-state-add-run state char 1)
    (setf (%sixel-band-state-next-x state) (1+ x))))

(defun %sixel-band-state-finish (state width)
  (%sixel-band-state-add-run state #\?
                             (- width (%sixel-band-state-next-x state)))
  (%sixel-band-state-flush state)
  (nreverse (%sixel-band-state-runs state)))

(defun %sixel-emit-runs (out runs)
  (dolist (run runs)
    (%sixel-emit-run out (car run) (cdr run))))

(defun %sixel-band-runs (workspace color-indices width height base-y)
  "Return sorted colors and RLE state for the band starting at BASE-Y.
The band is scanned once; blank columns are inserted lazily when a color appears
again, which avoids rescanning WIDTH for every palette entry."
  (%sixel-band-workspace-reset workspace)
  (let ((states (%sixel-band-workspace-states workspace))
        (seen (%sixel-band-workspace-seen workspace))
        (colors nil)
        (column-bits (%sixel-band-workspace-column-bits workspace))
        (column-seen (%sixel-band-workspace-column-seen workspace))
        (column-colors nil))
    (dotimes (x width)
      (setf column-colors nil)
      (dotimes (row +sixel-band-height+)
        (let ((y (+ base-y row)))
          (when (< y height)
            (let ((color (aref color-indices (+ (* y width) x))))
              (when (zerop (sbit seen color))
                (setf (sbit seen color) 1)
                (unless (aref states color)
                  (setf (aref states color) (%make-sixel-band-state)))
                (push color colors))
              (when (zerop (sbit column-seen color))
                (setf (sbit column-seen color) 1)
                (push color column-colors))
              (setf (aref column-bits color)
                    (logior (aref column-bits color) (ash 1 row)))))))
      (dolist (color column-colors)
        (%sixel-band-state-add-column
         (aref states color) x (code-char (+ #x3F (aref column-bits color))))
        (setf (aref column-bits color) 0
              (sbit column-seen color) 0)))
    (let ((sorted-colors (sort colors (function <))))
      (setf (%sixel-band-workspace-colors workspace) sorted-colors
            (%sixel-band-workspace-column-colors workspace) column-colors)
      (values sorted-colors states))))

(defun %check-image-dimensions (width height)
  (unless (and (integerp width) (not (minusp width))
               (integerp height) (not (minusp height)))
    (error "Image dimensions must be non-negative integers, got ~Sx~S."
           width height))
  (let ((pixel-count (* width height)))
    (when (> pixel-count +max-terminal-image-pixels+)
      (error "Image dimensions ~Dx~D exceed the ~D pixel limit."
              width height +max-terminal-image-pixels+)))
  (values))

(defun %check-pixel-vector (pixels expected-length format-control &rest format-arguments)
  (unless (vectorp pixels)
    (error "PIXELS must be a vector of octets, got ~S." (type-of pixels)))
  (unless (= (length pixels) expected-length)
    (apply (function error) format-control (length pixels) format-arguments))
  ;; Typed pixel buffers already guarantee octet elements; retain validation for
  ;; generic vectors so callers receive the existing diagnostic on bad values.
  (unless (typep pixels (quote (simple-array (unsigned-byte 8) (*))))
    (dotimes (index expected-length)
      (let ((octet (aref pixels index)))
        (unless (and (integerp octet) (<= 0 octet 255))
          (error "PIXELS element ~D must be an octet, got ~S."
                 index octet)))))
  (values))

(defun format-sixel (pixels width height)
  "Return a sixel DCS string encoding the WIDTH by HEIGHT RGB image in PIXELS.
PIXELS is a flat row-major buffer of WIDTH*HEIGHT*3 octets (R, G, B per pixel);
colors are quantized to the xterm 256 palette. The result is bracketed by the
sixel introducer `ESC P q` and terminator `ESC \\`, ready to write to a
sixel-capable terminal. A zero-area image yields an empty sixel."
  (%check-image-dimensions width height)
  (let ((expected-length (* width height 3)))
    (%check-pixel-vector pixels expected-length
                         "PIXELS length ~D does not match ~Dx~D RGB (expected ~D)."
                         width height expected-length))
  (with-output-to-string (out)
    (format out "~CPq" +escape+)
    (when (and (plusp width) (plusp height))
      (multiple-value-bind (color-indices palette)
          (%sixel-color-indices pixels width height)
        (dolist (color palette)
          (multiple-value-bind (r g b) (color-256-to-rgb color)
            (format out "#~D;2;~D;~D;~D"
                    color (%sixel-percent r) (%sixel-percent g) (%sixel-percent b))))
        (let ((workspace (%make-sixel-band-workspace)))
          (loop for base-y from 0 below height by +sixel-band-height+
                for first-band = t then nil
                do (unless first-band (write-char #\- out))
                   (multiple-value-bind (band-colors states)
                       (%sixel-band-runs workspace color-indices width height base-y)
                     (loop for color in band-colors
                           for first-color = t then nil
                           do (unless first-color (write-char #\$ out))
                              (format out "#~D" color)
                              (%sixel-emit-runs
                               out
                               (%sixel-band-state-finish
                                (aref states color) width))))))))
    (format out "~C\\" +escape+)))
