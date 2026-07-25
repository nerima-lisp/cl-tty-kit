;;;; Optional contrib system. NOT part of the core cl-tty-kit build or CI.
;;;;
;;;; Property-based fuzz tests built on nerima-lisp/cl-weave, exercising the
;;;; UTF-8 and input decoders against arbitrary octets plus the DCG-based CSI
;;;; grammar. Load and run it explicitly from inside a Nix dev shell, which
;;;; puts cl-prolog and cl-weave on CL_SOURCE_REGISTRY (see flake.nix
;;;; devShells.default.shellHook):
;;;;
;;;;   nix develop
;;;;   (asdf:load-system :cl-tty-kit-weave-tests)
;;;;   (cl-tty-kit/weave-property-tests:run-tests)

(asdf:defsystem #:cl-tty-kit-weave-tests
  :description "Property-based fuzz tests for cl-tty-kit, built on nerima-lisp/cl-weave."
  :author "nerima-lisp"
  :license "MIT"
  :depends-on (#:cl-tty-kit #:cl-weave #:cl-tty-kit-cl-prolog-csi-grammar)
  :components ((:file "weave-property-tests"))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (unless (uiop:symbol-call :cl-tty-kit/weave-property-tests :run-tests)
               (error "cl-tty-kit contrib cl-weave property suite failed."))))
