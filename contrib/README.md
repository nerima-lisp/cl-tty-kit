# cl-tty-kit contrib

Optional, opt-in integrations that layer external libraries on top of the core
toolkit. **Nothing here is part of the core `cl-tty-kit` build or CI** — the core
system keeps its single `sb-posix` dependency. These modules pull additional
libraries from Quicklisp, or from the vendored git submodules under
`vendor/`, and are loaded explicitly.

## `cl-tty-kit-cl-prolog-csi-grammar` — DCG grammar via nerima-lisp/cl-prolog

A declarative recognizer for the ECMA-48 CSI (Control Sequence Introducer)
byte-class grammar, built on [`nerima-lisp/cl-prolog`](https://github.com/nerima-lisp/cl-prolog)
(vendored at `vendor/cl-prolog`, pinned to its latest upstream HEAD — it is
not distributed by Quicklisp). `src/input-decode.lisp` already decodes CSI
sequences imperatively on the render loop's hot path; this module instead
expresses that same sequence shape — zero or more parameter bytes, then zero
or more intermediate bytes, then exactly one final byte — as a `def-dcg-rule`
grammar run through `phrase`, demonstrating cl-prolog's DCG support
independently of the hand-written decoder.

```lisp
(git submodule update --init vendor/cl-prolog) ; once, from the shell
(asdf:load-system :cl-tty-kit-cl-prolog-csi-grammar)

(tty-csi-grammar:csi-sequence-valid-p "1;1H")     ; => T   (cursor position)
(tty-csi-grammar:csi-sequence-valid-p "38;5;196m") ; => T   (SGR, 256-color fg)
(tty-csi-grammar:csi-sequence-valid-p "1;1")       ; => NIL (no final byte)
```

## `cl-tty-kit-weave-tests` — property-based fuzz tests via nerima-lisp/cl-weave

Property-based tests built on [`nerima-lisp/cl-weave`](https://github.com/nerima-lisp/cl-weave)
(vendored at `vendor/cl-weave`, pinned to its latest upstream HEAD — it is
not distributed by Quicklisp). `cl-weave`'s `it-property` generators
(`gen-vector`, `gen-string`, `gen-character`, ...) fuzz `src/utf8.lisp`'s
octet decoder and the public `cl-tty-kit:decode-input` entry point with
thousands of arbitrary byte sequences, asserting the documented contract:
malformed input always signals a `cl-tty-kit:tty-kit-error` condition and
never an undocumented Lisp error — the realistic threat model for decoders
that read attacker-controlled PTY bytes. It also regression-tests the DCG CSI
grammar above.

```lisp
(git submodule update --init vendor/cl-weave)  ; once, from the shell
(asdf:load-system :cl-tty-kit-weave-tests)
(cl-tty-kit/weave-property-tests:run-tests)    ; => T on success

;; Run more generated cases per property (default is cl-weave's own):
;;   CL_WEAVE_PROPERTY_TESTS=2000 sbcl --script contrib/verify-contrib.lisp
```

## `cl-tty-kit-prolog-bridge` — external ISO Prolog via cl-prolog2

Bridges cl-tty-kit's embedded logic engine (`cl-tty-kit/prolog`) to a full
external ISO Prolog through [`cl-prolog2`](https://github.com/cl-model-languages/cl-prolog2)
(latest Quicklisp release). The embedded engine is a compact in-image CPS
resolver; delegating to swipl/gprolog/yap adds ISO built-ins (arithmetic, cut,
findall, I/O) when a terminal app outgrows it. Both engines already spell logic
variables as `?`-prefixed symbols, so clause translation is a direct rewrite.

```lisp
(ql:quickload :cl-tty-kit-prolog-bridge)

(let ((db (tty-prolog:install-standard-primitives (tty-prolog:make-clause-db))))
  (tty-prolog:define-clauses db
    ((parent abraham isaac))
    ((parent isaac jacob))
    ((ancestor ?a ?b) (parent ?a ?b))
    ((ancestor ?a ?b) (parent ?a ?c) (ancestor ?c ?b)))

  ;; Pure translation to cl-prolog2 rule sexps (no external binary needed):
  (tty-prolog-bridge:clause-db-rules db)
  ;; => ((PARENT ABRAHAM ISAAC) (PARENT ISAAC JACOB)
  ;;     (:- (ANCESTOR ?A ?B) (PARENT ?A ?B))
  ;;     (:- (ANCESTOR ?A ?B) (PARENT ?A ?C) (ANCESTOR ?C ?B)))

  ;; Run the whole database on swipl (requires the swipl binary on PATH):
  (tty-prolog-bridge:run-clause-db-query db '(ancestor abraham ?d) '?d :prolog :swi))
```

## `contrib/literate/tty-relations.clw` — literate source via clweb

A literate program written for [`clweb`](https://github.com/plotnick/clweb), the
Common Lisp descendant of Knuth's WEB (the CL "weave" tool), at its latest
Quicklisp release. It documents the clause→ISO-Prolog rewrite and tangles to
loadable Lisp.

```lisp
(ql:quickload :clweb)
(clweb:tangle-file "contrib/literate/tty-relations.clw") ; -> tty-relations.lisp
(clweb:weave       "contrib/literate/tty-relations.clw") ; -> tty-relations.tex
```

## Verifying the contrib

`contrib/verify-contrib.lisp` exercises the Quicklisp-backed integrations
(bridge translation + clweb tangle) without needing an external Prolog
binary, and additionally exercises the two vendored integrations above when
their submodules are checked out (skipped, not failed, otherwise):

```bash
git submodule update --init vendor/cl-prolog vendor/cl-weave  # optional
sbcl --script contrib/verify-contrib.lisp
```
