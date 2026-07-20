(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun %mouse-report (cb cx cy final)
  (format nil "~C[<~D;~D;~D~C" #\Esc cb cx cy final))

(defun mouse-decoding-example ()
  "Decode a spread of SGR mouse reports into their structured events."
  (let ((reports (list (%mouse-report 0 5 2 #\M)     ; left press
                       (%mouse-report 0 5 2 #\m)     ; left release
                       (%mouse-report 2 10 4 #\M)    ; right press
                       (%mouse-report 64 7 7 #\M)    ; wheel up
                       (%mouse-report 32 3 3 #\M)))) ; left drag (motion)
    (with-output-to-string (out)
      (dolist (report reports)
        (multiple-value-bind (event consumed)
            (cl-tty-kit:decode-mouse-sequence report)
          (declare (ignore consumed))
          (format out "~A ~A at (~D,~D) mods ~A~%"
                  (cl-tty-kit:mouse-event-button event)
                  (cl-tty-kit:mouse-event-action event)
                  (cl-tty-kit:mouse-event-x event)
                  (cl-tty-kit:mouse-event-y event)
                  (cl-tty-kit:mouse-event-modifiers event)))))))

(defun run-mouse-decoding-example ()
  (format t "~A" (mouse-decoding-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-mouse-decoding-example))
