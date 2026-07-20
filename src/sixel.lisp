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

(defstruct (%sixel-band-state
            (:constructor %make-sixel-band-state))
  (next-x 0 :type (integer 0))
  run-char
  (run-count 0 :type (integer 0))
  runs)

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

(defun %sixel-band-runs (color-indices width height base-y)
  "Return sorted colors and RLE state for the band starting at BASE-Y.
The band is scanned once; blank columns are inserted lazily when a color appears
again, which avoids rescanning WIDTH for every palette entry."
  (let ((states (make-array 256 :initial-element nil))
        (seen (make-array 256 :element-type 'bit :initial-element 0))
        (colors '())
        (column-bits (make-array 256
                                 :element-type '(unsigned-byte 8)
                                 :initial-element 0))
        (column-seen (make-array 256 :element-type 'bit :initial-element 0))
        (column-colors '()))
    (dotimes (x width)
      (setf column-colors '())
      (dotimes (row +sixel-band-height+)
        (let ((y (+ base-y row)))
          (when (< y height)
            (let ((color (aref color-indices (+ (* y width) x))))
              (when (zerop (sbit seen color))
                (setf (sbit seen color) 1
                      (aref states color) (%make-sixel-band-state))
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
    (values (sort colors #'<) states)))

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

(defun %check-pixel-vector (pixels expected-length format-control
                            &rest format-arguments)
  (unless (vectorp pixels)
    (error "PIXELS must be a vector of octets, got ~S." (type-of pixels)))
  (unless (= (length pixels) expected-length)
    (apply #'error format-control (length pixels) format-arguments))
  (dotimes (index expected-length)
    (let ((octet (aref pixels index)))
      (unless (and (integerp octet) (<= 0 octet 255))
        (error "PIXELS element ~D must be an octet, got ~S."
               index octet))))
  (values))

(defun format-sixel (pixels width height)
  "Return a sixel DCS string encoding the WIDTH by HEIGHT RGB image in PIXELS.
PIXELS is a flat row-major buffer of WIDTH*HEIGHT*3 octets (R, G, B per pixel);
colors are quantized to the xterm 256 palette. The result is bracketed by the
sixel introducer `ESC P q' and terminator `ESC \\', ready to write to a
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
         (loop for base-y from 0 below height by +sixel-band-height+
               for first-band = t then nil
               do (unless first-band (write-char #\- out))
                  (multiple-value-bind (band-colors states)
                      (%sixel-band-runs color-indices width height base-y)
                    (loop for color in band-colors
                          for first-color = t then nil
                          do (unless first-color (write-char #\$ out))
                             (format out "#~D" color)
                             (%sixel-emit-runs
                              out
                              (%sixel-band-state-finish
                               (aref states color) width)))))))
    (format out "~C\\" +escape+)))

;;; --------------------------------------------------------------------------
;;; Kitty graphics protocol
;;;
;;; A different terminal-image mechanism from sixel: kitty, WezTerm, and Konsole
;;; render it, and they generally do not speak sixel -- so FORMAT-SIXEL and
;;; ANSI-KITTY-IMAGE together broaden bitmap coverage rather than duplicate it.
;;; The image is base64-encoded and split into APC (`ESC _ G ... ESC \') chunks.
;;; --------------------------------------------------------------------------

(defparameter +kitty-chunk-size+ 4096
  "Maximum base64 payload characters per kitty graphics APC chunk.")

(defun ansi-kitty-image (pixels width height &key (format 24))
  "Return a kitty graphics protocol escape that transmits and displays the
WIDTH by HEIGHT image in PIXELS. PIXELS is a flat octet buffer; FORMAT is 24 for
packed RGB (WIDTH*HEIGHT*3 bytes) or 32 for RGBA (WIDTH*HEIGHT*4). The payload is
base64-encoded and split into APC chunks (`m=1' on all but the last). Rendered by
terminals that speak the kitty graphics protocol (kitty, WezTerm, Konsole) and
  inert elsewhere -- the kitty-ecosystem counterpart to FORMAT-SIXEL, which serves
  the sixel terminals."
  (%check-image-dimensions width height)
  (let ((bytes-per-pixel
          (case format
            (24 3)
            (32 4)
            (otherwise
             (error "FORMAT must be 24 or 32, got ~S." format)))))
    (let ((expected-length (* width height bytes-per-pixel)))
      (%check-pixel-vector pixels expected-length
                           "PIXELS length ~D does not match ~Dx~D at f=~D (expected ~D)."
                           width height format expected-length)))
  (let ((encoded (%base64-encode-octets pixels)))
    (with-output-to-string (out)
      (let ((length (length encoded)))
        (if (zerop length)
            (format out "~C_Ga=T,f=~D,s=~D,v=~D,m=0;~C\\"
                    +escape+ format width height +escape+)
            (loop for start from 0 below length by +kitty-chunk-size+
                  for index from 0
                  for end = (min length (+ start +kitty-chunk-size+))
                  for more = (if (< end length) 1 0)
                  do (if (zerop index)
                         (format out "~C_Ga=T,f=~D,s=~D,v=~D,m=~D;"
                                 +escape+ format width height more)
                         (format out "~C_Gm=~D;" +escape+ more))
                     (write-string encoded out :start start :end end)
                     (format out "~C\\" +escape+)))))))
