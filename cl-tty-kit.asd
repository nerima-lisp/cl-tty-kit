;; nerima-lisp/cl-prolog and nerima-lisp/cl-weave (see docs/src/logic-engine.md
;; and t/sgr-prolog-oracle.lisp) are both used only by :CL-TTY-KIT/TEST below --
;; cl-prolog as a differential-testing oracle cross-checking the hand-written
;; SGR/CSI decoders, cl-weave as the test framework -- never by :CL-TTY-KIT
;; itself, which stays dependency-free (see its :DEPENDS-ON). Neither is
;; distributed by Quicklisp; `nix develop`/`nix build`/`nix flake check`
;; resolve both from this project's flake inputs onto CL_SOURCE_REGISTRY (see
;; flake.nix), which :INHERIT-CONFIGURATION below picks up. This system
;; registers its own directory tree before its :DEPENDS-ON is resolved, the
;; same way scripts/bootstrap.lisp does for every project script -- this makes
;; plain (asdf:load-system :cl-tty-kit) work standalone, independent of
;; whichever script or REPL loads this file first.
;;
;; This registers the directory through ASDF:*CENTRAL-REGISTRY*, NOT through
;; ASDF:INITIALIZE-SOURCE-REGISTRY. The latter replaces the source registry
;; outright, and :INHERIT-CONFIGURATION inherits the environment and user
;; configuration -- not a registry a caller has already installed
;; programmatically. Loading this file therefore used to erase the caller's
;; registry:
;;
;;   (asdf:initialize-source-registry '(:source-registry (:tree "/a/") ...))
;;   (asdf:initialize-source-registry '(:source-registry (:tree "/b/") ...))
;;   ;; systems under /a/ are now unfindable
;;
;; cl-cc-javascript hit this for real. Its cl-cc-repl system depends on
;; :CL-TTY-KIT and then :CL-BOUNDARY-KIT, so loading this file dropped the
;; entry that would have resolved the very next name in its own :DEPENDS-ON,
;; and the build failed with `Component :CL-BOUNDARY-KIT not found`. Under
;; CL_SOURCE_REGISTRY the damage is invisible, because an environment-provided
;; registry *is* inherited -- which is why nix builds here never showed it.
;;
;; Pushing onto *CENTRAL-REGISTRY* is additive and destroys nothing. ASDF
;; consults it before the source registry, so standalone
;; (asdf:load-system :cl-tty-kit) still works from a bare image.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (pushnew (uiop:pathname-directory-pathname *load-truename*)
           asdf:*central-registry*
           :test #'equal))

;;; System names are written as STRINGS, not #:symbols or :keywords: a string
;;; does not depend on the reader's package state at the moment this file is
;;; read, and it keeps `grep '"cl-tty-kit/test"'` reliable across the org.
(asdf:defsystem "cl-tty-kit"
  :description "A small Common Lisp terminal toolkit."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :homepage "https://github.com/nerima-lisp/cl-tty-kit"
  :bug-tracker "https://github.com/nerima-lisp/cl-tty-kit/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-tty-kit.git")
  :version "1.0.0"
  ;; SB-POSIX is only used by the SBCL-specific raw-mode layer (which requires
  ;; it itself under #+sbcl). Gating the dependency on the feature keeps ASDF
  ;; from failing dependency resolution with a confusing "system sb-posix not
  ;; found" on non-SBCL hosts; instead src/package.lisp reports a clear
  ;; SBCL-required error. See the README "Compatibility" section. This is the
  ;; toolkit's complete dependency set -- see the source-registry note above
  ;; for why CL-PROLOG belongs to :CL-TTY-KIT/TEST instead.
  :depends-on (#+sbcl #:sb-posix)
  :serial t
  :components ((:file "src/package")
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

(asdf:defsystem "cl-tty-kit/test"
  :description "Tests for cl-tty-kit."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "1.0.0"
  :homepage "https://github.com/nerima-lisp/cl-tty-kit"
  :bug-tracker "https://github.com/nerima-lisp/cl-tty-kit/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-tty-kit.git")
  :serial t
  :depends-on (#:cl-tty-kit #:cl-prolog #:cl-weave)
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
               (:file "t/screen-mutation")
               (:file "t/box")
               (:file "t/render-examples")
               (:file "t/render-core")
               (:file "t/sgr-prolog-oracle")
               (:file "t/render-diff")
               (:file "t/render")
               (:file "t/renderer")
               (:file "t/cursor")
               (:file "t/properties")))
