;;;; Verify the optional contrib integrations. Run from the project root:
;;;;
;;;;   git submodule update --init vendor/cl-prolog vendor/cl-weave
;;;;   sbcl --script contrib/verify-contrib.lisp
;;;;
;;;; It exercises clweb (via tangling the literate module) from Quicklisp,
;;;; plus the vendored nerima-lisp/cl-prolog DCG grammar and nerima-lisp/cl-weave
;;;; property tests from vendor/ (both pinned at their latest upstream HEAD;
;;;; see .gitmodules). The vendored checks are skipped, not failed, when the
;;;; submodules have not been checked out.

(require :asdf)
(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))

(defun check (label ok)
  (format t "~&[~A] ~A~%" (if ok "PASS" "FAIL") label)
  (unless ok (uiop:quit 1)))

(defparameter *root* (uiop:ensure-directory-pathname (uiop:getcwd)))

(asdf:initialize-source-registry
 `(:source-registry (:tree ,(namestring *root*)) :inherit-configuration))

;;; --- clweb literate module (Quicklisp, latest release) ---------------------
(handler-bind ((warning #'muffle-warning))
  (funcall (read-from-string "ql:quickload") :clweb :silent t))
(let* ((clw (merge-pathnames "contrib/literate/tty-relations.clw" *root*))
       (tangled (funcall (read-from-string "clweb:tangle-file") clw)))
  (check "clweb tangles the literate module" (probe-file tangled))
  (handler-bind ((warning #'muffle-warning)) (load tangled))
  (let ((fn (read-from-string "cl-tty-kit/literate:clause->prolog2-rule")))
    (check "tangled literate code runs"
           (and (equal '(parent abraham isaac)
                       (funcall fn '((parent abraham isaac))))
                (equal '(:- (ancestor ?a ?b) (parent ?a ?b))
                       (funcall fn '((ancestor ?a ?b) (parent ?a ?b))))))))

;;; --- vendored nerima-lisp/cl-prolog DCG grammar (vendor/, latest HEAD) -------
(if (probe-file (merge-pathnames "vendor/cl-prolog/cl-prolog.asd" *root*))
    (progn
      (handler-bind ((warning #'muffle-warning))
        (asdf:load-system :cl-tty-kit-cl-prolog-csi-grammar))
      (check "vendor/cl-prolog DCG grammar accepts a well-formed CSI body"
             (funcall (read-from-string "tty-csi-grammar:csi-sequence-valid-p")
                      "38;5;196m"))
      (check "vendor/cl-prolog DCG grammar rejects an unterminated CSI body"
             (not (funcall (read-from-string "tty-csi-grammar:csi-sequence-valid-p")
                           "1;1"))))
    (format t "~&[SKIP] vendor/cl-prolog not checked out (git submodule update --init)~%"))

;;; --- vendored nerima-lisp/cl-weave property tests (vendor/, latest HEAD) -----
(if (probe-file (merge-pathnames "vendor/cl-weave/cl-weave.asd" *root*))
    (progn
      (handler-bind ((warning #'muffle-warning))
        (asdf:load-system :cl-tty-kit-weave-tests))
      (check "vendor/cl-weave property-based decoder fuzz suite passes"
             (funcall (read-from-string "cl-tty-kit/weave-property-tests:run-tests"))))
    (format t "~&[SKIP] vendor/cl-weave not checked out (git submodule update --init)~%"))

(format t "~&==CONTRIB-OK==~%")
