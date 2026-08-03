(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Color model conversions
;;;
;;; Helpers for moving between hex/RGB triples and the xterm 256-color palette
;;; that STYLE-FG/STYLE-BG index. All are pure functions returning fresh values.
;;; --------------------------------------------------------------------------

(defparameter +xterm-system-colors+
  #((0 0 0) (128 0 0) (0 128 0) (128 128 0)
    (0 0 128) (128 0 128) (0 128 128) (192 192 192)
    (128 128 128) (255 0 0) (0 255 0) (255 255 0)
    (0 0 255) (255 0 255) (0 255 255) (255 255 255))
  "RGB triples for the sixteen system palette entries (indices 0-15).")

(defparameter +xterm-cube-levels+ #(0 95 135 175 215 255)
  "The six per-channel intensity levels of the 6x6x6 color cube (indices
16-231).")
(defparameter +nearest-cube-level-indices+
  (let ((indices (make-array 256 :element-type (quote (unsigned-byte 8)))))
    (dotimes (value 256 indices)
      (let ((best 0)
            (best-distance nil))
        (dotimes (index (length +xterm-cube-levels+))
          (let ((distance (abs (- value (aref +xterm-cube-levels+ index)))))
            (when (or (null best-distance) (< distance best-distance))
              (setf best-distance distance
                    best index))))
        (setf (aref indices value) best)))))

(defmacro %hex-nibble (char)
  `(let* ((char ,char)
          (digit (digit-char-p char 16)))
     (%assert digit "Invalid hex digit ~S in color string." char)
     digit))

(defun parse-hex-color (string)
  "Parse a hex color STRING into (VALUES R G B), each an integer in [0, 255].
Accepts \"#rrggbb\"/\"rrggbb\" and the short \"#rgb\"/\"rgb\" form (each nibble
doubled). Any other length or a non-hex digit signals an error."
  (let* ((body (if (and (plusp (length string)) (char= #\# (char string 0)))
                   (subseq string 1)
                   string)))
    (flet ((byte-at (index) (+ (* 16 (%hex-nibble (char body index)))
                               (%hex-nibble (char body (1+ index)))))
           (nibble-at (index) (let ((n (%hex-nibble (char body index))))
                                (+ (* 16 n) n))))
      (case (length body)
        (6 (values (byte-at 0) (byte-at 2) (byte-at 4)))
        (3 (values (nibble-at 0) (nibble-at 1) (nibble-at 2)))
        (otherwise
         (error "Hex color ~S must have 3 or 6 hex digits." string))))))

(defun color-256-to-rgb (index)
  "Return (VALUES R G B) for the xterm 256-color palette INDEX (0-255).
Indices 0-15 are the system colors, 16-231 the 6x6x6 cube, and 232-255 the
grayscale ramp. An out-of-range INDEX signals an error."
  (%assert (typep index '(integer 0 255)) "Color index ~S must be an integer in [0, 255]." index)
  (cond
    ((< index 16)
     (let ((rgb (aref +xterm-system-colors+ index)))
       (values (first rgb) (second rgb) (third rgb))))
    ((< index 232)
     (let ((n (- index 16)))
       (values (aref +xterm-cube-levels+ (truncate n 36))
               (aref +xterm-cube-levels+ (mod (truncate n 6) 6))
               (aref +xterm-cube-levels+ (mod n 6)))))
    (t
     (let ((gray (+ 8 (* 10 (- index 232)))))
       (values gray gray gray)))))

(defmacro %nearest-cube-level-index (value)
  `(aref +nearest-cube-level-indices+ ,value))

