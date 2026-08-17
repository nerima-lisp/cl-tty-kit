;;;; Optional contrib system. NOT part of the core cl-tty-kit build or CI.
;;;;
;;;; A parser-combinator recognizer for the ECMA-48 CSI byte-class grammar,
;;;; built on nerima-lisp/cl-parser-kit -- a second, independent declarative
;;;; specification of the same grammar cl-tty-kit-cl-prolog-kit-csi-grammar
;;;; recognizes via cl-prolog-kit's DCG support. Load it explicitly from inside
;;;; a Nix dev shell, which puts cl-parser-kit on CL_SOURCE_REGISTRY (see
;;;; flake.nix devShells.default.shellHook):
;;;;
;;;;   nix develop
;;;;   (asdf:load-system :cl-tty-kit-cl-parser-kit-csi-grammar)

(asdf:defsystem #:cl-tty-kit-cl-parser-kit-csi-grammar
  :description "Parser-combinator recognizer for the ECMA-48 CSI grammar, built on nerima-lisp/cl-parser-kit."
  :author "nerima-lisp"
  :license "MIT"
  :depends-on (#:cl-parser-kit)
  :components ((:file "cl-parser-kit-csi-grammar")))
