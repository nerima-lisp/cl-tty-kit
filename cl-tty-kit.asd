(asdf:defsystem #:cl-tty-kit
  :description "A small, low-dependency Common Lisp terminal toolkit."
  :author "takeokunn"
  :maintainer "takeokunn"
  :license "MIT"
  :homepage "https://github.com/nerima-lisp/cl-tty-kit"
  :bug-tracker "https://github.com/nerima-lisp/cl-tty-kit/issues"
  :source-control "git https://github.com/nerima-lisp/cl-tty-kit.git"
  :version "0.4.0"
  ;; SB-POSIX is only used by the SBCL-specific raw-mode layer (which requires
  ;; it itself under #+sbcl). Gating the dependency on the feature keeps ASDF
  ;; from failing dependency resolution with a confusing "system sb-posix not
  ;; found" on non-SBCL hosts; instead src/package.lisp reports a clear
  ;; SBCL-required error. See the README "Compatibility" section.
  :depends-on (#+sbcl #:sb-posix)
  :serial t
  :components ((:file "src/package")
               (:file "src/prolog-package")
               (:file "src/prolog-bindings")
               (:file "src/prolog-db")
               (:file "src/prolog-engine")
               (:file "src/prolog-primitives")
               (:file "src/conditions")
               (:file "src/clamp")
               (:file "src/string-empty")
               (:file "src/utf8")
               (:file "src/char-width-data")
               (:file "src/char-width")
               (:file "src/text-layout")
               (:file "src/color")
               (:file "src/format")
               (:file "src/rect")
               (:file "src/ansi")
               (:file "src/ansi-control")
               (:file "src/ansi-osc")
               (:file "src/sixel")
               (:file "src/raw-mode")
               (:file "src/raw-mode-sbcl")
               (:file "src/terminal-size")
               (:file "src/session")
               (:file "src/key-tables")
               (:file "src/keys")
               (:file "src/mouse")
               (:file "src/keys-decode-internals")
               (:file "src/keys-decode")
               (:file "src/input-state")
               (:file "src/input-decode-internals")
               (:file "src/input-decode")
               (:file "src/cell")
               (:file "src/screen")
               (:file "src/screen-regions")
               (:file "src/box")
               (:file "src/screen-text")
               (:file "src/cursor")
               (:file "src/render-style")
               (:file "src/sgr-parse")
               (:file "src/render-commands")
               (:file "src/render-diff")
               (:file "src/render")
               (:file "src/renderer")
               (:file "src/pty")
               (:file "src/pty-fd"))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (asdf:load-system :cl-tty-kit/test)
             (uiop:symbol-call :cl-tty-kit/test :run-tests)))

(asdf:defsystem #:cl-tty-kit/test
  :description "Tests for cl-tty-kit."
  :author "takeokunn"
  :license "MIT"
  :serial t
  :depends-on (#:cl-tty-kit #:cl-weave)
  :components ((:file "t/package")
               (:file "t/package-data")
               (:file "t/suite")
               (:file "t/package-introspection")
               (:file "t/package-readme")
               (:file "t/ansi")
               (:file "t/conditions")
               (:file "t/prolog-cases")
               (:file "t/prolog-support")
               (:file "t/prolog-queries")
               (:file "t/prolog-unification")
               (:file "t/prolog-primitives")
               (:file "t/prolog-db")
               (:file "t/text-layout")
               (:file "t/color")
               (:file "t/format")
               (:file "t/rect")
               (:file "t/keys")
               (:file "t/input-data")
               (:file "t/input")
               (:file "t/mouse")
               (:file "t/utf8")
               (:file "t/raw-mode")
               (:file "t/session")
               (:file "t/pty")
               (:file "t/screen")
               (:file "t/box")
               (:file "t/render-examples")
               (:file "t/render-core")
               (:file "t/sgr-prolog-oracle")
               (:file "t/render-diff")
               (:file "t/render")
               (:file "t/renderer")
               (:file "t/cursor")
               (:file "t/properties")))
