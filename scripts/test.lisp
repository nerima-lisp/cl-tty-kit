;;;; Compatibility shim. The test entry point moved to the repository root as
;;;; run-tests.lisp, which is where the org standard puts it (see
;;;; PACKAGE_STANDARD.md) and what flake.nix's `checks.default` and `apps.test`
;;;; invoke.
;;;;
;;;; This file stays because `sbcl --script scripts/test.lisp` is printed in
;;;; released CHANGELOG entries and in the 1.0.0 docs; removing it would break
;;;; those instructions with a bare "file not found" rather than a redirect.

(require :asdf)

(load (merge-pathnames #P"../run-tests.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))
