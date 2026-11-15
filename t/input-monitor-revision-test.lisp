(in-package #:cl-tty-kit/test)

(define-condition monitor-test-serious (serious-condition) ())

#+sb-thread
(defun monitor-test-wait-for-read (reader)
  (loop repeat 1000
        while (fd-wait reader :input 0)
        do (sleep 0.001))
  (when (fd-wait reader :input 0)
    (error "Monitor did not acknowledge a read.")))

#+sb-thread
(defun monitor-test-cg-p (event)
  (and (typep event 'key-event)
       (or (and (eq (key-event-type event) :special)
                (eq (key-event-code event) :control-g))
           (and (eq (key-event-type event) :character)
                (eql (key-event-code event) #\g)
                (member :control (key-event-modifiers event))))))

#+sb-thread
(defun monitor-test-streaming-trace (payload delay &key nonlocal measure)
  (with-monitor-pipe (reader writer)
    (let ((first-written (sb-thread:make-semaphore))
          (continue-writing (sb-thread:make-semaphore))
          (lock (sb-thread:make-mutex))
          (stop-writer nil)
          (producer nil)
          (producer-error nil)
          (call-error nil)
          (captured #())
          (body-values nil)
          (diagnostics nil)
          (body-ended nil)
          (elapsed nil)
          (remaining nil))
      (sb-posix:fcntl writer sb-posix:f-setfl
                      (logior (sb-posix:fcntl writer sb-posix:f-getfl)
                              sb-posix:o-nonblock))
      (unwind-protect
           (progn
             (handler-case
                 (catch 'monitor-stream-exit
                   (multiple-value-setq (captured body-values diagnostics)
                     (uiop:symbol-call
                       :cl-tty-kit :call-with-input-monitor reader
                       (lambda ()
                         (setf producer
                               (sb-thread:make-thread
                                 (lambda ()
                                   (handler-case
                                       (progn
                                         (fd-write-octets writer (subseq payload 0 1))
                                         (sb-thread:signal-semaphore first-written)
                                         (unless (sb-thread:wait-on-semaphore
                                                   continue-writing :timeout 1)
                                           (error "Writer was not released."))
                                         (loop with offset = 1
                                               while (< offset (length payload))
                                               until (sb-thread:with-mutex (lock)
                                                       stop-writer)
                                               for end = (min (length payload)
                                                              (+ offset 128))
                                               do (incf offset
                                                        (fd-write-octets
                                                          writer
                                                          (subseq payload offset end)))
                                                  (sleep 0.0002)))
                                     (serious-condition (condition)
                                       (setf producer-error condition))))
                                 :name "input-monitor test writer"))
                         (unless (sb-thread:wait-on-semaphore first-written :timeout 1)
                           (error "Writer did not start."))
                         (monitor-test-wait-for-read reader)
                         (sb-thread:signal-semaphore continue-writing)
                         (sleep delay)
                         (when measure (setf body-ended (get-internal-real-time)))
                         (when nonlocal (throw 'monitor-stream-exit :stopped))
                         :body-complete)
                       (lambda (event) (declare (ignore event)) nil)
                       :on-finish
                       (lambda (bytes)
                         (setf captured bytes)
                         (when measure
                           (setf elapsed
                                 (/ (- (get-internal-real-time) body-ended)
                                    internal-time-units-per-second)))))))
               (serious-condition (condition) (setf call-error condition)))
             ;; Drain while the producer finishes, so a full pipe cannot make
             ;; the test's producer join depend on the monitor still reading.
             (let ((buffer (make-array 4096 :element-type '(unsigned-byte 8)))
                   (chunks nil)
                   (total (length captured))
                   (deadline (+ (get-internal-real-time)
                                (* 3 internal-time-units-per-second))))
               (loop while (< total (length payload))
                     do (when (> (get-internal-real-time) deadline)
                          (error "Writer/drainer did not deliver the payload."))
                        (when (fd-wait reader :input 0.01)
                          (let ((count (fd-read-octets reader buffer)))
                            (when (and count (plusp count))
                              (push (subseq buffer 0 count) chunks)
                              (incf total count)))))
               (setf remaining
                     (apply #'concatenate '(vector (unsigned-byte 8))
                            (nreverse chunks))))
             (when producer-error (error producer-error))
             (when call-error (error call-error))
             (values captured remaining body-values diagnostics elapsed))
        (sb-thread:with-mutex (lock) (setf stop-writer t))
        (sb-thread:signal-semaphore continue-writing)
        (when producer (sb-thread:join-thread producer :default nil))))))

#+sb-thread
(defun monitor-test-partitioned-raw (payload widths)
  (with-monitor-pipe (reader writer)
    (multiple-value-bind (captured body-values diagnostics)
        (uiop:symbol-call
          :cl-tty-kit :call-with-input-monitor reader
          (lambda ()
            (loop with start = 0
                  for width in widths
                  for end = (min (length payload) (+ start width))
                  while (< start (length payload))
                  do (fd-write-octets writer (subseq payload start end))
                     (monitor-test-wait-for-read reader)
                     (setf start end)
                  finally (when (< start (length payload))
                            (fd-write-octets writer (subseq payload start))
                            (monitor-test-wait-for-read reader)))
            :delivered)
          (lambda (event) (declare (ignore event)) nil))
      (expect captured :to-equalp payload)
      (expect body-values :to-equal '(:delivered))
      (expect (every (lambda (entry)
                       (and (= (length entry) 2)
                            (eq (first entry) :decode)
                            (typep (second entry) 'serious-condition)))
                     diagnostics)))))

#+sb-thread
(defun monitor-test-cleanup-samples (streaming nonlocal)
  (let ((samples nil)
        (rng (make-random-state t)))
    (dotimes (trial 20)
      (let ((phase (/ (random 20 rng) 1000)))
        (if streaming
            (multiple-value-bind (captured remaining body-values diagnostics elapsed)
                (monitor-test-streaming-trace
                  (make-array 8192 :element-type '(unsigned-byte 8)
                                   :initial-element 97)
                  phase :nonlocal nonlocal :measure t)
              (declare (ignore captured remaining body-values diagnostics))
              (expect elapsed)
              (expect (< elapsed 0.05))
              (push elapsed samples))
            (with-monitor-pipe (reader writer)
              (let ((body-ended nil)
                    (elapsed nil))
                (catch 'monitor-idle-exit
                  (uiop:symbol-call
                    :cl-tty-kit :call-with-input-monitor reader
                    (lambda ()
                      (sleep phase)
                      (setf body-ended (get-internal-real-time))
                      (when nonlocal (throw 'monitor-idle-exit nil)))
                    (lambda (event) (declare (ignore event)) nil)
                    :on-finish
                    (lambda (bytes)
                      (declare (ignore bytes))
                      (setf elapsed
                            (/ (- (get-internal-real-time) body-ended)
                               internal-time-units-per-second)))))
                (expect elapsed)
                (expect (< elapsed 0.05))
                (push elapsed samples))))))
    (format t "~&monitor cleanup streaming=~S nonlocal=~S n=~D max=~,3Fms~%"
            streaming nonlocal (length samples) (* 1000 (reduce #'max samples)))
    samples))

#+sb-thread
(describe "input monitor revision"
  (it "recovers a truncated UTF-8 prefix before C-g interrupts an ignore-errors loop"
    (with-monitor-pipe (reader writer)
      (let ((owner sb-thread:*current-thread*)
            (done nil)
            (saved nil)
            (timer nil))
        (unwind-protect
             (let ((result
                     (catch 'monitor-revision-exit
                       (setf timer
                             (sb-thread:make-thread
                               (lambda ()
                                 (sleep 0.4)
                                 (sb-thread:interrupt-thread
                                   owner
                                   (lambda ()
                                     (unless done
                                       (throw 'monitor-revision-exit :watchdog)))))))
                       (uiop:symbol-call
                         :cl-tty-kit :call-with-input-monitor reader
                         (lambda ()
                           (fd-write-octets writer (monitor-test-octets '(#xE3 #x81)))
                           (monitor-test-wait-for-read reader)
                           (fd-write-octets writer (monitor-test-octets '(7)))
                           (loop (ignore-errors (sleep 0.001))))
                         (lambda (event)
                           (when (monitor-test-cg-p event)
                             (sb-thread:interrupt-thread
                               owner
                               (lambda ()
                                 (throw 'monitor-revision-exit :interrupted)))
                             :consume))
                         :on-finish (lambda (bytes) (setf saved bytes))))))
               (expect result :to-be :interrupted)
               (expect saved :to-equalp #(#xE3 #x81)))
          (sb-sys:without-interrupts
            (setf done t)
            (when timer (sb-thread:join-thread timer :default nil)))))))
  (it "recovers malformed UTF-8 and C-g in the same read without replacing body values"
    (with-monitor-pipe (reader writer)
      (let ((arrived (sb-thread:make-semaphore)))
        (multiple-value-bind (captured body-values diagnostics)
            (uiop:symbol-call
              :cl-tty-kit :call-with-input-monitor reader
              (lambda ()
                (fd-write-octets writer (monitor-test-octets '(#xE3 #x81 7)))
                (expect (sb-thread:wait-on-semaphore arrived :timeout 1))
                (values 42 :answer))
              (lambda (event)
                (when (monitor-test-cg-p event)
                  (sb-thread:signal-semaphore arrived)
                  :consume)))
          (expect captured :to-equalp #(#xE3 #x81))
          (expect body-values :to-equal '(42 :answer))
          (expect (mapcar #'first diagnostics) :to-equal '(:decode))
          (expect (typep (second (first diagnostics)) 'invalid-utf8-sequence))))))
  (it "keeps reading after an oversized paste decoder failure"
    (with-monitor-pipe (reader writer)
      (let ((decoder (make-input-decoder :collect-bracketed-paste t :max-pending 8))
            (arrived (sb-thread:make-semaphore)))
        (multiple-value-bind (captured body-values diagnostics)
            (uiop:symbol-call
              :cl-tty-kit :call-with-input-monitor reader
              (lambda ()
                (fd-write-octets writer
                                 (monitor-test-octets
                                   '(27 91 50 48 48 126 120 120 120 120 120 120 120 120 120
                                     27 91 50 48 49 126)))
                (monitor-test-wait-for-read reader)
                (fd-write-octets writer (monitor-test-octets '(7)))
                (expect (sb-thread:wait-on-semaphore arrived :timeout 1))
                :continued)
              (lambda (event)
                (when (monitor-test-cg-p event)
                  (sb-thread:signal-semaphore arrived)
                  :consume))
              :decoder decoder)
          (expect (length captured) :to-be 21)
          (expect body-values :to-equal '(:continued))
          (expect (mapcar #'first diagnostics) :to-equal '(:decode))
          (expect (typep (second (first diagnostics)) 'cl-tty-kit::input-buffer-exceeded))))))
  (it "consumes only the source ranges of explicit legacy and CSI-u C-g events"
    (with-monitor-pipe (reader writer)
      (let ((arrived (sb-thread:make-semaphore)))
        (multiple-value-bind (captured body-values diagnostics)
            (uiop:symbol-call
              :cl-tty-kit :call-with-input-monitor reader
              (lambda ()
                (fd-write-octets writer
                                 (monitor-test-octets '(97 7 98 27 91 49 48 51 59 53 117 99)))
                (expect (sb-thread:wait-on-semaphore arrived :n 5 :timeout 1))
                (values 42 :answer))
              (lambda (event)
                (sb-thread:signal-semaphore arrived)
                (when (monitor-test-cg-p event) :consume)))
          (expect captured :to-equalp #(97 98 99))
          (expect body-values :to-equal '(42 :answer))
          (expect diagnostics :to-be nil)))))
  (it "keeps bytes for other non-nil callback values"
    (with-monitor-pipe (reader writer)
      (let ((arrived (sb-thread:make-semaphore)))
        (expect
          (uiop:symbol-call
            :cl-tty-kit :call-with-input-monitor reader
            (lambda ()
              (fd-write-octets writer (monitor-test-octets '(7)))
              (expect (sb-thread:wait-on-semaphore arrived :timeout 1)))
            (lambda (event)
              (declare (ignore event))
              (sb-thread:signal-semaphore arrived)
              t))
          :to-equalp #(7)))))
  (it "consumes a normalized paste using its original framing and CRLF byte range"
    (with-monitor-pipe (reader writer)
      (let ((decoder (make-input-decoder :collect-bracketed-paste t
                                         :normalize-paste-line-endings t))
            (arrived (sb-thread:make-semaphore))
            (paste nil))
        (let ((captured
                (uiop:symbol-call
                  :cl-tty-kit :call-with-input-monitor reader
                  (lambda ()
                    (fd-write-octets writer
                                     (monitor-test-octets
                                       '(97 27 91 50 48 48 126 120 13 10 7
                                         27 91 50 48 49 126 98)))
                    (expect (sb-thread:wait-on-semaphore arrived :n 3 :timeout 1)))
                  (lambda (event)
                    (sb-thread:signal-semaphore arrived)
                    (when (eq (key-event-type event) :paste)
                      (setf paste (key-event-code event))
                      :consume))
                  :decoder decoder)))
          (expect paste :to-equal (coerce (list #\x #\Newline (code-char 7)) 'string))
          (expect captured :to-equalp #(97 98))
          (expect (mapcar #'key-event-code (decode-input-chunk decoder captured))
                  :to-equal '(#\a #\b))))))
  (it "transfers and consumes a CSI-u event spanning the supplied decoder's prefix"
    (with-monitor-pipe (reader writer)
      (let ((decoder (make-input-decoder :collect-bracketed-paste t))
            (arrived (sb-thread:make-semaphore)))
        (expect (decode-input-chunk decoder (monitor-test-octets '(27 91 49 48)))
                :to-be nil)
        (let ((captured
                (uiop:symbol-call
                  :cl-tty-kit :call-with-input-monitor reader
                  (lambda ()
                    (fd-write-octets writer (monitor-test-octets '(51 59 53 117 120)))
                    (expect (sb-thread:wait-on-semaphore arrived :n 2 :timeout 1)))
                  (lambda (event)
                    (sb-thread:signal-semaphore arrived)
                    (when (monitor-test-cg-p event) :consume))
                  :decoder decoder)))
          (expect captured :to-equalp #(120))
          (expect (mapcar #'key-event-code (decode-input-chunk decoder captured :eof t))
                  :to-equal '(#\x))))))
  (it "transfers an unfinished UTF-8 prefix and replays it exactly once"
    (with-monitor-pipe (reader writer)
      (let ((decoder (make-input-decoder :collect-bracketed-paste t))
            (arrived (sb-thread:make-semaphore)))
        (decode-input-chunk decoder (monitor-test-octets '(#xE2 #x9C)))
        (let ((captured
                (uiop:symbol-call
                  :cl-tty-kit :call-with-input-monitor reader
                  (lambda ()
                    (fd-write-octets writer (monitor-test-octets '(#x93 97)))
                    (expect (sb-thread:wait-on-semaphore arrived :n 2 :timeout 1)))
                  (lambda (event)
                    (declare (ignore event))
                    (sb-thread:signal-semaphore arrived)
                    nil)
                  :decoder decoder)))
          (expect captured :to-equalp #(#xE2 #x9C #x93 97))
          (expect (mapcar #'key-event-code (decode-input-chunk decoder captured :eof t))
                  :to-equal (list (code-char #x2713) #\a))))))
  (it "inherits an open paste so its C-g stays paste data"
    (with-monitor-pipe (reader writer)
      (let ((decoder (make-input-decoder :collect-bracketed-paste t))
            (arrived (sb-thread:make-semaphore))
            (events nil)
            (prefix (monitor-test-octets '(27 91 50 48 48 126 97))))
        (decode-input-chunk decoder prefix)
        (let* ((suffix (monitor-test-octets '(7 98 27 91 50 48 49 126)))
               (captured
                 (uiop:symbol-call
                   :cl-tty-kit :call-with-input-monitor reader
                   (lambda ()
                     (fd-write-octets writer suffix)
                     (expect (sb-thread:wait-on-semaphore arrived :timeout 1)))
                   (lambda (event)
                     (push event events)
                     (sb-thread:signal-semaphore arrived)
                     (when (monitor-test-cg-p event) :consume))
                   :decoder decoder)))
          (expect captured :to-equalp
                  (concatenate '(vector (unsigned-byte 8)) prefix suffix))
          (expect (length events) :to-be 1)
          (expect (key-event-type (first events)) :to-be :paste)
          (expect (mapcar #'%key-event-signature (decode-input-chunk decoder captured :eof t))
                  :to-equal (mapcar #'%key-event-signature events))))))
  (it "keeps monitoring after a callback serious-condition without replacing body values"
    (with-monitor-pipe (reader writer)
      (let ((arrived (sb-thread:make-semaphore))
            (calls 0))
        (multiple-value-bind (captured body-values diagnostics)
            (uiop:symbol-call
              :cl-tty-kit :call-with-input-monitor reader
              (lambda ()
                (fd-write-octets writer (monitor-test-octets '(97)))
                (expect (sb-thread:wait-on-semaphore arrived :timeout 1))
                (fd-write-octets writer (monitor-test-octets '(7)))
                (expect (sb-thread:wait-on-semaphore arrived :timeout 1))
                (values 42 :answer))
              (lambda (event)
                (incf calls)
                (sb-thread:signal-semaphore arrived)
                (if (= calls 1)
                    (progn (signal 'monitor-test-serious) :consume)
                    (when (monitor-test-cg-p event) :consume))))
          (expect calls :to-be 2)
          (expect captured :to-equalp #(97))
          (expect body-values :to-equal '(42 :answer))
          (expect (mapcar #'first diagnostics) :to-equal '(:on-event))
          (expect (typep (second (first diagnostics)) 'serious-condition))))))
  (it "returns at EOF without flushing an unfinished UTF-8 tail"
    (with-monitor-pipe (reader writer)
      (let ((arrived (sb-thread:make-semaphore))
            (worker nil))
        (fd-write-octets writer (monitor-test-octets '(97 #xE3 #x81)))
        (sb-unix:unix-close writer)
        (setf writer nil)
        (multiple-value-bind (captured body-values diagnostics)
            (uiop:symbol-call
              :cl-tty-kit :call-with-input-monitor reader
              (lambda ()
                (expect (sb-thread:wait-on-semaphore arrived :timeout 1))
                (loop repeat 1000 while (sb-thread:thread-alive-p worker)
                      do (sleep 0.001))
                (expect (sb-thread:thread-alive-p worker) :to-be nil)
                :eof)
              (lambda (event)
                (declare (ignore event))
                (setf worker sb-thread:*current-thread*)
                (sb-thread:signal-semaphore arrived)
                nil))
          (expect captured :to-equalp #(97 #xE3 #x81))
          (expect body-values :to-equal '(:eof))
          (expect diagnostics :to-be nil)))))
  (it "preserves inputs longer than the 4096-byte read buffer across partitions"
    (monitor-test-partitioned-raw
      (make-array 12289 :element-type '(unsigned-byte 8) :initial-element 97)
      '(4095 1 1 4096 4096))))
