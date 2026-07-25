(load (merge-pathnames #P"../scripts/bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(unless (find-package :cl-tty-kit)
  (cl-tty-kit/bootstrap:load-core-system))

(defun %chunk-source (chunks)
  "Return a thunk producing each of CHUNKS in turn, then NIL.
Shared by the examples that decode a fixed list of chunks incrementally
(event-loop.lisp, streaming-paste.lisp): stands in for a live read from a
PTY or stdin, so %DECODE-CHUNKS-CPS below can only ever ask for the next
chunk, never inspect \"the rest of the input\", because in a real event loop
there is no such thing until this thunk decides to produce it."
  (lambda ()
    (when chunks
      (pop chunks))))

(defun %decode-chunks-cps (chunk-source on-event on-done)
  "Feed CHUNK-SOURCE's output through an incremental CL-TTY-KIT input
decoder, in continuation-passing style: ON-EVENT is called with each decoded
KEY-EVENT as soon as it is available, and ON-DONE once with no arguments
after the final chunk is flushed. This is the shape a real event loop over a
live PTY or socket must take -- it drives itself forward chunk by chunk
rather than decoding a whole batch up front -- so these examples take it
too, even though their CHUNK-SOURCE happens to be backed by a fixed list."
  (let ((decoder (cl-tty-kit:make-input-decoder :collect-bracketed-paste t)))
    (labels ((step-loop ()
               (let ((chunk (funcall chunk-source)))
                 (if chunk
                     (progn
                       (dolist (event (cl-tty-kit:decode-input-chunk decoder chunk))
                         (funcall on-event event))
                       (step-loop))
                     (progn
                       (dolist (event (cl-tty-kit:flush-input-decoder decoder))
                         (funcall on-event event))
                       (funcall on-done))))))
      (step-loop))))
