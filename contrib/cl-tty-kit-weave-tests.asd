;;;; Optional contrib system. NOT part of the core cl-tty-kit build or CI.
;;;;
;;;; Property-based fuzz tests built on the vendored takeokunn/cl-weave
;;;; (vendor/cl-weave, latest HEAD), exercising the UTF-8 and input decoders
;;;; against arbitrary octets plus the DCG-based CSI grammar. Load and run it
;;;; explicitly once the submodules are checked out:
;;;;
;;;;   git submodule update --init vendor/cl-prolog vendor/cl-weave
;;;;   (asdf:load-system :cl-tty-kit-weave-tests)
;;;;   (cl-tty-kit/weave-property-tests:run-tests)

(asdf:defsystem #:cl-tty-kit-weave-tests
  :description "Property-based fuzz tests for cl-tty-kit, built on takeokunn/cl-weave."
  :author "takeokunn"
  :license "MIT"
  :depends-on (#:cl-tty-kit #:cl-weave #:cl-tty-kit-cl-prolog-csi-grammar)
  :components ((:file "weave-property-tests"))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (unless (uiop:symbol-call :cl-tty-kit/weave-property-tests :run-tests)
               (error "cl-tty-kit contrib cl-weave property suite failed."))))