(defmacro %rgb-distance (r1 g1 b1 r2 g2 b2)
  `(let* ((r-delta (- ,r1 ,r2))
          (g-delta (- ,g1 ,g2))
          (b-delta (- ,b1 ,b2)))
     (+ (* r-delta r-delta)
        (* g-delta g-delta)
        (* b-delta b-delta))))

(defmacro %assert-rgb-channels (r g b)
  `(let ((r ,r) (g ,g) (b ,b))
     (%assert (typep r '(integer 0 255))
              "RGB channel ~S must be an integer in [0, 255]." r)
     (%assert (typep g '(integer 0 255))
              "RGB channel ~S must be an integer in [0, 255]." g)
     (%assert (typep b '(integer 0 255))
              "RGB channel ~S must be an integer in [0, 255]." b)))

(defun %rgb-to-256-unchecked (r g b)
  (let* ((red-index (%nearest-cube-level-index r))
         (green-index (%nearest-cube-level-index g))
         (blue-index (%nearest-cube-level-index b))
         (cube-index (+ 16 (* 36 red-index) (* 6 green-index) blue-index))
         (gray-step (clamp (round (- (+ r g b) 24) 30) 0 23))
         (gray-value (+ 8 (* 10 gray-step)))
         (gray-index (+ 232 gray-step))
         (cube-red (aref +xterm-cube-levels+ red-index))
         (cube-green (aref +xterm-cube-levels+ green-index))
         (cube-blue (aref +xterm-cube-levels+ blue-index)))
    (if (<= (%rgb-distance r g b cube-red cube-green cube-blue)
            (%rgb-distance r g b gray-value gray-value gray-value))
        cube-index
        gray-index)))
(defun rgb-to-256 (r g b)
  "Return the xterm 256-color palette index closest to the RGB triple R G B.
Both the 6x6x6 cube and the grayscale ramp are considered and the nearer match
(by squared RGB distance) wins, so near-gray inputs map to the smoother gray
ramp. Each channel must be an integer in [0, 255]."
  (%assert-rgb-channels r g b)
  (%rgb-to-256-unchecked r g b))

(defun rgb-to-ansi16 (r g b)
  "Return the 0-15 system-palette index closest to the RGB triple R G B.
Distance is squared RGB against the sixteen standard colors, for terminals that
support only the base palette. Each channel must be an integer in [0, 255]."
  (%assert-rgb-channels r g b)
  (let ((best 0)
        (best-distance nil))
    (dotimes (index 16 best)
      (let ((rgb (aref +xterm-system-colors+ index)))
        (let ((distance (%rgb-distance r g b (first rgb) (second rgb) (third rgb))))
          (when (or (null best-distance) (< distance best-distance))
            (setf best-distance distance best index)))))))

(defun color-luminance (r g b)
  "Return the perceived luminance of the RGB triple R G B as an integer in
[0, 255], using the Rec. 601 weighting (0.299 R + 0.587 G + 0.114 B). Useful for
choosing a readable foreground (dark text over a light background and vice
versa). Each channel must be an integer in [0, 255]."
  (%assert-rgb-channels r g b)
  (round (+ (* 299/1000 r) (* 587/1000 g) (* 114/1000 b))))

(defun contrast-color (r g b)
  "Return (0 0 0) or (255 255 255) -- black or white -- whichever is more readable
as a foreground over the background RGB triple R G B, decided by COLOR-LUMINANCE."
  (if (>= (color-luminance r g b) 128)
      (list 0 0 0)
      (list 255 255 255)))

(defmacro %parse-rgb-functional (string)
  `(let ((string ,string))
     (labels ((malformed ()
                (error "Malformed rgb() color ~S." string))
              (parse-component (component)
                (unless (and (plusp (length component))
                             (<= (length component) 3)
                             (every #'digit-char-p component))
                  (malformed))
                (let ((value (parse-integer component)))
                  (unless (typep value '(integer 0 255))
                    (malformed))
                  value)))
       (let ((open (position #\( string))
             (close (position #\) string :from-end t)))
         (unless (and open
                      close
                      (< open close)
                      (loop for index from (1+ close) below (length string)
                            always (char= (char string index) #\Space)))
           (malformed))
         (let* ((body (subseq string (1+ open) close))
                ;; Splitting on comma after mapping every space to a comma
                ;; handles "r, g, b" and "r g b" the same way, and dropping
                ;; empty pieces absorbs the extra delimiters that produces
                ;; (e.g. the run of two commas at each ", ").
                (parts (remove-if (lambda (part) (zerop (length part)))
                                   (%split-on-char (substitute #\, #\Space body) #\,))))
           (unless (= 3 (length parts))
             (malformed))
           (values-list (mapcar #'parse-component parts)))))))

(defun parse-color (spec)
  "Parse SPEC into (VALUES R G B), each an integer in [0, 255].
SPEC is a hex string (\"#rrggbb\" or \"#rgb\"), a functional \"rgb(r,g,b)\"
string, or a color name -- a keyword or string accepted by NAMED-COLOR (resolved
through the xterm palette). This is the one-stop parser mirroring the color
inputs styling layers accept."
  (etypecase spec
    (keyword (color-256-to-rgb (named-color spec)))
    (string
     (cond
       ((and (plusp (length spec)) (char= #\# (char spec 0)))
        (parse-hex-color spec))
       ((and (>= (length spec) 4) (string-equal "rgb(" spec :end2 4))
        (%parse-rgb-functional spec))
       (t
        (multiple-value-bind (symbol status)
            (find-symbol (string-upcase spec) :keyword)
          (%assert (and symbol status) "Unknown color name ~S." spec)
          (color-256-to-rgb (named-color symbol))))))))
