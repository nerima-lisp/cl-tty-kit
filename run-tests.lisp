;;;; Lisp-level test entry point.
;;;;
;;;;     sbcl --script run-tests.lisp
;;;;
;;;; The org standard puts this file at the repository root (see
;;;; PACKAGE_STANDARD.md), because it is what flake.nix's `checks.default` and
;;;; `apps.test` invoke and what a reader looks for first. scripts/test.lisp
;;;; remains as a thin shim so the older documented command keeps working.
;;;;
;;;; scripts/bootstrap.lisp registers the project tree with ASDF, so this runs
;;;; from a plain checkout with no CL_SOURCE_REGISTRY set for cl-tty-kit
;;;; itself. Its test-only dependencies (cl-prolog, cl-weave) still come from
;;;; the environment, which flake.nix supplies.

(require :asdf)

(load (merge-pathnames #P"scripts/bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(defparameter *test-timeout-seconds* 120)

;; A hung test must fail the build rather than sit until the CI job's own
;; timeout, which reports "the job took 30 minutes" instead of naming the
;; suite that stopped making progress.
(defmacro with-test-timeout ((label) &body body)
  `(handler-case
       (sb-ext:with-timeout *test-timeout-seconds*
         ,@body)
     (sb-ext:timeout ()
       (error "~A timed out after ~D seconds"
              ,label
              *test-timeout-seconds*))))

;; Resolve through the package's external symbols rather than reading the
;; symbols at compile time: this file is loaded before cl-tty-kit/test exists,
;; so a direct reference would not read. Requiring :EXTERNAL also means an
;; accidental unexport fails here instead of silently calling an internal.
(defun call-exported-function (package-name symbol-name)
  (let* ((package (or (find-package package-name)
                      (error "Package ~A is not available." package-name)))
         (symbol (multiple-value-bind (symbol status)
                     (find-symbol symbol-name package)
                   (unless (eq status :external)
                     (error "Symbol ~A is not exported from ~A." symbol-name package-name))
                   symbol)))
    (funcall (symbol-function symbol))))

(with-test-timeout ("test suite")
  (call-exported-function "CL-TTY-KIT/BOOTSTRAP" "LOAD-TEST-SYSTEM")
  (call-exported-function "CL-TTY-KIT/TEST" "RUN-TESTS"))
