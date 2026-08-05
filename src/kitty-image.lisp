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

(defmacro %kitty-chunk-string (pixels format width height bytes-per-chunk length chunk-index start)
  "Return one kitty graphics APC chunk's full escape-framed string for the
byte range of PIXELS starting at START. Depends only on its own START/CHUNK-INDEX
(the M= more-flag is a pure function of END versus LENGTH, and the header
differs only for CHUNK-INDEX 0), so distinct chunks have no dependency on one
another and may be computed in any order or concurrently -- only their final
concatenation must stay in ascending START order."
  `(let ((pixels ,pixels) (format ,format) (width ,width) (height ,height)
         (bytes-per-chunk ,bytes-per-chunk) (length ,length)
         (chunk-index ,chunk-index) (start ,start))
     (let* ((end (if (> (+ start bytes-per-chunk) length) length (+ start bytes-per-chunk)))
            (more (if (< end length) 1 0)))
       (with-output-to-string (out)
         (if (zerop chunk-index)
             (format out "~C_Ga=T,f=~D,s=~D,v=~D,m=~D;" +escape+ format width height more)
             (format out "~C_Gm=~D;" +escape+ more))
         (%write-base64-octets pixels out :start start :end end)
         (write-char +escape+ out)
         (write-char #\\ out)))))

(defmacro %kitty-chunk-starts (length bytes-per-chunk)
  "Return the list of byte offsets ANSI-KITTY-IMAGE's APC chunk loop visits
for a payload of LENGTH octets, in ascending order."
  `(loop for start from 0 below ,length by ,bytes-per-chunk collect start))

(defmacro %kitty-chunk-strings-serial (pixels format width height bytes-per-chunk length)
  "Return every APC chunk's string, in chunk order, computed on the calling
thread."
  `(let ((pixels ,pixels) (format ,format) (width ,width) (height ,height)
         (bytes-per-chunk ,bytes-per-chunk) (length ,length))
     (loop for start in (%kitty-chunk-starts length bytes-per-chunk)
           for chunk-index from 0
           collect (%kitty-chunk-string
                    pixels format width height bytes-per-chunk length chunk-index start))))

(defun %kitty-chunk-strings-parallel (executor task-count pixels format width height bytes-per-chunk length)
  "Return every APC chunk's string, in chunk order, computed across EXECUTOR's
workers. Chunk indices are split into up to TASK-COUNT contiguous groups
(never empty, via %PARTITION-BOUNDS); each group's chunks are encoded on one
worker in a plain loop, reading only its own disjoint slice of PIXELS."
  (let* ((chunk-starts (coerce (%kitty-chunk-starts length bytes-per-chunk) 'vector))
         (chunk-count (length chunk-starts))
         (task-count (max 1 (min task-count chunk-count))))
    (apply (function append)
           (cl-concurrent-kit:executor-map
            executor
            (lambda (task)
              (multiple-value-bind (lo hi) (%partition-bounds task task-count chunk-count)
                (loop for chunk-index from lo below hi
                      collect (%kitty-chunk-string
                               pixels format width height bytes-per-chunk length
                               chunk-index (aref chunk-starts chunk-index)))))
            (loop for task below task-count collect task)))))

(defun ansi-kitty-image (pixels width height &key (format 24) executor (chunk-count 8))
  "Return a kitty graphics protocol escape that transmits and displays the
WIDTH by HEIGHT image in PIXELS. PIXELS is a flat octet buffer; FORMAT is 24 for
packed RGB (WIDTH*HEIGHT*3 bytes) or 32 for RGBA (WIDTH*HEIGHT*4). The payload is
base64-encoded and split into APC chunks with m=1 on all but the last.

EXECUTOR, when supplied, is a CL-CONCURRENT-KIT:EXECUTOR the caller creates
and owns -- APC chunk encoding then runs across its workers instead of the
calling thread, provided WIDTH*HEIGHT is at least
+SIXEL-PARALLEL-PIXEL-THRESHOLD+ (the same gate FORMAT-SIXEL uses); below
that, or with no EXECUTOR, encoding is serial and CHUNK-COUNT is ignored.
Output is byte-identical either way."
  (%check-image-dimensions width height)
  (let ((bytes-per-pixel
        (case format
          (24 3)
          (32 4)
          (otherwise (error "FORMAT must be 24 or 32, got ~S." format)))))
    (let ((expected-length (* width height bytes-per-pixel)))
      (%check-pixel-vector
        pixels
        expected-length
        "PIXELS length ~D does not match ~Dx~D at f=~D (expected ~D)."
        width
        height
        format
        expected-length)))
  (with-output-to-string (out)
    (let ((length (length pixels))
          (bytes-per-chunk (* 3 (ash +kitty-chunk-size+ -2))))
      (if (zerop length)
          (progn
            (format out "~C_Ga=T,f=~D,s=~D,v=~D,m=0;" +escape+ format width height)
            (write-char +escape+ out)
            (write-char #\\ out))
          (dolist (chunk-string
                   (if (and executor (>= (* width height) +sixel-parallel-pixel-threshold+))
                       (%kitty-chunk-strings-parallel
                        executor chunk-count pixels format width height bytes-per-chunk length)
                       (%kitty-chunk-strings-serial pixels format width height bytes-per-chunk length)))
            (write-string chunk-string out))))))
