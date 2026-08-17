;;;; Lisp-level test entry point.
;;;;
;;;;     sbcl --script run-tests.lisp
;;;;
;;;; The org standard puts this file at the repository root (see
;;;; PACKAGE_STANDARD.md), because it is what flake.nix's `checks.default` and
;;;; `apps.test` invoke and what a reader looks for first. This is the sole
;;;; supported Lisp-level test entry point.
;;;;
;;;; scripts/bootstrap.lisp registers the project tree with ASDF, so this runs
;;;; from a plain checkout with no CL_SOURCE_REGISTRY set for cl-tty-kit
;;;; itself. Its test-only dependencies (cl-prolog-kit, cl-weave) still come from
;;;; the environment, which flake.nix supplies.
(require :asdf)

(load
  (merge-pathnames
    #P"scripts/bootstrap.lisp"
    (uiop:pathname-directory-pathname *load-truename*)))

;; Resolve through the package's external symbols rather than reading the
;; symbols at compile time: this file is loaded before cl-tty-kit/test exists,
;; so a direct reference would not read. Requiring :EXTERNAL also means an
;; accidental unexport fails here instead of silently calling an internal.
(progn
  (cl-tty-kit/bootstrap:with-script-timeout
    ("test suite" 120)
    (cl-tty-kit/bootstrap:call-exported-function "CL-TTY-KIT/BOOTSTRAP" "LOAD-TEST-SYSTEM")
    (cl-tty-kit/bootstrap:call-exported-function "CL-TTY-KIT/TEST" "RUN-TESTS"))
  (uiop:quit 0))
