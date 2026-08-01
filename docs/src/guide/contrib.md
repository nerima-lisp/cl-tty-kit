# Optional Integrations (`contrib/`)

`contrib/` holds optional, opt-in integrations that layer external libraries
on top of the core toolkit. **Nothing here is part of the core `cl-tty-kit`
build or CI** — `:cl-tty-kit` has no ASDF dependencies; its SBCL-only
raw-mode implementation loads the bundled `sb-posix` contrib with `require`
(see [Compatibility](../reference/compatibility.md)). These modules pull additional
libraries from Quicklisp, or from `nerima-lisp/cl-prolog`,
`nerima-lisp/cl-weave`, and `nerima-lisp/cl-parser-kit` via this repository's
`flake.nix` (`nix develop` puts all three on `CL_SOURCE_REGISTRY`, the same
as `:cl-tty-kit/test`), and must be loaded explicitly.

!!! note "Why isolate these from core CI"

    `.github/workflows/ci.yml` runs `contrib/verify-contrib.lisp` in its own
    `contrib` job with `continue-on-error: true`. Quicklisp installs
    introduce a network dependency that a core language toolkit's build
    should never require — a flaky network never blocks a core merge, and a
    contrib regression never blocks a core release.

## `cl-tty-kit-cl-prolog-csi-grammar` — DCG grammar via `nerima-lisp/cl-prolog`

A declarative recognizer for the ECMA-48 CSI (Control Sequence Introducer)
byte-class grammar, built on
[`nerima-lisp/cl-prolog`](https://github.com/nerima-lisp/cl-prolog)
(pulled from this repository's `flake.nix` inputs — it is not distributed by
Quicklisp). [Input Decoding](input-decoding.md) already decodes CSI sequences
imperatively on the render loop's hot path; this module instead expresses
that same sequence shape — zero or more parameter bytes, then zero or more
intermediate bytes, then exactly one final byte — as a `def-dcg-rule`
grammar run through `phrase`, demonstrating cl-prolog's DCG support
independently of the hand-written decoder.

```lisp
;; nix develop  -- puts cl-prolog on CL_SOURCE_REGISTRY, once per shell
(asdf:load-system :cl-tty-kit-cl-prolog-csi-grammar)

(tty-csi-grammar:csi-sequence-valid-p "1;1H")      ; => T   (cursor position)
(tty-csi-grammar:csi-sequence-valid-p "38;5;196m")  ; => T   (SGR, 256-color fg)
(tty-csi-grammar:csi-sequence-valid-p "1;1")        ; => NIL (no final byte)
```

## `cl-tty-kit-cl-parser-kit-csi-grammar` — combinator grammar via `nerima-lisp/cl-parser-kit`

A second, independent declarative recognizer for the same ECMA-48 CSI grammar
as the DCG version above, built on
[`nerima-lisp/cl-parser-kit`](https://github.com/nerima-lisp/cl-parser-kit)'s
`seq`/`many`/`type-token` parser combinators instead of cl-prolog's DCG rules
(pulled from this repository's `flake.nix` inputs — it is not distributed by
Quicklisp). `contrib/verify-contrib.lisp` cross-checks the two grammars agree
on every case, the same differential-testing shape
[the SGR oracle](logic-engine.md#a-real-example-the-sgr-oracle) uses against
the hand-written decoder.

```lisp
;; nix develop  -- puts cl-parser-kit on CL_SOURCE_REGISTRY, once per shell
(asdf:load-system :cl-tty-kit-cl-parser-kit-csi-grammar)

(tty-csi-parser-kit-grammar:csi-sequence-valid-p "1;1H")      ; => T   (cursor position)
(tty-csi-parser-kit-grammar:csi-sequence-valid-p "38;5;196m") ; => T   (SGR, 256-color fg)
(tty-csi-parser-kit-grammar:csi-sequence-valid-p "1;1")       ; => NIL (no final byte)
```

## `cl-tty-kit-weave-tests` — property-based fuzz tests via `nerima-lisp/cl-weave`

Property-based tests built on
[`nerima-lisp/cl-weave`](https://github.com/nerima-lisp/cl-weave) (pulled
from this repository's `flake.nix` inputs — it is not distributed by
Quicklisp). `cl-weave`'s `it-property` generators
(`gen-vector`, `gen-string`, `gen-character`, ...) fuzz the UTF-8 octet
decoder and the public `cl-tty-kit:decode-input` entry point
(see [Input Decoding](input-decoding.md)) with thousands of arbitrary byte
sequences, asserting the documented contract: malformed input always signals
a `cl-tty-kit:tty-kit-error` condition (see [Conditions](../reference/conditions.md)) and
never an undocumented Lisp error — the realistic threat model for decoders
that read attacker-controlled PTY bytes. It also regression-tests the DCG CSI
grammar above.

```lisp
;; nix develop  -- puts cl-prolog and cl-weave on CL_SOURCE_REGISTRY, once per shell
(asdf:load-system :cl-tty-kit-weave-tests)
(cl-tty-kit/weave-property-tests:run-tests)    ; => T on success

;; Run more generated cases per property (default is cl-weave's own):
;;   CL_WEAVE_PROPERTY_TESTS=2000 sbcl --script contrib/verify-contrib.lisp
```

## `contrib/literate/tty-relations.clw` — literate source via `clweb`

A literate program written for [`clweb`](https://github.com/plotnick/clweb),
the Common Lisp descendant of Knuth's WEB (the CL "weave" tool), at its
latest Quicklisp release. It documents the rewrite from a Lisp-shaped
`(head . body)` clause (the same clause shape [the logic engine](logic-engine.md)
uses) to a [`cl-prolog2`](https://github.com/cl-model-languages/cl-prolog2)
ISO rule sexp — useful for running such clauses, however sourced, against a
full external ISO Prolog (swipl/gprolog/yap) — and tangles to loadable Lisp.

```lisp
(ql:quickload :clweb)
(clweb:tangle-file "contrib/literate/tty-relations.clw") ; -> tty-relations.lisp
(clweb:weave       "contrib/literate/tty-relations.clw") ; -> tty-relations.tex
```

## Verifying the contrib

`contrib/verify-contrib.lisp` exercises the Quicklisp-backed clweb tangle
integration, and additionally exercises the cl-prolog/cl-parser-kit/cl-weave
integrations above when ASDF can find the relevant system (skipped, not
failed, otherwise):

```bash
nix develop --command sbcl --script contrib/verify-contrib.lisp
```
