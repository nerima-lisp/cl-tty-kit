(in-package #:cl-tty-kit)

#+sb-thread
(defun call-with-input-monitor (fd function on-event &key on-finish)
  "Run FUNCTION on the caller while a helper monitors terminal FD.
Return the exact octets read, in order, and FUNCTION's multiple values as a
list. ON-EVENT receives each decoded event on the helper thread, using a
private decoder that collects bracketed paste. ON-FINISH, when supplied,
receives the same octet vector on the caller after the helper has joined,
including when FUNCTION exits nonlocally. A helper error is re-signaled on
the caller after a normal return from FUNCTION; a nonlocal exit takes priority.

The caller must exclusively own reads from FD for this scope and keep FD open.
Callbacks must return promptly without blocking: the helper waits at most 20ms
per poll and stops and joins within 50ms under that precondition, excluding OS
scheduling delays. The helper does not flush partial UTF-8, escape, or paste
input when it stops; those raw bytes remain in the returned vector. FD is not
closed and its blocking mode is unchanged."
  (%assert-fd fd)
  (dolist (callback (list function on-event))
    (unless (or (functionp callback) (and (symbolp callback) (fboundp callback)))
      (error "Input monitor callback must be a function designator, got ~S." callback)))
  (when (and on-finish
             (not (or (functionp on-finish)
                      (and (symbolp on-finish) (fboundp on-finish)))))
    (error "Input monitor finish callback must be a function designator, got ~S."
           on-finish))
  (let ((lock (cl-concurrent-kit:make-lock :name "cl-tty-kit input monitor"))
        (stopped nil)
        (thread nil)
        (chunks nil)
        (size 0)
        (failure nil)
        (octets nil)
        (body-values nil))
    (labels ((stopped-p ()
               (cl-concurrent-kit:with-lock-held (lock) stopped))
             (monitor ()
               (handler-case
                   (let ((decoder (make-input-decoder :collect-bracketed-paste t))
                         (buffer (make-array 4096 :element-type '(unsigned-byte 8))))
                     (loop until (stopped-p)
                           do (when (fd-wait fd :input 0.02)
                                (unless (stopped-p)
                                  (let ((chunk nil)
                                        (eof nil))
                                    ;; Never expose a successful read without
                                    ;; recording its bytes for the caller.
                                    (sb-sys:without-interrupts
                                      (let ((count (fd-read-octets fd buffer)))
                                        (cond
                                          ((null count) nil)
                                          ((zerop count) (setf eof t))
                                          (t (setf chunk (subseq buffer 0 count))
                                             (push chunk chunks)
                                             (incf size count)))))
                                    (when eof (return))
                                    (when chunk
                                      (dolist (event (decode-input-chunk decoder chunk))
                                        (when (stopped-p) (return))
                                        (funcall on-event event))))))))
                 (error (condition) (setf failure condition)))))
      ;; Establish cleanup before creation and publish the thread handle before
      ;; allowing an asynchronous exit from the caller.
      (sb-sys:without-interrupts
        (unwind-protect
             (progn
               (setf thread (cl-concurrent-kit:make-thread
                              #'monitor :name "cl-tty-kit input monitor"))
               (setf body-values
                     (multiple-value-list
                       (sb-sys:with-local-interrupts (funcall function)))))
          (cl-concurrent-kit:with-lock-held (lock) (setf stopped t))
          (when thread (cl-concurrent-kit:join-thread thread))
          (setf octets (make-array size :element-type '(unsigned-byte 8)))
          (loop with offset = 0
                for chunk in (nreverse chunks)
                do (replace octets chunk :start1 offset)
                   (incf offset (length chunk)))
          (when on-finish (funcall on-finish octets))))
      (when failure (error failure))
      (values octets body-values))))

#-sb-thread
(defun call-with-input-monitor (fd function on-event &key on-finish)
  "Monitor terminal input while FUNCTION runs; requires SBCL thread support."
  (declare (ignore fd function on-event on-finish))
  (error 'unsupported-feature :feature :input-monitor))
