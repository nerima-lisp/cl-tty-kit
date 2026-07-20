(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Sixel image encoding
;;;
;;; FORMAT-SIXEL turns a raw RGB pixel buffer into a sixel DCS string a
;;; sixel-capable terminal renders as an image. Colors are quantized to the
;;; xterm 256 palette (via RGB-TO-256), the image is emitted in the sixel format
;;; of 6-pixel-tall bands, one pass per color, with run-length compression.
;;; --------------------------------------------------------------------------

(defparameter +sixel-band-height+ 6
  "The number of pixel rows encoded per sixel band (a sixel byte's six bits).")

(defun %sixel-percent (value)
  "Scale an 8-bit color channel VALUE to sixel's 0-100 percentage."
  (round (* value 100) 255))

(defun %sixel-pixel-color (pixels width x y)
  "Return the xterm-256 palette index of the pixel at (X, Y) in the flat
row-major RGB buffer PIXELS."
  (let ((index (* 3 (+ (* y width) x))))
    (rgb-to-256 (aref pixels index)
                (aref pixels (+ index 1))
                (aref pixels (+ index 2)))))

(defun %sixel-emit-run (out char count)
  "Write COUNT copies of sixel data CHAR to OUT, run-length compressed."
  (cond
    ((<= count 0))
    ((<= count 3)
     (dotimes (index count) (write-char char out)))
    (t
     (format out "!~D~C" count char))))

(defun %sixel-color-band (out pixels width height base-y color)
  "Emit one COLOR's pass over the band starting at row BASE-Y to OUT."
  (format out "#~D" color)
  (let ((run-char nil)
        (run-count 0))
    (flet ((flush ()
             (when run-char
               (%sixel-emit-run out run-char run-count))))
      (dotimes (x width)
        (let ((bits 0))
          (dotimes (row +sixel-band-height+)
            (let ((y (+ base-y row)))
              (when (and (< y height)
                         (= color (%sixel-pixel-color pixels width x y)))
                (setf bits (logior bits (ash 1 row))))))
          (let ((char (code-char (+ #x3F bits))))
            (if (eql char run-char)
                (incf run-count)
                (progn (flush)
                       (setf run-char char run-count 1))))))
      (flush))))

(defun %sixel-band-colors (pixels width height base-y)
  "Return the sorted list of palette colors appearing in the band at BASE-Y."
  (let ((seen '()))
    (dotimes (x width)
      (dotimes (row +sixel-band-height+)
        (let ((y (+ base-y row)))
          (when (< y height)
            (pushnew (%sixel-pixel-color pixels width x y) seen)))))
    (sort seen #'<)))

(defun format-sixel (pixels width height)
  "Return a sixel DCS string encoding the WIDTH by HEIGHT RGB image in PIXELS.
PIXELS is a flat row-major buffer of WIDTH*HEIGHT*3 octets (R, G, B per pixel);
colors are quantized to the xterm 256 palette. The result is bracketed by the
sixel introducer `ESC P q' and terminator `ESC \\', ready to write to a
sixel-capable terminal. A zero-area image yields an empty sixel."
  (unless (= (length pixels) (* width height 3))
    (error "PIXELS length ~D does not match ~Dx~D RGB (expected ~D)."
           (length pixels) width height (* width height 3)))
  (with-output-to-string (out)
    (format out "~CPq" +escape+)
    (when (and (plusp width) (plusp height))
      (let ((palette '()))
        (dotimes (y height)
          (dotimes (x width)
            (pushnew (%sixel-pixel-color pixels width x y) palette)))
        (dolist (color (sort palette #'<))
          (multiple-value-bind (r g b) (color-256-to-rgb color)
            (format out "#~D;2;~D;~D;~D"
                    color (%sixel-percent r) (%sixel-percent g) (%sixel-percent b))))
        (loop for base-y from 0 below height by +sixel-band-height+
              for first-band = t then nil
              do (unless first-band (write-char #\- out))
                 (loop for color in (%sixel-band-colors pixels width height base-y)
                       for first-color = t then nil
                       do (unless first-color (write-char #\$ out))
                          (%sixel-color-band out pixels width height base-y color)))))
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

(defun %chunk-string (string size)
  "Split STRING into a list of substrings of at most SIZE characters (one empty
string when STRING is empty)."
  (if (zerop (length string))
      (list "")
      (loop for start from 0 below (length string) by size
            collect (subseq string start (min (length string) (+ start size))))))

(defun ansi-kitty-image (pixels width height &key (format 24))
  "Return a kitty graphics protocol escape that transmits and displays the
WIDTH by HEIGHT image in PIXELS. PIXELS is a flat octet buffer; FORMAT is 24 for
packed RGB (WIDTH*HEIGHT*3 bytes) or 32 for RGBA (WIDTH*HEIGHT*4). The payload is
base64-encoded and split into APC chunks (`m=1' on all but the last). Rendered by
terminals that speak the kitty graphics protocol (kitty, WezTerm, Konsole) and
inert elsewhere -- the kitty-ecosystem counterpart to FORMAT-SIXEL, which serves
the sixel terminals."
  (let ((bytes-per-pixel (ecase format (24 3) (32 4))))
    (unless (= (length pixels) (* width height bytes-per-pixel))
      (error "PIXELS length ~D does not match ~Dx~D at f=~D (expected ~D)."
             (length pixels) width height format
             (* width height bytes-per-pixel))))
  (let* ((encoded (%base64-encode-octets pixels))
         (chunks (%chunk-string encoded +kitty-chunk-size+))
         (count (length chunks)))
    (with-output-to-string (out)
      (loop for chunk in chunks
            for index from 0
            for more = (if (= index (1- count)) 0 1)
            do (if (zerop index)
                   (format out "~C_Ga=T,f=~D,s=~D,v=~D,m=~D;~A~C\\"
                           +escape+ format width height more chunk +escape+)
                   (format out "~C_Gm=~D;~A~C\\"
                           +escape+ more chunk +escape+))))))
