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
(defmacro expect-pty-operation-failed ((operation pty message) &body body)
  "The cl-weave counterpart to the legacy SIGNALS-PTY-OPERATION-FAILED: asserts
BODY signals PTY-OPERATION-FAILED naming OPERATION and PTY, with MESSAGE
present in its report."
  `(expect (lambda () ,@body)
           :to-throw
           (lambda (condition)
             (and (typep condition 'pty-operation-failed)
                  (eq ,operation (pty-operation-failed-operation condition))
                  (eq ,pty (pty-operation-failed-pty condition))
                  (search ,message (format nil "~A" condition))))))

#+sbcl
(defmacro expect-simple-error-containing (message &body body)
  "The cl-weave counterpart to the legacy SIGNALS-SIMPLE-ERROR-CONTAINING:
asserts BODY signals a SIMPLE-ERROR whose report contains MESSAGE."
  `(expect (lambda () ,@body)
           :to-throw
           (lambda (condition)
             (and (typep condition 'simple-error)
                  (search ,message (format nil "~A" condition))))))

#+sbcl
(describe "%transient-spawn-failure-p"
  (it "does not classify an ordinary error message as a transient spawn failure"
    (expect (null (cl-tty-kit::%transient-spawn-failure-p
                   (make-condition 'simple-error
                                   :format-control "permanent failure"
                                   :format-arguments nil)))))
  (it "classifies a resource-temporarily-unavailable message as a transient spawn failure"
    (expect (cl-tty-kit::%transient-spawn-failure-p
             (make-condition 'simple-error
                             :format-control "Resource temporarily unavailable"
                             :format-arguments nil)))))

#+sbcl
(describe "%run-program-with-pty-retry"
  (it "reraises the last error after exhausting ATTEMPTS on repeated transient failures"
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
        (expect-simple-error-containing
            "Resource temporarily unavailable"
          (cl-tty-kit::%run-program-with-pty-retry "/bin/sh" nil nil nil
                                                   :attempts 3
                                                   :sleep-seconds 0))
        (expect attempt-count :to-be 3))))
  (it "returns the process immediately without retrying when the first attempt succeeds"
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
        (expect (cl-tty-kit::%run-program-with-pty-retry "/bin/sh" nil nil nil
                                                          :attempts 3
                                                          :sleep-seconds 0)
                :to-be :process)
        (expect attempt-count :to-be 1)))))

