(in-package #:cl-tty-kit/test)

#+sb-thread
(defun monitor-test-read-race-trace (payload delay)
  (let ((read-original (fdefinition 'fd-read-octets))
        (join-original (fdefinition 'cl-concurrent-kit:join-thread))
        (read-held (sb-thread:make-semaphore))
        (return-gate (sb-thread:make-semaphore))
        (phase nil)
        (race-observed nil))
    (unwind-protect
         (progn
           (sb-sys:without-interrupts
             (setf (fdefinition 'fd-read-octets)
                   (lambda (&rest arguments)
                     (let ((count (apply read-original arguments)))
                       (when (and (null phase) count (plusp count)
                                  (equal (sb-thread:thread-name sb-thread:*current-thread*)
                                         "cl-tty-kit input monitor"))
                         ;; The real read has consumed bytes, but the monitor
                         ;; has not received its result or captured the chunk.
                         (setf phase :awaiting-return)
                         (sb-thread:signal-semaphore read-held)
                         (unwind-protect
                              (progn
                                (unless (sb-thread:wait-on-semaphore return-gate :timeout 1)
                                  (error "Read result was not released."))
                                (setf phase :returned))
                           (when (eq phase :awaiting-return)
                             (setf phase :aborted))))
                       count))
                   (fdefinition 'cl-concurrent-kit:join-thread)
                   (lambda (thread &rest options)
                     (when (equal (cl-concurrent-kit:thread-name thread)
                                  "cl-tty-kit input monitor")
                       ;; The production cleanup publishes stop before joining.
                       (when (eq phase :awaiting-return)
                         (setf race-observed t))
                       (sb-thread:signal-semaphore return-gate))
                     (apply join-original thread options))))
           (multiple-value-bind (captured remaining body-values diagnostics)
               (monitor-test-streaming-trace
                 payload delay
                 :read-ack (lambda ()
                             (unless (sb-thread:wait-on-semaphore read-held :timeout 1)
                               (error "No in-flight read result was observed."))))
             (values captured remaining body-values diagnostics race-observed)))
      (sb-thread:signal-semaphore return-gate)
      (sb-sys:without-interrupts
        (setf (fdefinition 'fd-read-octets) read-original
              (fdefinition 'cl-concurrent-kit:join-thread) join-original)))))

#+sb-thread
(describe "input monitor v190 contracts"
  (it "retains the completed read when stop arrives before read-result return"
    (let ((payload (make-array 8193 :element-type '(unsigned-byte 8) :initial-element 97)))
      (multiple-value-bind (captured remaining body-values diagnostics race-observed)
          (monitor-test-read-race-trace payload 0.003)
        (format t "~&controlled read race observed=~S captured=~D remaining=~D payload=~D~%"
                race-observed (length captured) (length remaining) (length payload))
        (expect race-observed)
        (expect (concatenate '(vector (unsigned-byte 8)) captured remaining)
                :to-equalp payload)
        (expect body-values :to-equal '(:body-complete))
        (expect (<= (length diagnostics) 1)))))
  (it "requests no more than 20ms for each real helper fd-wait"
    (let ((original (fdefinition 'fd-wait))
          (entered (sb-thread:make-semaphore))
          (timeouts nil))
      (unwind-protect
           (progn
             (sb-sys:without-interrupts
               (setf (fdefinition 'fd-wait)
                     (lambda (fd direction &optional timeout)
                       (when (equal (sb-thread:thread-name sb-thread:*current-thread*)
                                    "cl-tty-kit input monitor")
                         (push timeout timeouts)
                         (sb-thread:signal-semaphore entered))
                       (funcall original fd direction timeout))))
             (with-monitor-pipe (reader writer)
               (call-with-input-monitor
                 reader
                 (lambda ()
                   (unless (sb-thread:wait-on-semaphore entered :timeout 1)
                     (error "The helper did not enter fd-wait.")))
                 (lambda (event) (declare (ignore event)) nil))))
        (sb-sys:without-interrupts
          (setf (fdefinition 'fd-wait) original)))
      (expect (plusp (length timeouts)))
      (expect (every (lambda (timeout) (and (realp timeout) (<= timeout 0.020))) timeouts))))
  (it "consumes parameterized paste using its complete source framing"
    (with-monitor-pipe (reader writer)
      (let* ((done (sb-thread:make-semaphore))
             (source (concatenate 'string "a" (%esc "[200;5~hello")
                                  (%esc "[201~") "z"))
             (octets (cl-codec-kit:string-to-octets source :encoding :utf-8)))
        (multiple-value-bind (captured values diagnostics)
            (call-with-input-monitor
              reader
              (lambda ()
                (fd-write-octets writer octets)
                (unless (sb-thread:wait-on-semaphore done :timeout 1)
                  (error "Trailing key was not observed.")))
              (lambda (event)
                (cond ((eq (key-event-type event) :paste) :consume)
                      ((eql (key-event-code event) #\z)
                       (sb-thread:signal-semaphore done)
                       nil))))
          (declare (ignore values))
          (expect captured :to-equalp #(97 122))
          (expect diagnostics :to-be nil)))))
  (it "returns the exact inherited parameterized paste prefix for one replay"
    (with-monitor-pipe (reader writer)
      (let* ((decoder (make-input-decoder :collect-bracketed-paste t))
             (prefix (%esc "[200;5~a")))
        (decode-input-chunk decoder prefix)
        (multiple-value-bind (captured values diagnostics)
            (call-with-input-monitor reader (lambda () nil)
                                     (lambda (event) (declare (ignore event)) nil)
                                     :decoder decoder)
          (declare (ignore values))
          (expect captured :to-equalp (cl-codec-kit:string-to-octets prefix :encoding :utf-8))
          (expect diagnostics :to-be nil)
          (expect (decode-input-chunk decoder captured) :to-be nil)
          (expect (mapcar #'%key-event-signature (decode-input-chunk decoder (%esc "[201~")))
                  :to-equal '((:paste "a" nil)))))))
  (it "keeps parameterized paste source when EOF uses ordinary fallback"
    (let* ((decoder (make-input-decoder :collect-bracketed-paste t))
           (source (%esc "[200;5~a")))
      (decode-input-chunk decoder source)
      (let ((lengths nil)
            (expected (mapcar #'%key-event-signature (decode-input source))))
        (let ((cl-tty-kit::*input-decoder-source-length-sink*
                (lambda (length) (push length lengths))))
          (expect (mapcar #'%key-event-signature (flush-input-decoder decoder))
                  :to-equal expected))
        (expect (reduce #'+ lengths) :to-be
                (length (cl-codec-kit:string-to-octets source :encoding :utf-8))))))
  (it "consumes inherited parameterized paste without retaining its opening prefix"
    (with-monitor-pipe (reader writer)
      (let ((decoder (make-input-decoder :collect-bracketed-paste t))
            (done (sb-thread:make-semaphore)))
        (decode-input-chunk decoder (%esc "[200;5~a"))
        (multiple-value-bind (captured values diagnostics)
            (call-with-input-monitor
              reader
              (lambda ()
                (fd-write-octets writer
                  (cl-codec-kit:string-to-octets
                    (concatenate 'string "b" (%esc "[201~") "z") :encoding :utf-8))
                (unless (sb-thread:wait-on-semaphore done :timeout 1)
                  (error "Trailing key was not observed.")))
              (lambda (event)
                (cond ((eq (key-event-type event) :paste) :consume)
                      ((eql (key-event-code event) #\z)
                       (sb-thread:signal-semaphore done) nil)))
              :decoder decoder)
          (declare (ignore values))
          (expect captured :to-equalp #(122))
          (expect diagnostics :to-be nil)
          (expect (mapcar #'%key-event-signature (decode-input-chunk decoder captured))
                  :to-equal '((:character #\z nil)))))))
  (it "wakes an idle helper without waiting for the fd-wait timer"
    (let ((original (fdefinition 'fd-wait))
          (entered (sb-thread:make-semaphore))
          (body-ended nil)
          (elapsed nil)
          (calls 0))
      (unwind-protect
           (progn
             (sb-sys:without-interrupts
               (setf (fdefinition 'fd-wait)
                     (lambda (fd direction &optional timeout)
                       (if (equal (sb-thread:thread-name sb-thread:*current-thread*)
                                  "cl-tty-kit input monitor")
                           (progn
                             (incf calls)
                             (sb-thread:signal-semaphore entered)
                             ;; A readiness wake must work independently of
                             ;; the ordinary timer, even before select enters.
                             (funcall original fd direction 0.2))
                           (funcall original fd direction timeout)))))
             (with-monitor-pipe (reader writer)
               (multiple-value-bind (captured values diagnostics)
                   (call-with-input-monitor
                     reader
                     (lambda ()
                       (unless (sb-thread:wait-on-semaphore entered :timeout 1)
                         (error "Helper did not enter the wait."))
                       (setf body-ended (get-internal-real-time))
                       :body-complete)
                     (lambda (event) (declare (ignore event)) nil)
                     :on-finish
                     (lambda (bytes)
                       (declare (ignore bytes))
                       (setf elapsed (/ (- (get-internal-real-time) body-ended)
                                        internal-time-units-per-second))))
                 (expect captured :to-equalp #())
                 (expect values :to-equal '(:body-complete))
                 (expect diagnostics :to-be nil))))
        (sb-sys:without-interrupts (setf (fdefinition 'fd-wait) original)))
      (format t "~&readiness wake calls=~D elapsed=~,3Fms~%" calls (* 1000 elapsed))
      (expect (plusp calls))
      (expect (< elapsed 0.05))))
  (it "returns transferred input when private pipe creation fails"
    (let ((original (fdefinition 'cl-tty-kit::%make-input-monitor-wakeup-pipe))
          (injected (make-condition 'simple-error :format-control "pipe creation failed"))
          (observed nil)
          (saved nil)
          (calls 0)
          (decoder (make-input-decoder :collect-bracketed-paste t))
          (prefix (%esc "[200;5~a")))
      (decode-input-chunk decoder prefix)
      (unwind-protect
           (progn
             (sb-sys:without-interrupts
               (setf (fdefinition 'cl-tty-kit::%make-input-monitor-wakeup-pipe)
                     (lambda () (error injected))))
             (with-monitor-pipe (reader writer)
               (handler-case
                   (call-with-input-monitor
                     reader (lambda () (error "Body must not run."))
                     (lambda (event) (declare (ignore event)) nil)
                     :decoder decoder
                     :on-finish (lambda (bytes) (incf calls) (setf saved bytes)))
                 (error (condition) (setf observed condition)))))
        (sb-sys:without-interrupts
          (setf (fdefinition 'cl-tty-kit::%make-input-monitor-wakeup-pipe) original)))
      (expect observed :to-be injected)
      (expect calls :to-be 1)
      (expect saved :to-equalp (cl-codec-kit:string-to-octets prefix :encoding :utf-8))
      (expect (cl-tty-kit::%input-monitor-prefix decoder) :to-equalp #())
      (expect (decode-input-chunk decoder saved) :to-be nil)
      (expect (mapcar #'%key-event-signature (decode-input-chunk decoder (%esc "[201~")))
              :to-equal '((:paste "a" nil)))))
  (it "owns both pipe ends through EOF, creation interruption, and caller unwind"
    (let ((pipe-original (fdefinition 'cl-tty-kit::%make-input-monitor-wakeup-pipe))
          (thread-original (fdefinition 'cl-concurrent-kit:make-thread))
          (mode nil)
          (worker nil)
          (descriptors nil)
          (flags nil)
          (injected (make-condition 'simple-error :format-control "thread creation failed")))
      (unwind-protect
           (progn
             (sb-sys:without-interrupts
               (setf (fdefinition 'cl-tty-kit::%make-input-monitor-wakeup-pipe)
                     (lambda ()
                       (multiple-value-bind (reader writer) (funcall pipe-original)
                         (setf descriptors (list reader writer)
                               flags (mapcar (lambda (fd)
                                               (list (sb-posix:fcntl fd sb-posix:f-getfl)
                                                     (sb-posix:fcntl fd sb-posix:f-getfd)))
                                             descriptors))
                         (values reader writer)))
                     (fdefinition 'cl-concurrent-kit:make-thread)
                     (lambda (&rest arguments)
                       (when (eq mode :creation-error) (error injected))
                       (setf worker (apply thread-original arguments))
                       (when (eq mode :creation-interrupt)
                         (sb-thread:interrupt-thread
                           sb-thread:*current-thread* (lambda () (throw 'pipe-exit :interrupted))))
                       worker)))
             (dolist (test-mode '(:normal :nonlocal :eof :creation-error :creation-interrupt))
               (setf mode test-mode worker nil descriptors nil flags nil)
               (with-monitor-pipe (reader writer)
                 (let* ((input-flags (sb-posix:fcntl reader sb-posix:f-getfl))
                        (input-fd-flags (sb-posix:fcntl reader sb-posix:f-getfd))
                        (decoder (make-input-decoder :collect-bracketed-paste t))
                        (prefix (%esc "[200;5~a"))
                        (saved nil)
                        (finish-count 0)
                        (observed nil))
                   (decode-input-chunk decoder prefix)
                   (when (eq mode :eof) (sb-posix:close writer) (setf writer nil))
                   (let ((result
                           (catch 'pipe-exit
                             (handler-case
                                 (call-with-input-monitor
                                   reader
                                   (lambda ()
                                     (when (eq mode :nonlocal) (throw 'pipe-exit :escaped))
                                     (when (eq mode :eof)
                                       (loop repeat 1000 while (sb-thread:thread-alive-p worker)
                                             do (sleep 0.001))
                                       (unless (not (sb-thread:thread-alive-p worker))
                                         (error "EOF helper did not finish.")))
                                     :complete)
                                   (lambda (event) (declare (ignore event)) nil)
                                   :decoder decoder
                                   :on-finish (lambda (bytes)
                                                (incf finish-count) (setf saved bytes)))
                               (error (condition) (setf observed condition))))))
                     (case mode
                       (:nonlocal (expect result :to-be :escaped))
                       (:creation-interrupt (expect result :to-be :interrupted))
                       (:creation-error (expect observed :to-be injected))
                       (t (expect observed :to-be nil))))
                   (expect finish-count :to-be 1)
                   (expect saved :to-equalp (cl-codec-kit:string-to-octets prefix :encoding :utf-8))
                   (expect (cl-tty-kit::%input-monitor-prefix decoder) :to-equalp #())
                   (expect (length descriptors) :to-be 2)
                   (dolist (pair flags)
                     (expect (logtest sb-posix:o-nonblock (first pair)))
                     (expect (logtest 1 (second pair))))
                   (dolist (fd descriptors)
                     (expect (handler-case (progn (sb-posix:fcntl fd sb-posix:f-getfd) nil)
                               (sb-posix:syscall-error () t))))
                   (expect (sb-posix:fcntl reader sb-posix:f-getfl) :to-be input-flags)
                   (expect (sb-posix:fcntl reader sb-posix:f-getfd) :to-be input-fd-flags)
                   (when worker (expect (sb-thread:thread-alive-p worker) :to-be nil))))))
        (sb-sys:without-interrupts
          (setf (fdefinition 'cl-tty-kit::%make-input-monitor-wakeup-pipe) pipe-original
                (fdefinition 'cl-concurrent-kit:make-thread) thread-original)))))

  (it "isolates two simultaneous wake handlers from a caller serving fd events"
    (let ((original (fdefinition 'fd-wait))
          (ready (sb-thread:make-semaphore))
          (lock (sb-thread:make-mutex))
          (seen nil)
          (gates (vector (sb-thread:make-semaphore) (sb-thread:make-semaphore)))
          (finished (vector (sb-thread:make-semaphore) (sb-thread:make-semaphore)))
          (workers (make-array 2 :initial-element nil))
          (results (make-array 2 :initial-element nil))
          (errors (make-array 2 :initial-element nil))
          (caller-event nil))
      (unwind-protect
           (progn
             (sb-sys:without-interrupts
               (setf (fdefinition 'fd-wait)
                     (lambda (fd direction &optional timeout)
                       (if (equal (sb-thread:thread-name sb-thread:*current-thread*)
                                  "cl-tty-kit input monitor")
                           (progn
                             (sb-thread:with-mutex (lock)
                               (unless (member sb-thread:*current-thread* seen)
                                 (push sb-thread:*current-thread* seen)
                                 (sb-thread:signal-semaphore ready)))
                             (funcall original fd direction 0.2))
                           (funcall original fd direction timeout)))))
             (dotimes (index 2)
               (let ((slot index))
                 (setf (aref workers slot)
                       (sb-thread:make-thread
                         (lambda ()
                           (unwind-protect
                                (handler-case
                                    (with-monitor-pipe (reader writer)
                                      (setf (aref results slot)
                                            (multiple-value-list
                                              (call-with-input-monitor
                                                reader
                                                (lambda ()
                                                  (unless (sb-thread:wait-on-semaphore
                                                            (aref gates slot) :timeout 1)
                                                    (error "Monitor body was not released."))
                                                  :complete)
                                                (lambda (event) (declare (ignore event)) nil)))))
                                  (serious-condition (condition)
                                    (setf (aref errors slot) condition)))
                             (sb-thread:signal-semaphore (aref finished slot))))
                         :name "input-monitor concurrent caller"))))
             (unless (sb-thread:wait-on-semaphore ready :n 2 :timeout 1)
               (error "Both helpers did not reach their waits."))
             (with-monitor-pipe (reader writer)
               (sb-sys:with-fd-handler
                   (reader :input
                     (lambda (fd)
                       (fd-read-octets fd (make-array 1 :element-type '(unsigned-byte 8)))
                       (setf caller-event t)))
                 (sb-thread:signal-semaphore (aref gates 0))
                 (expect (sb-thread:wait-on-semaphore (aref finished 0) :timeout 1))
                 (expect (sb-thread:thread-alive-p (aref workers 1)))
                 (fd-write-octets writer (monitor-test-octets '(97)))
                 (loop repeat 100 until caller-event do (sb-sys:serve-event 0.001))
                 (expect caller-event)
                 (sb-thread:signal-semaphore (aref gates 1))
                 (expect (sb-thread:wait-on-semaphore (aref finished 1) :timeout 1))))
             (expect (length seen) :to-be 2)
             (dotimes (index 2)
               (expect (aref errors index) :to-be nil)
               (expect (aref results index) :to-equalp '(#() (:complete) nil))))
        (dotimes (index 2) (sb-thread:signal-semaphore (aref gates index)))
        (dotimes (index 2)
          (when (aref workers index) (sb-thread:join-thread (aref workers index) :default nil)))
        (sb-sys:without-interrupts (setf (fdefinition 'fd-wait) original)))))
)

