(unless (sb-ext:posix-getenv "CL_TTY_KIT_BENCHMARK_SKIP_BOOTSTRAP")
  (require :asdf)
  (load
    (merge-pathnames
      #P"bootstrap.lisp"
      (make-pathname :name nil :type nil :defaults *load-truename*)))
  (format t "~&[LOAD] cl-tty-kit~%")
  (finish-output)
  (let ((loader (find-symbol "LOAD-CORE-SYSTEM" "CL-TTY-KIT/BOOTSTRAP")))
    (unless loader
      (error "CL-TTY-KIT bootstrap did not export LOAD-CORE-SYSTEM."))
    (funcall (symbol-function loader)))
  (format t "~&[LOAD] complete~%")
  (finish-output))

(in-package #:cl-tty-kit)

(defparameter *benchmark-warmup-iterations* (let ((value (uiop:getenv "CL_TTY_KIT_BENCHMARK_WARMUP")))
    (if value (multiple-value-bind (integer position) (parse-integer value :junk-allowed t)
        (unless (and integer (= position (length value)) (not (minusp integer)))
          (error
            "CL_TTY_KIT_BENCHMARK_WARMUP must be a non-negative integer, got ~S."
            value))
        integer)
      1000)))

(progn
  (defparameter *benchmark-default-iterations* 100000)
  (defun benchmark-iterations ()
    (let ((arguments (uiop:command-line-arguments)))
      (if (null arguments)
          *benchmark-default-iterations*
          (let ((argument (first arguments)))
            (multiple-value-bind (value position)
                (parse-integer argument :junk-allowed t)
              (unless (and value (= position (length argument)))
                (error
                  "Usage: benchmark-hotpaths.lisp [POSITIVE-ITERATIONS]; got ~S."
                  argument))
              value))))))

(defvar *benchmark-result-sink* nil)

(defun run-benchmark-case (name operation preflight post iterations)
  (funcall preflight)
  (loop repeat *benchmark-warmup-iterations*
        do (setf *benchmark-result-sink* (funcall operation)))
  (setf *benchmark-result-sink* nil)
  (sb-ext:gc :full t)
  (let ((start-time (get-internal-real-time))
        (start-bytes (sb-ext:get-bytes-consed)))
    (loop repeat iterations
          do (setf *benchmark-result-sink* (funcall operation)))
    (let* ((elapsed-ticks (max 1 (- (get-internal-real-time) start-time)))
           (elapsed-seconds (/ elapsed-ticks internal-time-units-per-second))
           (bytes-consed (- (sb-ext:get-bytes-consed) start-bytes)))
      (funcall post)
      (format t "~&~A~%" name)
      (format t "iterations: ~D~%" iterations)
      (format t "elapsed: ~,6F s~%" (float elapsed-seconds 1.0d0))
      (format
        t
        "time: ~,1F ns/op~%"
        (/ (* elapsed-seconds 1000000000.0d0) iterations))
      (format t "throughput: ~,1F ops/s~%" (/ iterations elapsed-seconds))
      (format t "bytes-consed: ~,2F bytes/op~%" (/ bytes-consed iterations)))))

(defun make-styled-threshold-render-case ()
  (let* ((width 80)
         (height 24)
         (previous (make-screen width height))
         (current (make-screen width height))
         (plan (%make-screen-diff-plan current))
         (stream (make-broadcast-stream))
         (style (make-style :bold (style-fg (named-color :bright-cyan)))))
    (screen-fill previous #\A)
    (screen-fill current #\A)
    (loop for y below height
          do (screen-write-string
        current
        0
        y
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        :style
        style))
    (let ((diff-length (progn (%plan-diff-length current previous plan) (%diff-plan-rendered-length current plan)))
          (minimum-length (%minimum-screen-render-length current))
          (full-length (%screen-render-length current)))
      (values
        (lambda ()
          (%render-diff-output current previous stream plan))
        (lambda ()
          (unless (and (>= diff-length minimum-length) (< diff-length full-length))
            (error
              "Styled render case missed threshold: minimum=~D diff=~D full=~D."
              minimum-length
              diff-length
              full-length)))
        (lambda ()
          (multiple-value-bind (result wrote-output-p full-repaint-p) (%render-diff-output current previous stream plan)
            (declare (ignore result))
            (unless (and wrote-output-p (not full-repaint-p))
              (error
                "Styled render case selected the wrong strategy: output=~S full=~S."
                wrote-output-p
                full-repaint-p))))))))

(defun make-screen-write-case (string style tail-x tail-char &optional spacer-x)
  (let* ((screen (make-screen 80 1))
         (initial-generation (screen-generation screen))
         (expected-style (%normalize-cell-style style)))
    (values
      (lambda ()
        (screen-write-string screen 0 0 string :style style))
      (lambda ()
        (unless (and
            (= (screen-generation screen) initial-generation)
            (char= (cell-char (screen-cell screen tail-x 0)) #\Space)
            (null (cell-style (screen-cell screen tail-x 0))))
          (error "SCREEN-WRITE-STRING preflight initial-state guard failed.")))
      (lambda ()
        (let ((tail (screen-cell screen tail-x 0)))
          (unless (and
              (eq *benchmark-result-sink* screen)
              (> (screen-generation screen) initial-generation)
              (char= (cell-char tail) tail-char)
              (equal (cell-style tail) expected-style))
            (error "SCREEN-WRITE-STRING post guard failed at tail column ~D." tail-x)))
        (when spacer-x
          (let ((spacer (screen-cell screen spacer-x 0)))
            (unless (and
                (char= (cell-char spacer) #\Space)
                (equal (cell-style spacer) expected-style))
              (error "SCREEN-WRITE-STRING wide spacer guard failed at column ~D." spacer-x))))))))

(defun make-pending-escape-case ()
  (let* ((decoder (make-input-decoder))
         (empty "")
         (events (decode-input-chunk decoder (string #\Esc)))
         (pending (input-decoder-pending-string decoder)))
    (values
      (lambda ()
        (decode-input-chunk decoder empty))
      (lambda ()
        (unless (and (null events) (= (length pending) 1))
          (error "Failed to seed the pending ESC benchmark.")))
      (lambda ()
        (unless (and
            (null *benchmark-result-sink*)
            (eq pending (input-decoder-pending-string decoder))
            (zerop (length (input-decoder-pending-octets decoder))))
          (error "Pending ESC was changed by a non-EOF empty feed."))))))

(defun make-pending-utf8-case ()
  (let* ((decoder (make-input-decoder))
         (empty (make-array 0 :element-type (quote (unsigned-byte 8))))
         (events (decode-input-chunk decoder #(227 129)))
         (pending (input-decoder-pending-octets decoder)))
    (values
      (lambda ()
        (decode-input-chunk decoder empty))
      (lambda ()
        (unless (and (null events) (= (length pending) 2))
          (error "Failed to seed the pending UTF-8 benchmark.")))
      (lambda ()
        (unless (and
            (null *benchmark-result-sink*)
            (eq pending (input-decoder-pending-octets decoder))
            (zerop (length (input-decoder-pending-string decoder))))
          (error "Pending UTF-8 was changed by a non-EOF empty feed."))))))

(progn
  (defun make-rgb-to-256-case ()
    (let* ((samples
          #(#(0 0 0 16)
            #(255 0 0 196)
            #(0 255 0 46)
            #(0 0 255 21)
            #(128 128 128 244)
            #(255 255 255 231)
            #(95 135 175 67)
            #(238 238 238 255)))
           (sample-count (length samples))
           (index 0))
      (labels ((guard ()
                 (loop for sample across samples
                  for result = (rgb-to-256 (aref sample 0) (aref sample 1) (aref sample 2))
                  unless (= result (aref sample 3))
                    do (error
                "RGB-TO-256 correctness guard failed for ~S: expected ~D, got ~D."
                sample
                (aref sample 3)
                result))
                 (unless (< -1 index sample-count)
              (error "RGB-TO-256 benchmark index escaped its sample set: ~D." index))))
        (values
          (lambda ()
            (let* ((sample (aref samples index))
                   (result (rgb-to-256 (aref sample 0) (aref sample 1) (aref sample 2))))
              (setf index (mod (1+ index) sample-count))
              result))
          (function guard)
          (function guard)))))
  (defparameter *benchmark-statistical-trials* (let ((value (uiop:getenv "CL_TTY_KIT_BENCHMARK_TRIALS")))
      (if value (multiple-value-bind (integer position) (parse-integer value :junk-allowed t)
          (unless (and integer (= position (length value)) (plusp integer))
            (error "CL_TTY_KIT_BENCHMARK_TRIALS must be a positive integer, got ~S." value))
          integer)
        7)))
  (defun benchmark-median (values)
    (let* ((sorted (sort (copy-seq values) #'<))
           (length (length sorted))
           (middle (floor length 2)))
      (if (oddp length) (aref sorted middle)
        (/ (+ (aref sorted (1- middle)) (aref sorted middle)) 2))))
  (defun benchmark-median-absolute-deviation (values median)
    (benchmark-median
      (map
        'vector
        (lambda (value)
          (abs (- value median)))
        values)))
  (defun run-statistical-benchmark-case (name operation preflight post iterations)
    (funcall preflight)
    (loop repeat (min *benchmark-warmup-iterations* iterations)
          do (setf *benchmark-result-sink* (funcall operation)))
    (let ((times (make-array *benchmark-statistical-trials*))
          (allocations (make-array *benchmark-statistical-trials*)))
      (dotimes (trial *benchmark-statistical-trials*)
        (setf *benchmark-result-sink* nil)
        (sb-ext:gc :full t)
        (let ((start-time (get-internal-real-time))
              (start-bytes (sb-ext:get-bytes-consed)))
          (loop repeat iterations
                do (setf *benchmark-result-sink* (funcall operation)))
          (let ((elapsed-ticks (max 1 (- (get-internal-real-time) start-time))))
            (setf (aref times trial) (/ (* elapsed-ticks 1000000000.0d0) internal-time-units-per-second iterations)
                  (aref allocations trial) (/ (- (sb-ext:get-bytes-consed) start-bytes) iterations)))))
      (funcall post)
      (let ((median-time (benchmark-median times))
            (median-allocation (benchmark-median allocations)))
        (format
          t
          "~&~A~%iterations/trial: ~D~%trials: ~D~%"
          name
          iterations
          *benchmark-statistical-trials*)
        (format
          t
          "time: ~,1F ns/op median, ~,1F MAD (~,1F..~,1F)~%"
          median-time
          (benchmark-median-absolute-deviation times median-time)
          (reduce #'min times)
          (reduce #'max times))
        (format
          t
          "bytes-consed: ~,2F bytes/op median, ~,2F MAD (~,2F..~,2F)~%"
          median-allocation
          (benchmark-median-absolute-deviation allocations median-allocation)
          (reduce #'min allocations)
          (reduce #'max allocations)))))
  (defun make-benchmark-rgb-pixels (width height)
    (let ((pixels (make-array (* width height 3) :element-type '(unsigned-byte 8))))
      (loop for y below height
            do (loop for x below width
              for offset = (* (+ x (* y width)) 3)
              do (setf (aref pixels offset) (mod (+ (* x 17) y) 256)
                (aref pixels (+ offset 1)) (mod (+ x (* y 29)) 256)
                (aref pixels (+ offset 2)) (mod (+ (* x 7) (* y 11)) 256))))
      pixels))
  (defun make-image-encoding-case (encoder pixels width height)
    (labels ((input-checksum ()
               (loop with checksum = 2166136261
                     for octet across pixels
                     do (setf checksum
                          (logand #xffffffff (* 16777619 (logxor checksum octet))))
                     finally (return checksum))))
      (let ((reference nil)
            (expected-input-checksum (input-checksum)))
        (values
          (lambda ()
            (funcall encoder pixels width height))
          (lambda ()
            (let ((result (funcall encoder pixels width height)))
              (unless (and (stringp result) (plusp (length result)))
                (error "Image encoder preflight returned an empty or non-string result."))
              (setf reference (copy-seq result))))
          (lambda ()
            (unless (and
                (stringp *benchmark-result-sink*)
                (string= *benchmark-result-sink* reference))
              (error "Image encoder result changed from its preflight reference."))
            (unless (= (input-checksum) expected-input-checksum)
              (error "Image encoder mutated its input pixels.")))))))
  (defun make-base64-case (octets)
    (labels ((input-checksum ()
               (loop with checksum = 2166136261
                     for octet across octets
                     do (setf checksum
                          (logand #xffffffff (* 16777619 (logxor checksum octet))))
                     finally (return checksum))))
      (let ((expected-length (* 4 (ceiling (length octets) 3)))
            (expected-input-checksum (input-checksum))
            (reference nil))
        (values
          (lambda ()
            (%base64-encode-octets octets))
          (lambda ()
            (let ((result (%base64-encode-octets octets)))
              (unless (and
                  (stringp result)
                  (= (length result) expected-length))
                (error "Base64 preflight length did not match ~D." expected-length))
              (setf reference (copy-seq result))))
          (lambda ()
            (unless (and
                (stringp *benchmark-result-sink*)
                (string= *benchmark-result-sink* reference))
              (error "Base64 result changed from its preflight reference."))
            (unless (= (input-checksum) expected-input-checksum)
              (error "Base64 encoder mutated its input octets.")))))))
  (defun make-osc-52-case (text)
    (let* ((text-snapshot (copy-seq text))
           (reference
             (let ((octets
                     (sb-ext:string-to-octets text :external-format :utf-8)))
               (format nil
                       "~C]52;c;~A~C\\"
                       +escape+
                       (%base64-encode-octets octets)
                       +escape+))))
      (values
        (lambda ()
          (ansi-set-clipboard text))
        (lambda ()
          (let ((result (ansi-set-clipboard text)))
            (unless (and (stringp result) (string= result reference))
              (error "OSC 52 preflight did not match the reference implementation."))))
        (lambda ()
          (unless (and
              (stringp *benchmark-result-sink*)
              (string= *benchmark-result-sink* reference))
            (error "OSC 52 result changed from its preflight reference."))
          (unless (string= text text-snapshot)
            (error "OSC 52 encoder mutated its input text."))))))
  (defun make-format-table-case ()
    (let ((rows
            (loop for row-index below 100
                  collect
                  (loop for column-index below (- 12 (mod row-index 4))
                        collect
                        (case (mod (+ row-index column-index) 3)
                          (0
                           (format nil
                                   "cell-~2,'0D-~2,'0D"
                                   row-index
                                   column-index))
                          (1
                           (format nil "項目~2,'0D" column-index))
                          (2
                           (format nil "é-~2,'0D" row-index))))))
          (rows-snapshot nil)
          (reference nil))
      (values
        (lambda ()
          (format-table rows))
        (lambda ()
          (let ((result (format-table rows)))
            (unless (and (listp result) (= (length result) 100))
              (error "FORMAT-TABLE preflight returned an invalid result."))
            (setf rows-snapshot
                  (mapcar
                    (lambda (row)
                      (mapcar #'copy-seq row))
                    rows)
                  reference
                  (mapcar #'copy-seq result))))
        (lambda ()
          (unless (equal *benchmark-result-sink* reference)
            (error "FORMAT-TABLE result changed from its preflight reference."))
          (unless (equal rows rows-snapshot)
            (error "FORMAT-TABLE mutated its input rows.")))
        (reduce #'+ rows :key #'length))))
  (let ((iterations (benchmark-iterations))
        (style (make-style :underline (style-fg (named-color :yellow))))
        (ascii "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUV")
        (mixed "aあbいcうdえeおfかgきhくiけjこkさlしmすnせoそpた"))
    (unless (plusp iterations)
      (error "Expected a positive iteration count, got ~D." iterations))
    (multiple-value-bind (operation preflight post) (make-styled-threshold-render-case)
      (run-benchmark-case
        "render threshold styled"
        operation
        preflight
        post
        iterations))
    (multiple-value-bind (operation preflight post) (make-screen-write-case ascii style 47 #\V)
      (run-benchmark-case
        "screen-write-string ASCII styled"
        operation
        preflight
        post
        iterations))
    (multiple-value-bind (operation preflight post) (make-screen-write-case mixed style 46 #\た 47)
      (run-benchmark-case
        "screen-write-string mixed styled"
        operation
        preflight
        post
        iterations))
    (multiple-value-bind (operation preflight post) (make-pending-escape-case)
      (run-benchmark-case
        "input pending ESC non-EOF empty feed"
        operation
        preflight
        post
        iterations))
    (multiple-value-bind (operation preflight post) (make-pending-utf8-case)
      (run-benchmark-case
        "input pending UTF-8 non-EOF empty feed"
        operation
        preflight
        post
        iterations))
    (dolist (case (list (list "ASCII" ascii) (list "multibyte" mixed)))
      (multiple-value-bind (operation preflight post)
          (make-osc-52-case (second case))
        (run-statistical-benchmark-case
          (format nil "ansi-set-clipboard OSC 52 ~A" (first case))
          operation
          preflight
          post
          iterations)))
    (multiple-value-bind (operation preflight post cell-count)
        (make-format-table-case)
      (let ((case-iterations
              (max 1 (floor (* iterations 1200) cell-count))))
        (run-statistical-benchmark-case
          "format-table mixed ragged 100x12"
          operation
          preflight
          post
          case-iterations)))
    (multiple-value-bind (operation preflight post) (make-rgb-to-256-case)
      (run-benchmark-case
        "rgb-to-256 cycling valid RGB"
        operation
        preflight
        post
        iterations)))
  (dolist (dimensions '((16 16) (64 64) (256 256)))
    (destructuring-bind (width height) dimensions
      (let* ((pixels (make-benchmark-rgb-pixels width height))
             (case-iterations
            (max 1 (floor (* (benchmark-iterations) 4096) (* width height)))))
        (dolist (case (list (list "sixel" #'format-sixel) (list "kitty" #'ansi-kitty-image)))
          (multiple-value-bind (operation preflight post) (make-image-encoding-case (second case) pixels width height)
            (run-statistical-benchmark-case
              (format nil "~A RGB ~Dx~D" (first case) width height)
              operation
              preflight
              post
              case-iterations)))
        (multiple-value-bind (operation preflight post) (make-base64-case pixels)
          (run-statistical-benchmark-case
            (format nil "base64 RGB bytes ~Dx~D" width height)
            operation
            preflight
            post
            case-iterations))))))
