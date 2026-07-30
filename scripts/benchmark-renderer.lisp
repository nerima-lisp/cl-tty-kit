(progn
  (require :asdf)
  (load
    (merge-pathnames
      #P"bootstrap.lisp"
      (make-pathname :name nil :type nil :defaults *load-truename*)))
  (format t "~&[LOAD] cl-tty-kit~%")
  (finish-output)
  (let ((load-core-system (find-symbol "LOAD-CORE-SYSTEM" "CL-TTY-KIT/BOOTSTRAP")))
    (unless load-core-system
      (error "CL-TTY-KIT bootstrap did not export LOAD-CORE-SYSTEM."))
    (funcall (symbol-function load-core-system)))
  (format t "~&[LOAD] complete~%")
  (finish-output))

(in-package #:cl-tty-kit)

(defparameter *warmup-iterations* (let ((value (uiop:getenv "CL_TTY_KIT_BENCHMARK_WARMUP")))
    (if value (multiple-value-bind (integer position) (parse-integer value :junk-allowed t)
        (unless (and integer (= position (length value)) (not (minusp integer)))
          (error
            "CL_TTY_KIT_BENCHMARK_WARMUP must be a non-negative integer, got ~S."
            value))
        integer)
      1000)))

(defparameter *default-iterations* 100000)

(defun benchmark-iterations ()
  (or
    (loop for argument in (uiop:command-line-arguments)
          for (value position) = (multiple-value-list (parse-integer argument :junk-allowed t))
          when (and value (= position (length argument)))
            return value)
    *default-iterations*))

(progn
  (defun measure-render-diff (current previous iterations)
    "Measure repeated RENDER-DIFF calls for a stable sparse screen update."
    (let ((stream (make-broadcast-stream)))
      (loop repeat *warmup-iterations*
            do (render-diff current previous stream))
      (sb-ext:gc :full t)
      (let ((start-time (get-internal-real-time))
            (start-bytes (sb-ext:get-bytes-consed)))
        (loop repeat iterations
              do (render-diff current previous stream))
        (let* ((elapsed-ticks (max 1 (- (get-internal-real-time) start-time)))
               (elapsed-seconds (/ elapsed-ticks internal-time-units-per-second))
               (bytes-consed (- (sb-ext:get-bytes-consed) start-bytes)))
          (values elapsed-seconds bytes-consed)))))
  (defun measure-renderer-sparse-update (renderer iterations)
    "Measure one changed tail cell per RENDERER frame after the initial paint."
    (let ((stream (make-broadcast-stream))
          (screen (renderer-screen renderer))
          (x (1- (renderer-width renderer)))
          (y (1- (renderer-height renderer)))
          (x-cell (make-cell :char #\X))
          (y-cell (make-cell :char #\Y)))
      (renderer-render renderer :stream stream)
      (flet ((render-next-cell (iteration)
               (screen-put-cell
              screen
              x
              y
              (if (oddp iteration) x-cell
                y-cell))
               (renderer-render renderer :stream stream)))
        (loop for iteration below *warmup-iterations*
              do (render-next-cell iteration))
        (sb-ext:gc :full t)
        (let ((start-time (get-internal-real-time))
              (start-bytes (sb-ext:get-bytes-consed)))
          (loop for iteration below iterations
                do (render-next-cell iteration))
          (let* ((elapsed-ticks (max 1 (- (get-internal-real-time) start-time)))
                 (elapsed-seconds (/ elapsed-ticks internal-time-units-per-second))
                 (bytes-consed (- (sb-ext:get-bytes-consed) start-bytes)))
            (values elapsed-seconds bytes-consed)))))))

(defun measure-renderer-dense-update (renderer iterations)
  "Measure alternating full-screen frames after the initial paint."
  (let ((stream (make-broadcast-stream))
        (screen (renderer-screen renderer))
        (x-cell (make-cell :char #\X))
        (y-cell (make-cell :char #\Y)))
    (renderer-render renderer :stream stream)
    (flet ((render-next-frame (iteration)
             (screen-fill
            screen
            (if (oddp iteration) x-cell
              y-cell))
             (renderer-render renderer :stream stream)))
      (loop for iteration below *warmup-iterations*
            do (render-next-frame iteration))
      (sb-ext:gc :full t)
      (let ((start-time (get-internal-real-time))
            (start-bytes (sb-ext:get-bytes-consed)))
        (loop for iteration below iterations
              do (render-next-frame iteration))
        (let* ((elapsed-ticks (max 1 (- (get-internal-real-time) start-time)))
               (elapsed-seconds (/ elapsed-ticks internal-time-units-per-second))
               (bytes-consed (- (sb-ext:get-bytes-consed) start-bytes)))
          (values elapsed-seconds bytes-consed))))))

(let ((iterations (benchmark-iterations)))
  (unless (plusp iterations)
    (error "Expected a positive iteration count, got ~D." iterations))
  (let ((previous (make-screen 80 24))
        (current (make-screen 80 24))
        (renderer (make-renderer 80 24)))
    (screen-put-cell current 79 23 #\X)
    (multiple-value-bind (elapsed-seconds bytes-consed) (measure-render-diff current previous iterations)
      (format t "~&render-diff 80x24 tail update~%")
      (format t "iterations: ~D~%" iterations)
      (format t "elapsed: ~,3F s~%" (float elapsed-seconds 1.0))
      (format t "throughput: ~,1F frames/s~%" (/ iterations elapsed-seconds))
      (format t "allocation: ~,2F bytes/frame~%" (/ bytes-consed iterations)))
    (multiple-value-bind (elapsed-seconds bytes-consed) (measure-renderer-sparse-update renderer iterations)
      (format t "~&renderer-render 80x24 tail update~%")
      (format t "iterations: ~D~%" iterations)
      (format t "elapsed: ~,3F s~%" (float elapsed-seconds 1.0))
      (format t "throughput: ~,1F frames/s~%" (/ iterations elapsed-seconds))
      (format t "allocation: ~,2F bytes/frame~%" (/ bytes-consed iterations)))
    (multiple-value-bind (elapsed-seconds bytes-consed) (measure-renderer-dense-update (make-renderer 80 24) iterations)
      (format t "~&renderer-render 80x24 full repaint~%")
      (format t "iterations: ~D~%" iterations)
      (format t "elapsed: ~,3F s~%" (float elapsed-seconds 1.0))
      (format t "throughput: ~,1F frames/s~%" (/ iterations elapsed-seconds))
      (format t "allocation: ~,2F bytes/frame~%" (/ bytes-consed iterations)))))
