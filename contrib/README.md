# cl-tty-kit contrib

Optional, opt-in integrations that layer external libraries on top of the core
toolkit. **Nothing here is part of the core `cl-tty-kit` build or CI** —
`:cl-tty-kit`'s own dependency is `sb-posix` (see the root README's
"Compatibility" section). These modules pull additional libraries from
Quicklisp, or from `nerima-lisp/cl-prolog-kit`, `nerima-lisp/cl-weave`, and
`nerima-lisp/cl-parser-kit` via this repository's `flake.nix` (`nix develop`
puts all three on `CL_SOURCE_REGISTRY`, the same as `:cl-tty-kit/test`), and
are loaded explicitly.

## `cl-tty-kit-cl-prolog-kit-csi-grammar` — DCG grammar via nerima-lisp/cl-prolog-kit

A declarative recognizer for the ECMA-48 CSI (Control Sequence Introducer)
byte-class grammar, built on [`nerima-lisp/cl-prolog-kit`](https://github.com/nerima-lisp/cl-prolog-kit)
(pulled from this repository's `flake.nix` inputs — it is not distributed by
Quicklisp). `src/input-decode.lisp` already decodes CSI sequences
imperatively on the render loop's hot path; this module instead expresses
that same sequence shape — zero or more parameter bytes, then zero or more
intermediate bytes, then exactly one final byte — as a `def-dcg-rule`
grammar run through `phrase`, demonstrating cl-prolog-kit's DCG support
independently of the hand-written decoder.

```lisp
;; nix develop  -- puts cl-prolog-kit on CL_SOURCE_REGISTRY, once per shell
(asdf:load-system :cl-tty-kit-cl-prolog-kit-csi-grammar)

(tty-csi-grammar:csi-sequence-valid-p "1;1H")     ; => T   (cursor position)
(tty-csi-grammar:csi-sequence-valid-p "38;5;196m") ; => T   (SGR, 256-color fg)
(tty-csi-grammar:csi-sequence-valid-p "1;1")       ; => NIL (no final byte)
```

## `cl-tty-kit-cl-parser-kit-csi-grammar` — combinator grammar via nerima-lisp/cl-parser-kit

A second, independent declarative recognizer for the same ECMA-48 CSI grammar
as the DCG version above, built on
[`nerima-lisp/cl-parser-kit`](https://github.com/nerima-lisp/cl-parser-kit)'s
`seq`/`many`/`type-token` parser combinators instead of cl-prolog-kit's DCG rules
(pulled from this repository's `flake.nix` inputs — it is not distributed by
Quicklisp). `contrib/verify-contrib.lisp` cross-checks the two grammars agree
on every case, the same differential-testing shape `t/sgr-prolog-oracle.lisp`
uses against the hand-written decoder.

```lisp
;; nix develop  -- puts cl-parser-kit on CL_SOURCE_REGISTRY, once per shell
(asdf:load-system :cl-tty-kit-cl-parser-kit-csi-grammar)

(tty-csi-parser-kit-grammar:csi-sequence-valid-p "1;1H")      ; => T   (cursor position)
(tty-csi-parser-kit-grammar:csi-sequence-valid-p "38;5;196m") ; => T   (SGR, 256-color fg)
(tty-csi-parser-kit-grammar:csi-sequence-valid-p "1;1")       ; => NIL (no final byte)
```

## `cl-tty-kit-weave-tests` — property-based fuzz tests via nerima-lisp/cl-weave

Property-based tests built on [`nerima-lisp/cl-weave`](https://github.com/nerima-lisp/cl-weave)
(pulled from this repository's `flake.nix` inputs — it is not distributed by
Quicklisp). `cl-weave`'s `it-property` generators
(`gen-vector`, `gen-string`, `gen-character`, ...) fuzz `src/utf8.lisp`'s
octet decoder and the public `cl-tty-kit:decode-input` entry point with
thousands of arbitrary byte sequences, asserting the documented contract:
malformed input always signals a `cl-tty-kit:tty-kit-error` condition and
never an undocumented Lisp error — the realistic threat model for decoders
that read attacker-controlled PTY bytes. It also regression-tests the DCG CSI
grammar above.

```lisp
;; nix develop  -- puts cl-prolog-kit and cl-weave on CL_SOURCE_REGISTRY, once per shell
(asdf:load-system :cl-tty-kit-weave-tests)
(cl-tty-kit/weave-property-tests:run-tests)    ; => T on success

;; Run more generated cases per property (default is cl-weave's own):
;;   CL_WEAVE_PROPERTY_TESTS=2000 sbcl --script contrib/verify-contrib.lisp
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

`contrib/verify-contrib.lisp` exercises the Quicklisp-backed clweb tangle
integration, and additionally exercises the cl-prolog-kit/cl-parser-kit/cl-weave
integrations above when ASDF can find the relevant system (skipped, not
failed, otherwise):

```bash
nix develop --command sbcl --script contrib/verify-contrib.lisp
```
