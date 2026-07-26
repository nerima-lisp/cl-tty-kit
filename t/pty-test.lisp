(in-package #:cl-tty-kit/test)

#+sbcl
(defun read-pty-until (pty predicate &key (attempts 50) (sleep-seconds 0.01))
  (let ((chunks '()))
    (loop repeat attempts
          for chunk = (pty-read pty)
          do (when chunk
               (push chunk chunks)
               (let ((output (apply #'concatenate 'string (nreverse chunks))))
                 (when (funcall predicate output)
                   (return output))))
             (sleep sleep-seconds)
          finally (return (and chunks
                               (apply #'concatenate 'string (nreverse chunks)))))))

#+sbcl
(defun inherited-environment ()
  "The current process environment, for a child that must resolve a binary on PATH.
MAKE-PTY forwards :ENVIRONMENT straight to SB-EXT:RUN-PROGRAM, where NIL means an
*empty* environment rather than an inherited one -- so a PTY child spawned with
the default has no PATH, and any `sh -c' body calling a non-builtin exits 127.
That stays invisible on a developer machine because sh then falls back to a
compiled-in default PATH that happens to contain the binary; inside the Nix build
sandbox, and therefore in CI, it does not. Prefer shell builtins where possible
and this environment where a real binary is genuinely required."
  (sb-ext:posix-environ))

#+sbcl
(defmacro with-function-overrides ((&rest bindings) &body body)
  (let ((saved-bindings
          (loop for (name replacement) in bindings
                collect (list (gensym "FUNCTION-")
                              name
                              replacement))))
    `(let ,(loop for (saved name replacement) in saved-bindings
                 collect `(,saved (symbol-function ',name)))
       (unwind-protect
            (progn
              (sb-ext:without-package-locks
                ,@(loop for (_ name replacement) in saved-bindings
                        collect `(setf (symbol-function ',name) ,replacement)))
              ,@body)
         (sb-ext:without-package-locks
           ,@(loop for (saved name ignore) in saved-bindings
                   collect `(setf (symbol-function ',name) ,saved)))))))

#+sbcl
(defun %assert-pty-operation-failed (condition operation pty message)
  (is (eq operation (pty-operation-failed-operation condition)))
  (is (eq pty (pty-operation-failed-pty condition)))
  (is (search message (format nil "~A" condition))))

#+sbcl
(defmacro signals-pty-operation-failed ((operation pty message) &body body)
  `(signals (pty-operation-failed condition)
     (progn ,@body)
     (%assert-pty-operation-failed condition ,operation ,pty ,message)))

#+sbcl
(defmacro signals-simple-error-containing (message &body body)
  `(signals (simple-error condition)
     (progn ,@body)
     (is (search ,message (format nil "~A" condition)))))

#+sbcl
(defun test-pty ()
  (is (null (cl-tty-kit::%transient-spawn-failure-p
             (make-condition 'simple-error
                             :format-control "permanent failure"
                             :format-arguments nil))))
  (is (cl-tty-kit::%transient-spawn-failure-p
       (make-condition 'simple-error
                       :format-control "Resource temporarily unavailable"
                       :format-arguments nil)))
  (let ((attempt-count 0))
    (with-function-overrides
        ((sb-ext:run-program
           (lambda (&rest args)
             (declare (ignore args))
             (incf attempt-count)
             (error "Resource temporarily unavailable")))
         (sleep
           (lambda (&rest args)
             (declare (ignore args))
             nil)))
      (signals-simple-error-containing
          "Resource temporarily unavailable"
        (cl-tty-kit::%run-program-with-pty-retry "/bin/sh" nil nil nil
                                                 :attempts 3
                                                 :sleep-seconds 0))
      (is (= 3 attempt-count))))
  (let ((attempt-count 0))
    (with-function-overrides
        ((sb-ext:run-program
           (lambda (&rest args)
             (declare (ignore args))
             (incf attempt-count)
             :process))
         (sleep
           (lambda (&rest args)
             (declare (ignore args))
             nil)))
      (is (eq :process
              (cl-tty-kit::%run-program-with-pty-retry "/bin/sh" nil nil nil
                                                       :attempts 3
                                                       :sleep-seconds 0)))
      (is (= 1 attempt-count))))
  (signals-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
      (make-pty :program :not-a-program))
  (signals-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
      (make-pty :program "/bin/sh" :args '("-c" :not-a-string)))
  ;; ARGS/ENVIRONMENT that are not lists at all, as opposed to lists
  ;; containing a bad element.
  (signals-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
      (make-pty :program "/bin/sh" :args :bad))
  (signals-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
      (make-pty :program "/bin/sh" :environment '(:not-a-string)))
  (signals-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
      (make-pty :program "/bin/sh" :environment :bad))
  (signals-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
      (make-pty :program "/bin/sh" :directory :not-a-directory))
  (let ((alive-count 0))
    (with-function-overrides
        ((sb-ext:process-alive-p
           (lambda (process)
             (declare (ignore process))
             (incf alive-count)
             t))
         (sleep
           (lambda (&rest args)
             (declare (ignore args))
             nil)))
      (is (null (cl-tty-kit::%wait-for-process-exit :process
                                                    :attempts 2
                                                    :sleep-seconds 0)))
      (is (= 3 alive-count))))
  (let ((kill-signals '())
        (closed nil))
    (with-function-overrides
        ((close
           (lambda (stream &key abort)
             (declare (ignore stream abort))
             (setf closed t)))
         (cl-tty-kit::%wait-for-process-exit
           (lambda (process &key attempts sleep-seconds)
             (declare (ignore process attempts sleep-seconds))
             nil))
         (sb-ext:process-kill
           (lambda (process signal mode)
             (declare (ignore process mode))
             (push signal kill-signals)))
         (sb-ext:process-close
           (lambda (process)
             (declare (ignore process))
             :closed)))
      (signals-simple-error-containing
          "did not exit during shutdown"
        (cl-tty-kit::%close-pty-process :process :stream)))
    (is closed)
    (is (equal '(9 15) kill-signals)))
  (signals-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
      (make-pty :program "/definitely/missing"))
  (let* ((input (make-string-input-stream "abc"))
         (read-pty (cl-tty-kit::%make-pty :process nil :stream input)))
    (is (null (pty-process read-pty)))
    (is (eq input (pty-stream read-pty)))
    (is (string= "abc" (pty-read read-pty)))
    (is (null (pty-read read-pty)))
    (signals-pty-operation-failed (:read read-pty "PTY operation READ failed")
      (pty-read read-pty -1))
    (signals-pty-operation-failed (:read read-pty "PTY operation READ failed")
      (pty-read read-pty 1.5))
    (close-pty read-pty))
  (let* ((closed-input (make-string-input-stream "abc"))
         (read-pty (cl-tty-kit::%make-pty :process nil :stream closed-input)))
    (close closed-input)
    (signals-pty-operation-failed (:read read-pty "PTY operation READ failed")
      (pty-read read-pty)))
  (let ((pty (cl-tty-kit::%make-pty :process t :stream (make-string-input-stream ""))))
    (with-function-overrides
        ((cl-tty-kit::%close-pty-process
           (lambda (&rest args)
             (declare (ignore args))
             (error "close failed"))))
      (signals-pty-operation-failed (:close pty "PTY operation CLOSE failed")
        (close-pty pty))))
  (let* ((pty (make-pty :program "/bin/sh"))
         (process (pty-process pty)))
    (is (pty-process pty))
    (is (streamp (pty-stream pty)))
    (is (eq pty (close-pty pty)))
    (is (not (sb-ext:process-alive-p process)))
    (is (null (pty-process pty)))
    (is (null (pty-stream pty)))
    (is (eq pty (close-pty pty)))
    (is (null (pty-process pty)))
    (is (null (pty-stream pty))))
  ;; /bin/sh reads stdin, so closing its PTY stream alone (SIGPIPE/EOF) ends
  ;; it before %CLOSE-PTY-PROCESS ever needs to send a real signal -- the two
  ;; cases above never exercise %TERMINATE-PTY-PROCESS's actual SIGTERM path.
  ;; sleep(1) ignores stdin entirely, so it survives the stream close and
  ;; forces %CLOSE-PTY-PROCESS through %WAIT-FOR-PROCESS-EXIT returning NIL
  ;; once, then %TERMINATE-PTY-PROCESS's real SIGTERM successfully ending it.
  ;;
  ;; `exec sleep' through /bin/sh, rather than spawning "/bin/sleep" directly:
  ;; /bin/sh is the only absolute path the Nix build sandbox provides, and
  ;; sleep(1) lives in coreutils on PATH there, not at /bin/sleep. The `exec'
  ;; matters too: it replaces the shell, so nothing is left reading stdin,
  ;; which is the entire point of this case. INHERITED-ENVIRONMENT is what
  ;; actually puts coreutils on PATH -- see its docstring; without it the
  ;; shell cannot find sleep and exits 127 instead of blocking.
  (let* ((pty (make-pty :program "/bin/sh"
                        :args '("-c" "exec sleep 5")
                        :environment (inherited-environment)))
         (process (pty-process pty)))
    (is (sb-ext:process-alive-p process))
    (is (eq pty (close-pty pty)))
    (is (not (sb-ext:process-alive-p process))))
  (let* ((stream (make-string-input-stream "abc"))
         (pty (cl-tty-kit::%make-pty :process nil :stream stream)))
    (is (eq pty (close-pty pty)))
    (is (null (pty-process pty)))
    (is (null (pty-stream pty))))
  (let* ((output (make-string-output-stream))
         (write-pty (cl-tty-kit::%make-pty :process nil :stream output)))
    (is (null (pty-process write-pty)))
    (is (eq output (pty-stream write-pty)))
    (is (eq write-pty (pty-write write-pty "hi")))
    (is (string= "hi" (get-output-stream-string output)))
    (signals-pty-operation-failed (:write write-pty "PTY operation WRITE failed")
      (pty-write write-pty :bad))
    (signals-pty-operation-failed (:write write-pty "PTY operation WRITE failed")
      (pty-write write-pty #(104 :bad)))
    (let* ((vector-output (make-string-output-stream))
           (vector-pty (cl-tty-kit::%make-pty :process nil
                                              :stream vector-output)))
      (is (null (pty-process vector-pty)))
      (is (eq vector-output (pty-stream vector-pty)))
      (is (eq vector-pty (pty-write vector-pty #(104 105))))
      (is (string= "hi" (get-output-stream-string vector-output)))
      (let* ((utf8-output (make-string-output-stream))
             (utf8-pty (cl-tty-kit::%make-pty :process nil
                                              :stream utf8-output)))
        (is (eq utf8-pty (pty-write utf8-pty #(227 129 130))))
        (is (string= "あ" (get-output-stream-string utf8-output)))
        (close-pty utf8-pty))
      (let* ((invalid-output (make-string-output-stream))
             (invalid-pty (cl-tty-kit::%make-pty :process nil
                                                 :stream invalid-output)))
        (signals (pty-operation-failed condition)
            (pty-write invalid-pty #(255))
          (is (eq :write (pty-operation-failed-operation condition)))
          (is (eq invalid-pty (pty-operation-failed-pty condition)))
          (let ((reason (pty-operation-failed-reason condition)))
            (is (typep reason 'invalid-utf8-sequence))
            (is (= 0 (invalid-utf8-sequence-position reason)))
            (is (eq :invalid-leading-byte
                    (invalid-utf8-sequence-reason reason)))))
        (close-pty invalid-pty))
      (let* ((closed-output (make-string-output-stream))
             (closed-pty (cl-tty-kit::%make-pty :process nil
                                                :stream closed-output)))
        (close closed-output)
        (signals-pty-operation-failed (:write closed-pty "PTY operation WRITE failed")
          (pty-write closed-pty "x")))
      (close-pty vector-pty))
    (close-pty write-pty))
  ;; `printf' and `read' are both shell builtins, so this needs no PATH (see
  ;; INHERITED-ENVIRONMENT). The trailing `read' is what keeps the child alive
  ;; while the parent drains the master side: an earlier `sleep 0.05' here was
  ;; a timing bet that the child outlives the read loop, and it lost that bet
  ;; whenever sleep(1) was unavailable and the shell exited immediately --
  ;; a dead child makes the next master-side read fail with EIO rather than
  ;; return "hello". Blocking on stdin instead removes the race entirely: the
  ;; child now lives until CLOSE-PTY closes the master and it sees EOF.
  (let ((pty (make-pty :program "/bin/sh"
                       :args '("-c" "printf hello; read ignored"))))
    (is (pty-process pty))
    (is (streamp (pty-stream pty)))
    (let ((output (read-pty-until pty
                                  (lambda (output)
                                    (search "hello" output)))))
      (is (search "hello" output)))
    (close-pty pty))
  ;; PTY-RESIZE sets the window size, verifiable by reading it back via ioctl.
  (let ((pty (make-pty :program "/bin/sh")))
    (is (eq pty (pty-resize pty 111 37)))
    (let ((fd (cl-tty-kit::%stream-fd (pty-stream pty))))
      (when fd
        (multiple-value-bind (columns rows) (terminal-size fd)
          (is (eql 111 columns))
          (is (eql 37 rows)))))
    (close-pty pty))
  ;; A stream without a file descriptor signals a structured resize failure.
  (let ((pty (cl-tty-kit::%make-pty :process nil
                                    :stream (make-string-output-stream))))
    (signals-pty-operation-failed (:resize pty "PTY operation RESIZE failed")
      (pty-resize pty 80 24)))
  ;; Invalid COLUMNS/ROWS are rejected before the ioctl is ever attempted.
  (let ((pty (make-pty :program "/bin/sh")))
    (signals-pty-operation-failed (:resize pty "PTY operation RESIZE failed")
      (pty-resize pty 0 24))
    (signals-pty-operation-failed (:resize pty "PTY operation RESIZE failed")
      (pty-resize pty -1 24))
    (signals-pty-operation-failed (:resize pty "PTY operation RESIZE failed")
      (pty-resize pty 80 0))
    (signals-pty-operation-failed (:resize pty "PTY operation RESIZE failed")
      (pty-resize pty 80 -1))
    (signals-pty-operation-failed (:resize pty "PTY operation RESIZE failed")
      (pty-resize pty 1.5 24))
    (signals-pty-operation-failed (:resize pty "PTY operation RESIZE failed")
      (pty-resize pty 80 1.5))
    (close-pty pty))
  ;; PTY-ALIVE-P tracks the child's lifetime.
  (let ((pty (make-pty :program "/bin/sh")))
    (is (pty-alive-p pty))
    (close-pty pty)
    (is (not (pty-alive-p pty))))
  ;; A stream-only PTY (no process) is never alive.
  (is (not (pty-alive-p (cl-tty-kit::%make-pty :process nil
                                              :stream (make-string-input-stream "")))))
  ;; PTY-EXIT-CODE reports the child's status once it has finished.
  (let ((pty (make-pty :program "/bin/sh" :args '("-c" "exit 3"))))
    (loop repeat 200 while (pty-alive-p pty) do (sleep 0.01))
    (is (eql 3 (pty-exit-code pty)))
    (close-pty pty))
  (let ((pty (make-pty :program "/bin/sh" :args '("-c" "exit 0"))))
    (loop repeat 200 while (pty-alive-p pty) do (sleep 0.01))
    (is (eql 0 (pty-exit-code pty)))
    (close-pty pty))
  ;; No process -> no exit code.
  (is (null (pty-exit-code (cl-tty-kit::%make-pty :process nil
                                                 :stream (make-string-input-stream "")))))
  t)

#+sbcl
(defun test-pty-fd ()
  ;; FR-001 / FR-003: PTY-FD and PTY-PID on a live PTY.
  (let ((pty (make-pty :program "/bin/sh")))
    (unwind-protect
         (let ((fd (pty-fd pty))
               (pid (pty-pid pty)))
           (is (integerp fd))
           (is (plusp fd))
           (is (eql fd (cl-tty-kit::%stream-fd (pty-stream pty))))
           (is (integerp pid))
           (is (plusp pid))
           (is (eql pid (sb-ext:process-pid (pty-process pty)))))
      (close-pty pty)))
  ;; A stream-only PTY has no PID; a PTY whose stream lacks a descriptor signals.
  (is (null (pty-pid (cl-tty-kit::%make-pty :process nil
                                            :stream (make-string-input-stream "")))))
  (let ((fdless (cl-tty-kit::%make-pty :process nil
                                       :stream (make-string-output-stream))))
    (signals-pty-operation-failed (:fd fdless "PTY operation FD failed")
      (pty-fd fdless)))
  ;; A stream backed by a negative fd (SB-SYS:FD-STREAM-FD is -1 once its
  ;; underlying descriptor has itself been closed out from under a still-live
  ;; stream object) is declined the same way a non-integer fd is above, not
  ;; treated as a valid descriptor.
  (let* ((rigged (open "/dev/null" :direction :output :if-exists :append))
         (pty (cl-tty-kit::%make-pty :process nil :stream rigged))
         (real-fd (sb-sys:fd-stream-fd rigged)))
    (unwind-protect
         (progn
           (setf (sb-sys:fd-stream-fd rigged) -1)
           (signals-pty-operation-failed (:fd pty "PTY operation FD failed")
             (pty-fd pty)))
      ;; Restore the real descriptor before closing, or CLOSE would try to
      ;; close fd -1 and leak the one /dev/null actually opened.
      (setf (sb-sys:fd-stream-fd rigged) real-fd)
      (close rigged)))
  ;; FR-002: byte-transparent octet round-trip over a real pipe. The payload
  ;; carries a UTF-8 high-byte sequence (#xE2 #x9C #x93) plus NUL and ESC control
  ;; bytes, all of which must survive verbatim with no character decoding.
  (multiple-value-bind (rfd wfd) (sb-unix:unix-pipe)
    (unwind-protect
         (let ((payload (make-array 6 :element-type '(unsigned-byte 8)
                                      :initial-contents
                                      '(#xE2 #x9C #x93 #x00 #x1B #x41))))
           (is (= 6 (fd-write-octets wfd payload)))
           (let ((buffer (make-array 32 :element-type '(unsigned-byte 8)
                                        :initial-element 0)))
             (let ((count (fd-read-octets rfd buffer)))
               (is (eql 6 count))
               (is (equalp payload (subseq buffer 0 count))))))
      (sb-unix:unix-close wfd)
      (sb-unix:unix-close rfd)))
  ;; FR-002: a non-blocking read with no data ready returns NIL (never blocks);
  ;; once the peer closes, a ready read reports EOF as 0.
  (multiple-value-bind (rfd wfd) (sb-unix:unix-pipe)
    (let ((wfd-open t))
      (unwind-protect
           (let ((flags (sb-posix:fcntl rfd sb-posix:f-getfl))
                 (buffer (make-array 16 :element-type '(unsigned-byte 8))))
             (sb-posix:fcntl rfd sb-posix:f-setfl
                             (logior flags sb-posix:o-nonblock))
             (is (null (fd-read-octets rfd buffer)))
             (sb-unix:unix-close wfd)
             (setf wfd-open nil)
             (is (eql 0 (fd-read-octets rfd buffer))))
        (when wfd-open (sb-unix:unix-close wfd))
        (sb-unix:unix-close rfd))))
  ;; FR-002: fd-read-octets honours an explicit LIMIT smaller than the buffer and
  ;; returns 0 immediately for a zero-count request (early return, no syscall, so
  ;; it never blocks and consumes nothing).
  (multiple-value-bind (rfd wfd) (sb-unix:unix-pipe)
    (unwind-protect
         (let ((payload (make-array 6 :element-type '(unsigned-byte 8)
                                      :initial-contents '(1 2 3 4 5 6)))
               (buffer (make-array 16 :element-type '(unsigned-byte 8)
                                      :initial-element 0)))
           (is (= 6 (fd-write-octets wfd payload)))
           ;; LIMIT caps the read below the buffer length and what is available.
           (is (eql 3 (fd-read-octets rfd buffer 3)))
           (is (equalp #(1 2 3) (subseq buffer 0 3)))
           ;; Zero-count early return leaves the remaining 4 5 6 in the pipe.
           (is (eql 0 (fd-read-octets rfd buffer 0)))
           (is (eql 3 (fd-read-octets rfd buffer)))
           (is (equalp #(4 5 6) (subseq buffer 0 3))))
      (sb-unix:unix-close wfd)
      (sb-unix:unix-close rfd)))
  ;; FR-002: fd-write-octets short-write / non-blocking short-count contract.
  ;; A payload far larger than any pipe's kernel buffer cannot be written in one
  ;; shot on a non-blocking fd -- the first call fills the buffer and returns a
  ;; short count 0 < result < len. Draining the read end and resuming with the
  ;; remaining octets (subseq payload result) eventually writes every byte. This
  ;; is the multiplexer-critical resumable-write path.
  (multiple-value-bind (rfd wfd) (sb-unix:unix-pipe)
    (unwind-protect
         (let* ((len (* 1024 1024))
                (payload (make-array len :element-type '(unsigned-byte 8)
                                         :initial-element 65))
                (drain (make-array 65536 :element-type '(unsigned-byte 8))))
           ;; Both ends non-blocking so neither the resumed write nor the drain
           ;; loop can block this single-threaded test.
           (let ((wflags (sb-posix:fcntl wfd sb-posix:f-getfl))
                 (rflags (sb-posix:fcntl rfd sb-posix:f-getfl)))
             (sb-posix:fcntl wfd sb-posix:f-setfl
                             (logior wflags sb-posix:o-nonblock))
             (sb-posix:fcntl rfd sb-posix:f-setfl
                             (logior rflags sb-posix:o-nonblock)))
           (let ((first (fd-write-octets wfd payload)))
             ;; Short count: some but not all bytes made it into the buffer.
             (is (< 0 first))
             (is (< first len))
             (let ((total first))
               (loop while (< total len)
                     repeat 100000
                     do ;; Fully drain the read end (a non-blocking read returns
                        ;; NIL once the buffer empties), then resume writing the
                        ;; leftover octets from where the previous call stopped.
                        (loop for n = (fd-read-octets rfd drain)
                              while (and n (plusp n)))
                        (let ((wrote (fd-write-octets wfd (subseq payload total))))
                          (is (plusp wrote))
                          (incf total wrote)))
               (is (= total len)))))
      (sb-unix:unix-close wfd)
      (sb-unix:unix-close rfd)))
  ;; FR-001: PTY-FD after CLOSE-PTY has cleared the stream signals a structured
  ;; failure rather than returning a stale descriptor.
  (let ((closed-pty (make-pty :program "/bin/sh")))
    (close-pty closed-pty)
    (signals-pty-operation-failed (:fd closed-pty "PTY operation FD failed")
      (pty-fd closed-pty)))
  ;; Validation: a non-octet buffer and a bad fd are wrapped as PTY-OPERATION-FAILED.
  (signals-pty-operation-failed (:fd-read nil "PTY operation FD-READ failed")
    (fd-read-octets 0 "not-a-buffer"))
  (signals-pty-operation-failed (:fd-write nil "PTY operation FD-WRITE failed")
    (fd-write-octets -1 (make-array 0 :element-type '(unsigned-byte 8))))
  ;; A negative LIMIT is rejected before any syscall is attempted.
  (signals-pty-operation-failed (:fd-read nil "PTY operation FD-READ failed")
    (fd-read-octets 0 (make-array 1 :element-type '(unsigned-byte 8)) -1))
  ;; A syntactically valid but unopened fd reaches the real syscall and
  ;; surfaces its OS error (EBADF), distinct from the EAGAIN/EINTR retry path.
  (signals-pty-operation-failed (:fd-read nil "PTY operation FD-READ failed")
    (fd-read-octets 987654 (make-array 1 :element-type '(unsigned-byte 8))))
  (signals-pty-operation-failed (:fd-write nil "PTY operation FD-WRITE failed")
    (fd-write-octets 987654
                     (make-array 1 :element-type '(unsigned-byte 8)
                                   :initial-element 1)))
  ;; FR-002: fd-write-octets retries silently when unix-write is interrupted by
  ;; a signal (EINTR), the retry path a real syscall almost never exercises.
  (let ((call-count 0))
    (with-function-overrides
        ((sb-unix:unix-write
           (lambda (fd octets offset len)
             (declare (ignore fd octets offset))
             (incf call-count)
             (if (= call-count 1)
                 (values nil sb-unix:eintr)
                 (values len nil)))))
      (is (= 3 (fd-write-octets 0 (make-array 3 :element-type '(unsigned-byte 8)
                                                :initial-element 1))))
      (is (= 2 call-count))))
  t)

#-sbcl
(defun test-pty-fd ()
  (dolist (thunk (list (lambda () (pty-fd (cl-tty-kit::%make-pty)))
                       (lambda () (pty-pid (cl-tty-kit::%make-pty)))
                       (lambda () (fd-read-octets 0 nil))
                       (lambda () (fd-write-octets 0 nil))))
    (handler-case
        (progn (funcall thunk) (is nil))
      (unsupported-feature (condition)
        (is (eq :pty (unsupported-feature-feature condition))))))
  t)

#-sbcl
(defun test-pty ()
  (handler-case
      (progn
        (make-pty)
        (is nil))
    (unsupported-feature (condition)
      (is (eq :pty (unsupported-feature-feature condition)))))
  (handler-case
      (progn
        (close-pty (cl-tty-kit::%make-pty :process nil :stream (make-string-input-stream "")))
        (is nil))
    (unsupported-feature (condition)
      (is (eq :pty (unsupported-feature-feature condition)))))
  t)
