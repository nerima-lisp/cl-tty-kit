(in-package #:cl-tty-kit)

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
