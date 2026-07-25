(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun streaming-paste-example ()
  "Decode a bracketed paste split across chunks, in continuation-passing
style via %DECODE-CHUNKS-CPS (bootstrap.lisp): each chunk is fed to the
decoder as if it just arrived from a live PTY or socket read, rather than
concatenated and decoded as one batch up front."
  (let ((events '()))
    (%decode-chunks-cps
     (%chunk-source (list (concatenate 'string (string #\Esc) "[200~he")
                          "llo"
                          (concatenate 'string (string #\Esc) "[201~")))
     (lambda (event) (push event events))
     (lambda ()))
    (nreverse events)))

(defun run-streaming-paste-example ()
  (dolist (event (streaming-paste-example))
    (format t "~S~%" event)))

(when *cl-tty-kit-run-example-on-load*
  (run-streaming-paste-example))
