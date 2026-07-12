(asdf:defsystem #:cl-tty-kit
  :description "A small, low-dependency Common Lisp terminal toolkit."
  :author "takeokunn"
  :maintainer "takeokunn"
  :license "MIT"
  :homepage "https://github.com/takeokunn/cl-tty-kit"
  :bug-tracker "https://github.com/takeokunn/cl-tty-kit/issues"
  :source-control "git https://github.com/takeokunn/cl-tty-kit.git"
  :version "0.1.0"
  :depends-on (#:sb-posix)
  :serial t
  :components ((:file "src/package")
    (:file "src/prolog-bindings")
    (:file "src/prolog-db")
    (:file "src/prolog-engine")
    (:file "src/prolog-primitives")
    (:file "src/conditions")
    (:file "src/clamp")
    (:file "src/string-empty")
    (:file "src/output-utils")
    (:file "src/utf8")
    (:file "src/char-width-data")
    (:file "src/char-width")
    (:file "src/ansi")
    (:file "src/raw-mode")
    (:file "src/raw-mode-sbcl")
    (:file "src/session")
    (:file "src/key-tables")
    (:file "src/keys")
    (:file "src/keys-decode-internals")
    (:file "src/keys-decode")
    (:file "src/input-state")
    (:file "src/input-decode-internals")
    (:file "src/input-decode")
    (:file "src/cell")
    (:file "src/screen")
    (:file "src/cursor")
    (:file "src/render-style")
    (:file "src/render-commands")
    (:file "src/render-diff")
    (:file "src/render")
    (:file "src/pty"))
  :perform (asdf:test-op
    (op system)
    (declare (ignore op system))
    (asdf:load-system :cl-tty-kit/test)
    (uiop:symbol-call :cl-tty-kit/test :run-tests)))

(asdf:defsystem #:cl-tty-kit/test
  :description "Tests for cl-tty-kit."
  :author "takeokunn"
  :license "MIT"
  :serial t
  :depends-on (#:cl-tty-kit)
  :components ((:file "t/package")
    (:file "t/package-data")
    (:file "t/package-introspection")
    (:file "t/package-readme")
    (:file "t/suite")
    (:file "t/ansi")
    (:file "t/conditions")
    (:file "t/prolog-cases")
    (:file "t/prolog-support")
    (:file "t/prolog-queries")
    (:file "t/prolog-unification")
    (:file "t/prolog-primitives")
    (:file "t/prolog-db")
    (:file "t/keys")
    (:file "t/input-data")
    (:file "t/input")
    (:file "t/utf8")
    (:file "t/raw-mode")
    (:file "t/session")
    (:file "t/pty")
    (:file "t/screen")
    (:file "t/render-examples")
    (:file "t/render-core")
    (:file "t/render-diff")
    (:file "t/render")
    (:file "t/cursor")))
