(in-package #:cl-tty-kit)

(defun blend-colors (color-a color-b ratio)
  "Return the RGB triple (list R G B) that is RATIO of the way from COLOR-A to
COLOR-B. Each color is a three-element (R G B) list and RATIO is clamped to
[0, 1], so 0 yields COLOR-A and 1 yields COLOR-B. Channels are rounded to the
nearest integer."
  (let ((ratio (clamp ratio 0 1)))
    (mapcar (lambda (a b) (round (+ a (* (- b a) ratio))))
            color-a
            color-b)))

(defun rgb-to-hsl (r g b)
  "Convert the RGB triple R G B (each 0-255) to (VALUES HUE SATURATION LIGHTNESS),
with HUE in degrees [0, 360) and SATURATION/LIGHTNESS as percentages [0, 100]."
  (let* ((rf (/ r 255)) (gf (/ g 255)) (bf (/ b 255))
         (mx (max rf gf bf)) (mn (min rf gf bf))
         (lightness (/ (+ mx mn) 2)))
    (if (= mx mn)
        (values 0 0 (round (* lightness 100)))
        (let* ((d (- mx mn))
               (s (if (> lightness 1/2) (/ d (- 2 mx mn)) (/ d (+ mx mn))))
               (h (cond ((= mx rf) (mod (/ (- gf bf) d) 6))
                        ((= mx gf) (+ (/ (- bf rf) d) 2))
                        (t (+ (/ (- rf gf) d) 4)))))
          (values (mod (round (* h 60)) 360)
                  (round (* s 100))
                  (round (* lightness 100)))))))

(defmacro %hue-to-channel (p q hue)
  `(let* ((p ,p) (q ,q) (hue (mod ,hue 1)))
     (cond ((< hue 1/6) (+ p (* (- q p) 6 hue)))
           ((< hue 1/2) q)
           ((< hue 2/3) (+ p (* (- q p) (- 2/3 hue) 6)))
           (t p))))

(defun hsl-to-rgb (hue saturation lightness)
  "Convert HUE (degrees) SATURATION LIGHTNESS (percentages) to (VALUES R G B),
each an integer in [0, 255]. Inverse of RGB-TO-HSL."
  (let ((h (/ (mod hue 360) 360))
        (s (/ saturation 100))
        (l (/ lightness 100)))
    (if (zerop s)
        (let ((v (round (* l 255)))) (values v v v))
        (let* ((q (if (< l 1/2) (* l (+ 1 s)) (- (+ l s) (* l s))))
               (p (- (* 2 l) q)))
          (values (round (* 255 (%hue-to-channel p q (+ h 1/3))))
                  (round (* 255 (%hue-to-channel p q h)))
                  (round (* 255 (%hue-to-channel p q (- h 1/3)))))))))

(defun rgb-to-hsv (r g b)
  "Convert the RGB triple R G B (each 0-255) to (VALUES HUE SATURATION VALUE),
with HUE in degrees [0, 360) and SATURATION/VALUE as percentages [0, 100]."
  (let* ((rf (/ r 255)) (gf (/ g 255)) (bf (/ b 255))
         (mx (max rf gf bf)) (mn (min rf gf bf)) (d (- mx mn)))
    (values (mod (round (* 60 (cond ((zerop d) 0)
                                    ((= mx rf) (mod (/ (- gf bf) d) 6))
                                    ((= mx gf) (+ (/ (- bf rf) d) 2))
                                    (t (+ (/ (- rf gf) d) 4)))))
                 360)
            (round (* 100 (if (zerop mx) 0 (/ d mx))))
            (round (* 100 mx)))))

(defun hsv-to-rgb (hue saturation value)
  "Convert HUE (degrees) SATURATION VALUE (percentages) to (VALUES R G B), each
an integer in [0, 255]. Inverse of RGB-TO-HSV."
  (let* ((h (/ (mod hue 360) 60))
         (s (/ saturation 100))
         (v (/ value 100))
         (i (truncate h))
         (f (- h i))
         (p (* v (- 1 s)))
         (q (* v (- 1 (* s f))))
         (u (* v (- 1 (* s (- 1 f))))))
    (multiple-value-bind (rf gf bf)
        (ecase (mod i 6)
          (0 (values v u p))
          (1 (values q v p))
          (2 (values p v u))
          (3 (values p q v))
          (4 (values u p v))
          (5 (values v p q)))
      (values (round (* 255 rf)) (round (* 255 gf)) (round (* 255 bf))))))

(defun color-gradient (from to steps)
  "Return a list of STEPS RGB triples interpolating from FROM to TO inclusive.
FROM and TO are (R G B) lists; the first result is FROM and, when STEPS > 1, the
last is TO, with the rest evenly spaced (via BLEND-COLORS). STEPS must be a
positive integer. Handy for heatmaps and status ramps feeding STYLE-FG/STYLE-BG
through RGB-TO-256."
  (%assert (and (integerp steps) (plusp steps))
           "Gradient STEPS ~S must be a positive integer." steps)
  (if (= steps 1)
      (list (blend-colors from to 0))
      (loop for index from 0 below steps
            collect (blend-colors from to (/ index (1- steps))))))
