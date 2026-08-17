;;;; Optional contrib system. NOT part of the core cl-tty-kit build or CI.
;;;;
;;;; Mutation tests built on nerima-lisp/cl-weave: mutate a pure function's
;;;; body (read live from its SRC/ source file) and confirm the same case
;;;; battery a unit test would use kills every mutation. This measures
;;;; whether the tests actually notice a wrong implementation, which
;;;; SB-COVER line/branch coverage alone cannot show. Load and run it
;;;; explicitly from inside a Nix dev shell, which puts cl-prolog-kit and
;;;; cl-weave on CL_SOURCE_REGISTRY (see flake.nix
;;;; devShells.default.shellHook):
;;;;
;;;;   nix develop
;;;;   (asdf:load-system :cl-tty-kit-weave-mutation-tests)
;;;;   (cl-tty-kit/weave-mutation-tests:run-tests)

(asdf:defsystem #:cl-tty-kit-weave-mutation-tests
  :description "Mutation tests for cl-tty-kit, built on nerima-lisp/cl-weave."
  :author "nerima-lisp"
  :license "MIT"
  :depends-on (#:cl-tty-kit #:cl-weave)
  :components ((:file "weave-mutation-tests"))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (unless (uiop:symbol-call :cl-tty-kit/weave-mutation-tests :run-tests)
               (error "cl-tty-kit contrib cl-weave mutation suite failed."))))
