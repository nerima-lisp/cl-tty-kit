;;;; Optional contrib system. NOT part of the core cl-tty-kit build or CI.
;;;;
;;;; A DCG-based recognizer for the ECMA-48 CSI byte-class grammar, built on
;;;; the vendored takeokunn/cl-prolog (vendor/cl-prolog, latest HEAD). Load it
;;;; explicitly once the submodule is checked out:
;;;;
;;;;   git submodule update --init vendor/cl-prolog
;;;;   (asdf:load-system :cl-tty-kit-cl-prolog-csi-grammar)

(asdf:defsystem #:cl-tty-kit-cl-prolog-csi-grammar
  :description "DCG recognizer for the ECMA-48 CSI grammar, built on takeokunn/cl-prolog."
  :author "takeokunn"
  :license "MIT"
  :depends-on (#:cl-prolog)
  :components ((:file "cl-prolog-csi-grammar")))
