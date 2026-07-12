(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun key-decoding-example ()
  (cl-tty-kit:decode-input (concatenate 'string
                                        "a"
                                        (string (code-char 3))
                                        (string #\Esc) "[A"
                                        (string #\Esc) "[105;6u"
                                        (string #\Esc) "[200~"
                                        (string #\Esc) "[201~"
                                        (string #\Esc) "[Z"
                                        (string #\Esc) "[57363;3u"
                                        (string #\Esc) "OA"
                                        (string #\Esc) "x")))

(defun run-key-decoding-example ()
  (dolist (event (key-decoding-example))
    (format t "~S~%" event)))

(when *cl-tty-kit-run-example-on-load*
  (run-key-decoding-example))
