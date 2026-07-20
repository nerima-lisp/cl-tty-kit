(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun styled-parse-example ()
  "Recover the text and style of each run from an ANSI-styled string.
Builds a styled log line with the attribute builders, then reverses it with
PARSE-STYLED-STRING (which decodes each SGR escape via DECODE-SGR)."
  (let* ((styled (concatenate
                  'string
                  (cl-tty-kit:style-ansi :bold (cl-tty-kit:style-fg 196))
                  "ERROR" (cl-tty-kit:ansi-reset-style)
                  " " (cl-tty-kit:style-ansi :underline)
                  "main.lisp" (cl-tty-kit:ansi-reset-style)
                  ":" (cl-tty-kit:style-ansi (cl-tty-kit:style-fg 33))
                  "42" (cl-tty-kit:ansi-reset-style)))
         (segments (cl-tty-kit:parse-styled-string styled)))
    (with-output-to-string (out)
      (format out "parsed ~D styled segments:~%" (length segments))
      (dolist (segment segments)
        (format out "  text=~S style=~S~%" (car segment) (cdr segment))))))

(defun run-styled-parse-example ()
  (format t "~A" (styled-parse-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-styled-parse-example))
