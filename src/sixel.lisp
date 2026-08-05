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

(defmacro %sixel-percent (value)
  "Scale an 8-bit color channel VALUE to sixel's 0-100 percentage."
  `(let ((value ,value))
     (round (* value 100) 255)))

(defmacro %sixel-color-indices (pixels width height)
  "Return per-pixel xterm-256 palette indices and a sorted palette list.
Color quantization is performed once per pixel; band rendering reuses the
indices instead of requantizing every color pass."
  `(let ((pixels ,pixels) (width ,width) (height ,height))
     (let ((indices (make-array (* width height)
                                :element-type '(unsigned-byte 8)))
           (seen (make-array 256 :element-type 'bit :initial-element 0)))
       (dotimes (pixel-index (* width height))
         (let* ((rgb-index (* pixel-index 3))
                (color (%rgb-to-256-unchecked (aref pixels rgb-index)
                                              (aref pixels (+ rgb-index 1))
                                              (aref pixels (+ rgb-index 2)))))
           (setf (aref indices pixel-index) color
                 (aref seen color) 1)))
       (let ((palette '()))
         (dotimes (color 256)
           (when (= 1 (aref seen color))
             (push color palette)))
         (values indices (nreverse palette))))))

(defmacro %partition-bounds (k n total)
  "Return the [START, END) bounds of the Kth of N even, contiguous, gapless
partitions of the integer range [0, TOTAL). Every partition is non-empty when
N <= TOTAL, so splitting work this way across N executor workers never
dispatches an empty chunk."
  `(values (floor (* ,k ,total) ,n) (floor (* (1+ ,k) ,total) ,n)))

(defun %sixel-color-indices-parallel (executor chunk-count pixels width height)
  "Parallel equivalent of %SIXEL-COLOR-INDICES. PIXELS's WIDTH*HEIGHT pixel
range is split into CHUNK-COUNT contiguous partitions; each runs on one of
EXECUTOR's workers, quantizing into its own disjoint slice of one shared
INDICES array (safe: each worker writes only its own partition, and
single-byte stores to distinct array indices never tear) while tracking the
colors it saw in a private 256-bit set. The per-worker sets are then merged
with BIT-IOR and the palette built from the merged set in ascending color
order -- the same order %SIXEL-COLOR-INDICES itself produces, so which
worker first saw a given color cannot change the output."
  (let* ((total (* width height))
         (chunk-count (max 1 (min chunk-count total)))
         (indices (make-array total :element-type '(unsigned-byte 8))))
    (let ((seens (cl-concurrent-kit:executor-map
                  executor
                  (lambda (k)
                    (let ((seen (make-array 256 :element-type 'bit :initial-element 0)))
                      (multiple-value-bind (lo hi) (%partition-bounds k chunk-count total)
                        (loop for pixel-index from lo below hi
                              for rgb-index = (* pixel-index 3)
                              for color = (%rgb-to-256-unchecked
                                           (aref pixels rgb-index)
                                           (aref pixels (+ rgb-index 1))
                                           (aref pixels (+ rgb-index 2)))
                              do (setf (aref indices pixel-index) color
                                       (sbit seen color) 1)))
                      seen))
                  (loop for k below chunk-count collect k))))
      (let ((merged (make-array 256 :element-type 'bit :initial-element 0))
            (palette '()))
        (dolist (seen seens) (bit-ior merged seen merged))
        (dotimes (color 256)
          (when (= 1 (sbit merged color))
            (push color palette)))
        (values indices (nreverse palette))))))

(defmacro %sixel-emit-run (out char count)
  "Write COUNT copies of sixel data CHAR to OUT, run-length compressed."
  `(let ((out ,out) (char ,char) (count ,count))
     (cond
       ((<= count 0))
       ((<= count 3)
        (dotimes (index count) (write-char char out)))
       (t
        (format out "!~D~C" count char)))))

(progn
  (defstruct (%sixel-band-state
              (:constructor %make-sixel-band-state))
    (next-x 0 :type (integer 0))
    run-char
    (run-count 0 :type (integer 0))
    (runs (make-array 16
                      :element-type (quote (unsigned-byte 32))
                      :adjustable t
                      :fill-pointer 0)
          :type (vector (unsigned-byte 32))))

  (defstruct (%sixel-band-workspace
              (:constructor %make-sixel-band-workspace))
    (states (make-array 256 :initial-element nil))
    (seen (make-array 256 :element-type (quote bit) :initial-element 0))
    colors
    (column-bits (make-array 256
                             :element-type (quote (unsigned-byte 8))
                             :initial-element 0))
    (column-seen (make-array 256 :element-type (quote bit) :initial-element 0))
    (column-colors (make-array 256
                               :element-type (quote (unsigned-byte 8)))))

  (defun %sixel-band-workspace-reset (workspace)
    (dolist (color (%sixel-band-workspace-colors workspace))
      (let ((state (aref (%sixel-band-workspace-states workspace) color)))
        (setf (sbit (%sixel-band-workspace-seen workspace) color) 0
              (%sixel-band-state-next-x state) 0
              (%sixel-band-state-run-char state) nil
              (%sixel-band-state-run-count state) 0
              (fill-pointer (%sixel-band-state-runs state)) 0)))
    (setf (%sixel-band-workspace-colors workspace) nil)
    workspace))

(defmacro %sixel-band-state-flush (state)
  `(let ((state ,state))
     (when (%sixel-band-state-run-char state)
       (let ((runs (%sixel-band-state-runs state)))
         (vector-push-extend
          (logior (char-code (%sixel-band-state-run-char state))
                  (ash (%sixel-band-state-run-count state) 7))
          runs
          (let ((capacity (length runs)))
            (if (< capacity 16) 16 capacity))))
       (setf (%sixel-band-state-run-char state) nil
             (%sixel-band-state-run-count state) 0))))

(defmacro %sixel-band-state-add-run (state char count)
  `(let ((state ,state) (char ,char) (count ,count))
     (cond
       ((<= count 0))
       ((eql char (%sixel-band-state-run-char state))
        (incf (%sixel-band-state-run-count state) count))
       (t
        (%sixel-band-state-flush state)
        (setf (%sixel-band-state-run-char state) char
              (%sixel-band-state-run-count state) count)))))

(defmacro %sixel-band-state-add-column (state x char)
  `(let ((state ,state) (x ,x) (char ,char))
     (let ((gap (- x (%sixel-band-state-next-x state))))
       (%sixel-band-state-add-run state #\? gap)
       (%sixel-band-state-add-run state char 1)
       (setf (%sixel-band-state-next-x state) (1+ x)))))

(defmacro %sixel-band-state-finish (state width)
  `(let ((state ,state) (width ,width))
     (%sixel-band-state-add-run state #\?
                                (- width (%sixel-band-state-next-x state)))
     (%sixel-band-state-flush state)
     (%sixel-band-state-runs state)))

(defmacro %sixel-emit-runs (out runs)
  `(let ((out ,out) (runs ,runs))
     (dotimes (index (fill-pointer runs))
       (let ((run (aref runs index)))
         (%sixel-emit-run out
                          (code-char (logand run #x7F))
                          (ash run -7))))))

(defmacro %sixel-band-runs (workspace color-indices width height base-y)
  "Return sorted colors and RLE state for the band starting at BASE-Y.
The band is scanned once; blank columns are inserted lazily when a color appears
again, which avoids rescanning WIDTH for every palette entry."
  `(let ((workspace ,workspace) (color-indices ,color-indices) (width ,width)
         (height ,height) (base-y ,base-y))
     (%sixel-band-workspace-reset workspace)
     (let ((states (%sixel-band-workspace-states workspace))
           (seen (%sixel-band-workspace-seen workspace))
           (colors nil)
           (column-bits (%sixel-band-workspace-column-bits workspace))
           (column-seen (%sixel-band-workspace-column-seen workspace))
           (column-colors (%sixel-band-workspace-column-colors workspace))
           (band-row-count
             (let ((remaining (- height base-y)))
               (if (minusp remaining)
                   0
                   (if (> remaining +sixel-band-height+)
                       +sixel-band-height+
                       remaining))))
           (column-index (* base-y width)))
       (dotimes (x width)
         (let ((column-color-count 0))
           (loop repeat band-row-count
                 for pixel-index = column-index then (+ pixel-index width)
                 for bit = 1 then (ash bit 1)
                 for color = (aref color-indices pixel-index)
                 do
                    (when (zerop (sbit seen color))
                      (setf (sbit seen color) 1)
                      (unless (aref states color)
                        (setf (aref states color) (%make-sixel-band-state)))
                      (push color colors))
                    (when (zerop (sbit column-seen color))
                      (setf (sbit column-seen color) 1
                            (aref column-colors column-color-count) color)
                      (incf column-color-count))
                    (setf (aref column-bits color)
                          (logior (aref column-bits color) bit)))
           (dotimes (index column-color-count)
             (let ((color (aref column-colors index)))
               (%sixel-band-state-add-column
                (aref states color) x
                (code-char (+ #x3F (aref column-bits color))))
               (setf (aref column-bits color) 0
                     (sbit column-seen color) 0))))
         (incf column-index))
       (let ((sorted-colors (sort colors (function <))))
         (setf (%sixel-band-workspace-colors workspace) sorted-colors)
         (values sorted-colors states)))))

(defmacro %check-image-dimensions (width height)
  `(let ((width ,width) (height ,height))
     (unless (and (integerp width) (not (minusp width))
                  (integerp height) (not (minusp height)))
       (error "Image dimensions must be non-negative integers, got ~Sx~S."
              width height))
     (let ((pixel-count (* width height)))
       (when (> pixel-count +max-terminal-image-pixels+)
         (error "Image dimensions ~Dx~D exceed the ~D pixel limit."
                 width height +max-terminal-image-pixels+)))
     (values)))

(defmacro %check-pixel-vector (pixels expected-length format-control &rest format-arguments)
  `(let ((pixels ,pixels) (expected-length ,expected-length)
         (format-control ,format-control) (format-arguments (list ,@format-arguments)))
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
     (values)))

(defparameter +sixel-parallel-pixel-threshold+ (* 64 64)
  "Minimum WIDTH*HEIGHT below which FORMAT-SIXEL ignores :EXECUTOR and encodes
serially. Below this size, per-band encoding cost falls under
CL-CONCURRENT-KIT's submit+await dispatch floor (measured ~5us per task on the
development host), so splitting bands across workers would net-lose to
dispatch overhead rather than win.")

(defmacro %sixel-band-starts (height)
  "Return the list of BASE-Y offsets FORMAT-SIXEL's band loop visits for
HEIGHT, in ascending order."
  `(loop for base-y from 0 below ,height by +sixel-band-height+ collect base-y))

(defmacro %sixel-band-string (workspace color-indices width height base-y)
  "Return BASE-Y's band as a string (colors separated by $), using WORKSPACE
as scratch space. WORKSPACE is reset on entry, so it must not be shared with
a concurrently-running band -- each parallel worker gets its own."
  `(let ((workspace ,workspace) (color-indices ,color-indices)
         (width ,width) (height ,height) (base-y ,base-y))
     (with-output-to-string (out)
       (multiple-value-bind (band-colors states)
           (%sixel-band-runs workspace color-indices width height base-y)
         (loop for color in band-colors
               for first-color = t then nil
               do (unless first-color (write-char #\$ out))
                  (format out "#~D" color)
                  (%sixel-emit-runs out (%sixel-band-state-finish (aref states color) width)))))))

(defmacro %sixel-band-strings-serial (color-indices width height)
  "Return every band's string, in band order, computed on the calling thread
with one shared, reused workspace."
  `(let ((color-indices ,color-indices) (width ,width) (height ,height))
     (let ((workspace (%make-sixel-band-workspace)))
       (loop for base-y in (%sixel-band-starts height)
             collect (%sixel-band-string workspace color-indices width height base-y)))))

(defun %sixel-band-strings-parallel (executor chunk-count color-indices width height)
  "Return every band's string, in band order, computed across EXECUTOR's
workers. Bands are split into up to CHUNK-COUNT contiguous groups; each group
runs on one worker with its own private workspace, so no mutable state is
shared across threads. COLOR-INDICES is read-only after %SIXEL-COLOR-INDICES
returns it and is safe to share across workers unmodified."
  (let* ((band-starts (%sixel-band-starts height))
         (band-count (length band-starts))
         (chunk-count (max 1 (min chunk-count band-count)))
         (chunk-size (ceiling band-count chunk-count))
         (chunks (loop for start from 0 below band-count by chunk-size
                       collect (subseq band-starts start (min band-count (+ start chunk-size))))))
    (apply (function append)
           (cl-concurrent-kit:executor-map
            executor
            (lambda (chunk)
              (let ((workspace (%make-sixel-band-workspace)))
                (mapcar (lambda (base-y)
                          (%sixel-band-string workspace color-indices width height base-y))
                        chunk)))
            chunks))))

(defun format-sixel (pixels width height &key executor (chunk-count 8))
  "Return a sixel DCS string encoding the WIDTH by HEIGHT RGB image in PIXELS.
PIXELS is a flat row-major buffer of WIDTH*HEIGHT*3 octets (R, G, B per pixel);
colors are quantized to the xterm 256 palette. The result is bracketed by the
sixel introducer `ESC P q` and terminator `ESC \\`, ready to write to a
sixel-capable terminal. A zero-area image yields an empty sixel.

EXECUTOR, when supplied, is a CL-CONCURRENT-KIT:EXECUTOR the caller creates
and owns (e.g. via CL-CONCURRENT-KIT:WITH-EXECUTOR) -- both color quantization
and band encoding then run across its workers instead of the calling thread,
provided WIDTH*HEIGHT is at least +SIXEL-PARALLEL-PIXEL-THRESHOLD+; below
that, or with no EXECUTOR, encoding is fully serial and CHUNK-COUNT is
ignored. CHUNK-COUNT bounds how many contiguous chunks each phase dispatches
to EXECUTOR -- keep it near EXECUTOR's own worker count for best throughput;
oversubscribing past that count wins nothing further. Output is byte-identical
either way."
  (%check-image-dimensions width height)
  (let ((expected-length (* width height 3)))
    (%check-pixel-vector pixels expected-length
                         "PIXELS length ~D does not match ~Dx~D RGB (expected ~D)."
                         width height expected-length))
  (with-output-to-string (out)
    (format out "~CPq" +escape+)
    (when (and (plusp width) (plusp height))
      (let ((parallel-p (and executor (>= (* width height) +sixel-parallel-pixel-threshold+))))
        (multiple-value-bind (color-indices palette)
            (if parallel-p
                (%sixel-color-indices-parallel executor chunk-count pixels width height)
                (%sixel-color-indices pixels width height))
          (dolist (color palette)
            (multiple-value-bind (r g b) (color-256-to-rgb color)
              (format out "#~D;2;~D;~D;~D"
                      color (%sixel-percent r) (%sixel-percent g) (%sixel-percent b))))
          (let ((band-strings
                  (if parallel-p
                      (%sixel-band-strings-parallel executor chunk-count color-indices width height)
                      (%sixel-band-strings-serial color-indices width height))))
            (loop for band-string in band-strings
                  for first-band = t then nil
                  do (unless first-band (write-char #\- out))
                     (write-string band-string out))))))
    (format out "~C\\" +escape+)))
