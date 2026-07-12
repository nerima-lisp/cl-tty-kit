(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun streaming-paste-example ()
  (let ((decoder (cl-tty-kit:make-input-decoder :collect-bracketed-paste t))
        (events '()))
    (dolist (chunk (list (concatenate 'string (string #\Esc) "[200~he")
                         "llo"
                         (concatenate 'string (string #\Esc) "[201~")))
      (setf events
            (nconc events
                   (copy-list (cl-tty-kit:decode-input-chunk decoder chunk)))))
    (nconc events
           (copy-list (cl-tty-kit:flush-input-decoder decoder)))))

(defun run-streaming-paste-example ()
  (dolist (event (streaming-paste-example))
    (format t "~S~%" event)))

(when *cl-tty-kit-run-example-on-load*
  (run-streaming-paste-example))
