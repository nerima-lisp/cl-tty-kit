;;;; Optional contrib system. NOT part of the core cl-tty-kit build or CI.
;;;;
;;;; A DCG-based recognizer for the ECMA-48 CSI byte-class grammar, built on
;;;; nerima-lisp/cl-prolog. Load it explicitly from inside a Nix dev shell,
;;;; which puts cl-prolog on CL_SOURCE_REGISTRY (see flake.nix
;;;; devShells.default.shellHook):
;;;;
;;;;   nix develop
;;;;   (asdf:load-system :cl-tty-kit-cl-prolog-csi-grammar)

(asdf:defsystem #:cl-tty-kit-cl-prolog-csi-grammar
  :description "DCG recognizer for the ECMA-48 CSI grammar, built on nerima-lisp/cl-prolog."
  :author "nerima-lisp"
  :license "MIT"
  :depends-on (#:cl-prolog)
  :components ((:file "cl-prolog-csi-grammar")))