#+sbcl
(describe "make-pty argument validation at spawn time"
  (it "rejects a non-string PROGRAM"
    (expect-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
        (make-pty :program :not-a-program)))
  (it "rejects a non-string element within ARGS"
    (expect-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
        (make-pty :program "/bin/sh" :args '("-c" :not-a-string))))
  ;; ARGS/ENVIRONMENT that are not lists at all, as opposed to lists
  ;; containing a bad element.
  (it "rejects an ARGS value that is not a list at all"
    (expect-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
        (make-pty :program "/bin/sh" :args :bad)))
  (it "rejects a non-string element within ENVIRONMENT"
    (expect-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
        (make-pty :program "/bin/sh" :environment '(:not-a-string))))
  (it "rejects an ENVIRONMENT value that is not a list at all"
    (expect-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
        (make-pty :program "/bin/sh" :environment :bad)))
  (it "rejects a non-pathname-designator DIRECTORY"
    (expect-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
        (make-pty :program "/bin/sh" :directory :not-a-directory))))

#+sbcl
(describe "%wait-for-process-exit"
  (it "polls PROCESS-ALIVE-P once per attempt plus a final check, sleeping between, and returns NIL when the process never exits"
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
        (expect (null (cl-tty-kit::%wait-for-process-exit :process
                                                          :attempts 2
                                                          :sleep-seconds 0)))
        (expect alive-count :to-be 3)))))

#+sbcl
(describe "%close-pty-process shutdown escalation"
  (it "closes the stream, escalates SIGTERM then SIGKILL, and signals when the process still has not exited"
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
        (expect-simple-error-containing
            "did not exit during shutdown"
          (cl-tty-kit::%close-pty-process :process :stream)))
      (expect closed)
      (expect kill-signals :to-equal '(9 15)))))

#+sbcl
(describe "make-pty against a missing program"
  (it "signals PTY-OPERATION-FAILED for :spawn when the program does not exist"
    (expect-pty-operation-failed (:spawn nil "PTY operation SPAWN failed")
        (make-pty :program "/definitely/missing"))))

#+sbcl
(describe "PTY-READ over a stream-only PTY"
  (it "reads the backing stream, exhausts to NIL at EOF, and rejects invalid COUNT arguments"
    (let* ((input (make-string-input-stream "abc"))
           (read-pty (cl-tty-kit::%make-pty :process nil :stream input)))
      (expect (null (pty-process read-pty)))
      (expect (pty-stream read-pty) :to-be input)
      (expect (pty-read read-pty) :to-equal "abc")
      (expect (null (pty-read read-pty)))
      (expect-pty-operation-failed (:read read-pty "PTY operation READ failed")
        (pty-read read-pty -1))
      (expect-pty-operation-failed (:read read-pty "PTY operation READ failed")
        (pty-read read-pty 1.5))
      (close-pty read-pty))))

#+sbcl
(describe "PTY-READ from a closed stream"
  (it "signals PTY-OPERATION-FAILED for :read when the underlying stream is already closed"
    (let* ((closed-input (make-string-input-stream "abc"))
           (read-pty (cl-tty-kit::%make-pty :process nil :stream closed-input)))
      (close closed-input)
      (expect-pty-operation-failed (:read read-pty "PTY operation READ failed")
        (pty-read read-pty)))))

#+sbcl
(describe "CLOSE-PTY error handling"
  (it "wraps a failure from %CLOSE-PTY-PROCESS as PTY-OPERATION-FAILED for :close"
    (let ((pty (cl-tty-kit::%make-pty :process t :stream (make-string-input-stream ""))))
      (with-function-overrides
          ((cl-tty-kit::%close-pty-process
             (lambda (&rest args)
               (declare (ignore args))
               (error "close failed"))))
        (expect-pty-operation-failed (:close pty "PTY operation CLOSE failed")
          (close-pty pty))))))

#+sbcl
(describe "CLOSE-PTY lifecycle over a live /bin/sh process"
  (it "terminates the process, clears process/stream, and is idempotent on a second call"
    (let* ((pty (make-pty :program "/bin/sh"))
           (process (pty-process pty)))
      (expect (pty-process pty))
      (expect (streamp (pty-stream pty)))
      (expect (close-pty pty) :to-be pty)
      (expect (not (sb-ext:process-alive-p process)))
      (expect (null (pty-process pty)))
      (expect (null (pty-stream pty)))
      (expect (close-pty pty) :to-be pty)
      (expect (null (pty-process pty)))
      (expect (null (pty-stream pty))))))

#+sbcl
(describe "CLOSE-PTY forcing SIGTERM against a child ignoring stdin EOF"
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
  (it "closes a live child that outlives the stream close by escalating to SIGTERM"
    (let* ((pty (make-pty :program "/bin/sh"
                          :args '("-c" "exec sleep 5")
                          :environment (inherited-environment)))
           (process (pty-process pty)))
      (expect (sb-ext:process-alive-p process))
      (expect (close-pty pty) :to-be pty)
      (expect (not (sb-ext:process-alive-p process))))))

#+sbcl
(describe "CLOSE-PTY over a stream-only PTY"
  (it "is idempotent and clears process/stream even without a real process"
    (let* ((stream (make-string-input-stream "abc"))
           (pty (cl-tty-kit::%make-pty :process nil :stream stream)))
      (expect (close-pty pty) :to-be pty)
      (expect (null (pty-process pty)))
      (expect (null (pty-stream pty))))))

#+sbcl
(describe "PTY-WRITE"
  (it "writes octets to the backing stream, validates the octet buffer, and handles vector/UTF-8/invalid-UTF-8/closed-stream cases"
    (let* ((output (make-string-output-stream))
           (write-pty (cl-tty-kit::%make-pty :process nil :stream output)))
      (expect (null (pty-process write-pty)))
      (expect (pty-stream write-pty) :to-be output)
      (expect (pty-write write-pty "hi") :to-be write-pty)
      (expect (get-output-stream-string output) :to-equal "hi")
      (expect-pty-operation-failed (:write write-pty "PTY operation WRITE failed")
        (pty-write write-pty :bad))
      (expect-pty-operation-failed (:write write-pty "PTY operation WRITE failed")
        (pty-write write-pty #(104 :bad)))
      (let* ((vector-output (make-string-output-stream))
             (vector-pty (cl-tty-kit::%make-pty :process nil
                                                :stream vector-output)))
        (expect (null (pty-process vector-pty)))
        (expect (pty-stream vector-pty) :to-be vector-output)
        (expect (pty-write vector-pty #(104 105)) :to-be vector-pty)
        (expect (get-output-stream-string vector-output) :to-equal "hi")
        (let* ((utf8-output (make-string-output-stream))
               (utf8-pty (cl-tty-kit::%make-pty :process nil
                                                :stream utf8-output)))
          (expect (pty-write utf8-pty #(227 129 130)) :to-be utf8-pty)
          (expect (get-output-stream-string utf8-output) :to-equal "あ")
          (close-pty utf8-pty))
        (let* ((invalid-output (make-string-output-stream))
               (invalid-pty (cl-tty-kit::%make-pty :process nil
                                                   :stream invalid-output)))
          (expect (lambda () (pty-write invalid-pty #(255)))
                  :to-throw
                  (lambda (condition)
                    (and (typep condition 'pty-operation-failed)
                         (eq :write (pty-operation-failed-operation condition))
                         (eq invalid-pty (pty-operation-failed-pty condition))
                         (let ((reason (pty-operation-failed-reason condition)))
                           (and (typep reason 'invalid-utf8-sequence)
                                (= 0 (invalid-utf8-sequence-position reason))
                                (eq :invalid-leading-byte
                                    (invalid-utf8-sequence-reason reason)))))))
          (close-pty invalid-pty))
        (let* ((closed-output (make-string-output-stream))
               (closed-pty (cl-tty-kit::%make-pty :process nil
                                                  :stream closed-output)))
          (close closed-output)
          (expect-pty-operation-failed (:write closed-pty "PTY operation WRITE failed")
            (pty-write closed-pty "x")))
        (close-pty vector-pty))
      (close-pty write-pty))))

#+sbcl
(describe "PTY-READ over a live /bin/sh child"
  ;; `printf' and `read' are both shell builtins, so this needs no PATH (see
  ;; INHERITED-ENVIRONMENT). The trailing `read' is what keeps the child alive
  ;; while the parent drains the master side: an earlier `sleep 0.05' here was
  ;; a timing bet that the child outlives the read loop, and it lost that bet
  ;; whenever sleep(1) was unavailable and the shell exited immediately --
  ;; a dead child makes the next master-side read fail with EIO rather than
  ;; return "hello". Blocking on stdin instead removes the race entirely: the
  ;; child now lives until CLOSE-PTY closes the master and it sees EOF.
  (it "reads output written by the child, accumulated via READ-PTY-UNTIL"
    (let ((pty (make-pty :program "/bin/sh"
                         :args '("-c" "printf hello; read ignored"))))
      (expect (pty-process pty))
      (expect (streamp (pty-stream pty)))
      (let ((output (read-pty-until pty
                                    (lambda (output)
                                      (search "hello" output)))))
        (expect (search "hello" output)))
      (close-pty pty))))

#+sbcl
(describe "PTY-RESIZE"
  ;; PTY-RESIZE sets the window size, verifiable by reading it back via ioctl.
  (it "sets the window size, verifiable by reading it back via ioctl"
    (let ((pty (make-pty :program "/bin/sh")))
      (expect (pty-resize pty 111 37) :to-be pty)
      (let ((fd (cl-tty-kit::%stream-fd (pty-stream pty))))
        (when fd
          (multiple-value-bind (columns rows) (terminal-size fd)
            (expect columns :to-be 111)
            (expect rows :to-be 37))))
      (close-pty pty)))
  ;; A stream without a file descriptor signals a structured resize failure.
  (it "signals a structured resize failure for a stream without a file descriptor"
    (let ((pty (cl-tty-kit::%make-pty :process nil
                                      :stream (make-string-output-stream))))
      (expect-pty-operation-failed (:resize pty "PTY operation RESIZE failed")
        (pty-resize pty 80 24))))
  ;; Invalid COLUMNS/ROWS are rejected before the ioctl is ever attempted.
  (it "rejects invalid COLUMNS/ROWS before the ioctl is ever attempted"
    (let ((pty (make-pty :program "/bin/sh")))
      (expect-pty-operation-failed (:resize pty "PTY operation RESIZE failed")
        (pty-resize pty 0 24))
      (expect-pty-operation-failed (:resize pty "PTY operation RESIZE failed")
        (pty-resize pty -1 24))
      (expect-pty-operation-failed (:resize pty "PTY operation RESIZE failed")
        (pty-resize pty 80 0))
      (expect-pty-operation-failed (:resize pty "PTY operation RESIZE failed")
        (pty-resize pty 80 -1))
      (expect-pty-operation-failed (:resize pty "PTY operation RESIZE failed")
        (pty-resize pty 1.5 24))
      (expect-pty-operation-failed (:resize pty "PTY operation RESIZE failed")
        (pty-resize pty 80 1.5))
      (close-pty pty))))

#+sbcl
(describe "PTY-ALIVE-P"
  ;; PTY-ALIVE-P tracks the child's lifetime.
  (it "tracks the child's lifetime, live before CLOSE-PTY and not after"
    (let ((pty (make-pty :program "/bin/sh")))
      (expect (pty-alive-p pty))
      (close-pty pty)
      (expect (not (pty-alive-p pty)))))
  ;; A stream-only PTY (no process) is never alive.
  (it "is never true for a stream-only PTY with no process"
    (expect (not (pty-alive-p (cl-tty-kit::%make-pty :process nil
                                                     :stream (make-string-input-stream "")))))))

#+sbcl
(describe "PTY-EXIT-CODE"
  ;; PTY-EXIT-CODE reports the child's status once it has finished.
  (it "reports the child's exit status once it has finished, for a nonzero exit"
    (let ((pty (make-pty :program "/bin/sh" :args '("-c" "exit 3"))))
      (loop repeat 200 while (pty-alive-p pty) do (sleep 0.01))
      (expect (pty-exit-code pty) :to-be 3)
      (close-pty pty)))
  (it "reports the child's exit status once it has finished, for a zero exit"
    (let ((pty (make-pty :program "/bin/sh" :args '("-c" "exit 0"))))
      (loop repeat 200 while (pty-alive-p pty) do (sleep 0.01))
      (expect (pty-exit-code pty) :to-be 0)
      (close-pty pty)))
  ;; No process -> no exit code.
  (it "is NIL when there is no process"
    (expect (null (pty-exit-code (cl-tty-kit::%make-pty :process nil
                                                        :stream (make-string-input-stream "")))))))

#+sbcl
(describe "PTY-FD and PTY-PID"
  ;; FR-001 / FR-003: PTY-FD and PTY-PID on a live PTY.
  (it "report the live process's real fd and pid"
    (let ((pty (make-pty :program "/bin/sh")))
      (unwind-protect
           (let ((fd (pty-fd pty))
                 (pid (pty-pid pty)))
             (expect (integerp fd))
             (expect (plusp fd))
             (expect (cl-tty-kit::%stream-fd (pty-stream pty)) :to-be fd)
             (expect (integerp pid))
             (expect (plusp pid))
             (expect (sb-ext:process-pid (pty-process pty)) :to-be pid))
        (close-pty pty)))))

#+sbcl
(describe "PTY-PID and PTY-FD without a live process"
  ;; A stream-only PTY has no PID; a PTY whose stream lacks a descriptor signals.
  (it "PTY-PID is NIL for a stream-only PTY with no process"
    (expect (null (pty-pid (cl-tty-kit::%make-pty :process nil
                                                  :stream (make-string-input-stream ""))))))
  (it "PTY-FD signals PTY-OPERATION-FAILED when the stream lacks a descriptor"
    (let ((fdless (cl-tty-kit::%make-pty :process nil
                                         :stream (make-string-output-stream))))
      (expect-pty-operation-failed (:fd fdless "PTY operation FD failed")
        (pty-fd fdless))))
  ;; A stream backed by a negative fd (SB-SYS:FD-STREAM-FD is -1 once its
  ;; underlying descriptor has itself been closed out from under a still-live
  ;; stream object) is declined the same way a non-integer fd is above, not
  ;; treated as a valid descriptor.
  (it "declines a stream backed by a negative fd the same way as a non-integer fd"
    (let* ((rigged (open "/dev/null" :direction :output :if-exists :append))
           (pty (cl-tty-kit::%make-pty :process nil :stream rigged))
           (real-fd (sb-sys:fd-stream-fd rigged)))
      (unwind-protect
           (progn
             (setf (sb-sys:fd-stream-fd rigged) -1)
             (expect-pty-operation-failed (:fd pty "PTY operation FD failed")
               (pty-fd pty)))
        ;; Restore the real descriptor before closing, or CLOSE would try to
        ;; close fd -1 and leak the one /dev/null actually opened.
        (setf (sb-sys:fd-stream-fd rigged) real-fd)
        (close rigged)))))

#+sbcl
(describe "fd-read-octets / fd-write-octets over real pipes"
  ;; FR-002: byte-transparent octet round-trip over a real pipe. The payload
  ;; carries a UTF-8 high-byte sequence (#xE2 #x9C #x93) plus NUL and ESC control
  ;; bytes, all of which must survive verbatim with no character decoding.
  (it "round-trips a UTF-8/NUL/ESC octet payload without character decoding"
    (multiple-value-bind (rfd wfd) (sb-unix:unix-pipe)
      (unwind-protect
           (let ((payload (make-array 6 :element-type '(unsigned-byte 8)
                                        :initial-contents
                                        '(#xE2 #x9C #x93 #x00 #x1B #x41))))
             (expect (fd-write-octets wfd payload) :to-be 6)
             (let ((buffer (make-array 32 :element-type '(unsigned-byte 8)
                                          :initial-element 0)))
               (let ((count (fd-read-octets rfd buffer)))
                 (expect count :to-be 6)
                 (expect (subseq buffer 0 count) :to-equalp payload))))
        (sb-unix:unix-close wfd)
        (sb-unix:unix-close rfd))))
  ;; FR-002: a non-blocking read with no data ready returns NIL (never blocks);
  ;; once the peer closes, a ready read reports EOF as 0.
  (it "a non-blocking read with no data ready returns NIL; a ready read reports EOF as 0 once the peer closes"
    (multiple-value-bind (rfd wfd) (sb-unix:unix-pipe)
      (let ((wfd-open t))
        (unwind-protect
             (let ((flags (sb-posix:fcntl rfd sb-posix:f-getfl))
                   (buffer (make-array 16 :element-type '(unsigned-byte 8))))
               (sb-posix:fcntl rfd sb-posix:f-setfl
                               (logior flags sb-posix:o-nonblock))
               (expect (null (fd-read-octets rfd buffer)))
               (sb-unix:unix-close wfd)
               (setf wfd-open nil)
               (expect (fd-read-octets rfd buffer) :to-be 0))
          (when wfd-open (sb-unix:unix-close wfd))
          (sb-unix:unix-close rfd)))))
  ;; FR-002: fd-read-octets honours an explicit LIMIT smaller than the buffer and
  ;; returns 0 immediately for a zero-count request (early return, no syscall, so
  ;; it never blocks and consumes nothing).
  (it "honours an explicit LIMIT smaller than the buffer, and returns 0 immediately for a zero-count request"
    (multiple-value-bind (rfd wfd) (sb-unix:unix-pipe)
      (unwind-protect
           (let ((payload (make-array 6 :element-type '(unsigned-byte 8)
                                        :initial-contents '(1 2 3 4 5 6)))
                 (buffer (make-array 16 :element-type '(unsigned-byte 8)
                                        :initial-element 0)))
             (expect (fd-write-octets wfd payload) :to-be 6)
             ;; LIMIT caps the read below the buffer length and what is available.
             (expect (fd-read-octets rfd buffer 3) :to-be 3)
             (expect (subseq buffer 0 3) :to-equalp #(1 2 3))
             ;; Zero-count early return leaves the remaining 4 5 6 in the pipe.
             (expect (fd-read-octets rfd buffer 0) :to-be 0)
             (expect (fd-read-octets rfd buffer) :to-be 3)
             (expect (subseq buffer 0 3) :to-equalp #(4 5 6)))
        (sb-unix:unix-close wfd)
        (sb-unix:unix-close rfd))))
  ;; FR-002: fd-write-octets short-write / non-blocking short-count contract.
  ;; A payload far larger than any pipe's kernel buffer cannot be written in one
  ;; shot on a non-blocking fd -- the first call fills the buffer and returns a
  ;; short count 0 < result < len. Draining the read end and resuming with the
  ;; remaining octets (subseq payload result) eventually writes every byte. This
  ;; is the multiplexer-critical resumable-write path.
  (it "resumes a short write by draining the read end and writing the remaining octets"
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
               (expect (< 0 first))
               (expect (< first len))
               (let ((total first))
                 (loop while (< total len)
                       repeat 100000
                       do ;; Fully drain the read end (a non-blocking read returns
                          ;; NIL once the buffer empties), then resume writing the
                          ;; leftover octets from where the previous call stopped.
                          (loop for n = (fd-read-octets rfd drain)
                                while (and n (plusp n)))
                          (let ((wrote (fd-write-octets wfd (subseq payload total))))
                            (expect (plusp wrote))
                            (incf total wrote)))
                 (expect total :to-be len))))
        (sb-unix:unix-close wfd)
        (sb-unix:unix-close rfd)))))

#+sbcl
(describe "PTY-FD after CLOSE-PTY"
  ;; FR-001: PTY-FD after CLOSE-PTY has cleared the stream signals a structured
  ;; failure rather than returning a stale descriptor.
  (it "signals a structured failure rather than returning a stale descriptor"
    (let ((closed-pty (make-pty :program "/bin/sh")))
      (close-pty closed-pty)
      (expect-pty-operation-failed (:fd closed-pty "PTY operation FD failed")
        (pty-fd closed-pty)))))

#+sbcl
(describe "fd-read-octets / fd-write-octets argument validation"
  ;; Validation: a non-octet buffer and a bad fd are wrapped as PTY-OPERATION-FAILED.
  (it "wraps a non-octet buffer and a bad fd as PTY-OPERATION-FAILED"
    (expect-pty-operation-failed (:fd-read nil "PTY operation FD-READ failed")
      (fd-read-octets 0 "not-a-buffer"))
    (expect-pty-operation-failed (:fd-write nil "PTY operation FD-WRITE failed")
      (fd-write-octets -1 (make-array 0 :element-type '(unsigned-byte 8)))))
  ;; A negative LIMIT is rejected before any syscall is attempted.
  (it "rejects a negative LIMIT before any syscall is attempted"
    (expect-pty-operation-failed (:fd-read nil "PTY operation FD-READ failed")
      (fd-read-octets 0 (make-array 1 :element-type '(unsigned-byte 8)) -1)))
  ;; A syntactically valid but unopened fd reaches the real syscall and
  ;; surfaces its OS error (EBADF), distinct from the EAGAIN/EINTR retry path.
  (it "surfaces the real OS error (EBADF) for a syntactically valid but unopened fd"
    (expect-pty-operation-failed (:fd-read nil "PTY operation FD-READ failed")
      (fd-read-octets 987654 (make-array 1 :element-type '(unsigned-byte 8))))
    (expect-pty-operation-failed (:fd-write nil "PTY operation FD-WRITE failed")
      (fd-write-octets 987654
                       (make-array 1 :element-type '(unsigned-byte 8)
                                     :initial-element 1))))
  ;; FR-002: fd-write-octets retries silently when unix-write is interrupted by
  ;; a signal (EINTR), the retry path a real syscall almost never exercises.
  (it "retries silently when unix-write is interrupted by EINTR"
    (let ((call-count 0))
      (with-function-overrides
          ((sb-unix:unix-write
             (lambda (fd octets offset len)
               (declare (ignore fd octets offset))
               (incf call-count)
               (if (= call-count 1)
                   (values nil sb-unix:eintr)
                   (values len nil)))))
        (expect (fd-write-octets 0 (make-array 3 :element-type '(unsigned-byte 8)
                                                  :initial-element 1))
                :to-be 3)
        (expect call-count :to-be 2))))
  ;; A fractional read limit is rejected before attempting I/O.
  (it "rejects a fractional LIMIT before attempting I/O"
    (expect-pty-operation-failed (:fd-read nil "PTY operation FD-READ failed")
      (fd-read-octets 0 (make-array 1 :element-type '(unsigned-byte 8)) 1.5))))

#+sbcl
(describe "fd-wait"
  (it "reports a timeout and then input readiness for a pipe"
    (multiple-value-bind (rfd wfd) (sb-unix:unix-pipe)
      (unwind-protect
           (progn
             (expect (fd-wait rfd :input 0) :to-be-falsy)
             (expect (fd-write-octets wfd
                                      (make-array 1 :element-type '(unsigned-byte 8)
                                                        :initial-element 65))
                     :to-be 1)
             (expect (fd-wait rfd :input 1) :to-be-truthy))
        (sb-unix:unix-close wfd)
        (sb-unix:unix-close rfd))))
  (it "validates direction, timeout, and descriptor before waiting"
    (expect-pty-operation-failed (:fd-wait nil "PTY operation FD-WAIT failed")
      (fd-wait -1 :input 0))
    (expect-pty-operation-failed (:fd-wait nil "PTY operation FD-WAIT failed")
      (fd-wait 0 :bad 0))
    (expect-pty-operation-failed (:fd-wait nil "PTY operation FD-WAIT failed")
      (fd-wait 0 :input -1))))
