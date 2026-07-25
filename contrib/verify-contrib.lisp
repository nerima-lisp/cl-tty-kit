;;;; Verify the optional contrib integrations. Run from the project root
;;;; inside a Nix dev shell, which puts nerima-lisp/cl-prolog and
;;;; nerima-lisp/cl-weave on CL_SOURCE_REGISTRY (see flake.nix
;;;; devShells.default.shellHook):
;;;;
;;;;   nix develop --command sbcl --script contrib/verify-contrib.lisp
;;;;
;;;; It exercises clweb (via tangling the literate module) from Quicklisp,
;;;; plus the nerima-lisp/cl-prolog DCG grammar, the nerima-lisp/cl-parser-kit
;;;; combinator grammar, and nerima-lisp/cl-weave property tests. The
;;;; cl-prolog/cl-parser-kit/cl-weave checks are skipped, not failed, when
;;;; ASDF cannot find the relevant system (i.e. outside a Nix dev shell with
;;;; CL_SOURCE_REGISTRY pointed at none of them).

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

;;; --- nerima-lisp/cl-prolog DCG grammar --------------------------------------
(if (asdf:find-system :cl-prolog nil)
    (progn
      (handler-bind ((warning #'muffle-warning))
        (asdf:load-system :cl-tty-kit-cl-prolog-csi-grammar))
      (check "cl-prolog DCG grammar accepts a well-formed CSI body"
             (funcall (read-from-string "tty-csi-grammar:csi-sequence-valid-p")
                      "38;5;196m"))
      (check "cl-prolog DCG grammar rejects an unterminated CSI body"
             (not (funcall (read-from-string "tty-csi-grammar:csi-sequence-valid-p")
                           "1;1"))))
    (format t "~&[SKIP] cl-prolog not on CL_SOURCE_REGISTRY (run inside `nix develop`)~%"))

;;; --- nerima-lisp/cl-parser-kit combinator grammar ---------------------------
(if (asdf:find-system :cl-parser-kit nil)
    (progn
      (handler-bind ((warning #'muffle-warning))
        (asdf:load-system :cl-tty-kit-cl-parser-kit-csi-grammar))
      (check "cl-parser-kit combinator grammar accepts a well-formed CSI body"
             (funcall (read-from-string "tty-csi-parser-kit-grammar:csi-sequence-valid-p")
                      "38;5;196m"))
      (check "cl-parser-kit combinator grammar rejects an unterminated CSI body"
             (not (funcall (read-from-string "tty-csi-parser-kit-grammar:csi-sequence-valid-p")
                           "1;1")))
      ;; The two independent grammars -- Prolog DCG and parser combinators --
      ;; must agree whenever both are loaded, the same differential-testing
      ;; contract SGR-PROLOG-ORACLE holds against the hand-written decoder.
      (when (asdf:find-system :cl-prolog nil)
        (dolist (case '("1;1H" "38;5;196m" "?25h" "" "1;1" "1H2" "A" "9x;1"
                        ">0;276;0c" "1;1;104;200u"))
          (check (format nil "grammars agree on ~S" case)
                 (eq (and (funcall (read-from-string "tty-csi-grammar:csi-sequence-valid-p") case) t)
                     (and (funcall (read-from-string "tty-csi-parser-kit-grammar:csi-sequence-valid-p") case) t))))))
    (format t "~&[SKIP] cl-parser-kit not on CL_SOURCE_REGISTRY (run inside `nix develop`)~%"))

;;; --- nerima-lisp/cl-weave property tests ------------------------------------
(if (asdf:find-system :cl-weave nil)
    (progn
      (handler-bind ((warning #'muffle-warning))
        (asdf:load-system :cl-tty-kit-weave-tests))
      (check "cl-weave property-based decoder fuzz suite passes"
             (funcall (read-from-string "cl-tty-kit/weave-property-tests:run-tests"))))
    (format t "~&[SKIP] cl-weave not on CL_SOURCE_REGISTRY (run inside `nix develop`)~%"))

(format t "~&==CONTRIB-OK==~%")
