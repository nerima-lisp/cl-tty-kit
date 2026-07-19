;;;; Verify the optional contrib integrations without requiring an external
;;;; Prolog binary. Run from the project root:
;;;;
;;;;   sbcl --script contrib/verify-contrib.lisp
;;;;
;;;; It exercises cl-prolog2 (via the bridge translation layer) and clweb (via
;;;; tangling the literate module), both at their current Quicklisp versions.

(require :asdf)
(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))

(defun check (label ok)
  (format t "~&[~A] ~A~%" (if ok "PASS" "FAIL") label)
  (unless ok (uiop:quit 1)))

(let ((root (uiop:ensure-directory-pathname (uiop:getcwd))))
  (asdf:initialize-source-registry
   `(:source-registry (:tree ,(namestring root)) :inherit-configuration))

  ;; --- cl-prolog2 bridge (advanced usage of cl-prolog, latest) ---------------
  (handler-bind ((warning #'muffle-warning))
    (funcall (read-from-string "ql:quickload") :cl-tty-kit-prolog-bridge :silent t))
  (let* ((db (funcall (read-from-string "tty-prolog:install-standard-primitives")
                      (funcall (read-from-string "tty-prolog:make-clause-db")))))
    (funcall (read-from-string "tty-prolog:add-clause") db '((parent abraham isaac)))
    (funcall (read-from-string "tty-prolog:add-clause") db '((parent isaac jacob)))
    (funcall (read-from-string "tty-prolog:add-clause")
             db '((ancestor ?a ?b) (parent ?a ?b)))
    (funcall (read-from-string "tty-prolog:add-clause")
             db '((ancestor ?a ?b) (parent ?a ?c) (ancestor ?c ?b)))
    (let ((rules (funcall (read-from-string "tty-prolog-bridge:clause-db-rules") db)))
      (check "cl-prolog2 bridge loads and translates clauses"
             (and (member '(parent abraham isaac) rules :test #'equal)
                  (member '(:- (ancestor ?a ?b) (parent ?a ?b)) rules :test #'equal)
                  (member '(:- (ancestor ?a ?b) (parent ?a ?c) (ancestor ?c ?b))
                          rules :test #'equal)))))

  ;; --- clweb literate module (advanced usage of cl-weave, latest) ------------
  (handler-bind ((warning #'muffle-warning))
    (funcall (read-from-string "ql:quickload") :clweb :silent t))
  (let* ((clw (merge-pathnames "contrib/literate/tty-relations.clw" root))
         (tangled (funcall (read-from-string "clweb:tangle-file") clw)))
    (check "clweb tangles the literate module" (probe-file tangled))
    (handler-bind ((warning #'muffle-warning)) (load tangled))
    (let ((fn (read-from-string "cl-tty-kit/literate:clause->prolog2-rule")))
      (check "tangled literate code runs"
             (and (equal '(parent abraham isaac)
                         (funcall fn '((parent abraham isaac))))
                  (equal '(:- (ancestor ?a ?b) (parent ?a ?b))
                         (funcall fn '((ancestor ?a ?b) (parent ?a ?b)))))))))

(format t "~&==CONTRIB-OK==~%")
