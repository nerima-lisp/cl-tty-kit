# cl-tty-kit contrib

Optional, opt-in integrations that layer external libraries on top of the core
toolkit. **Nothing here is part of the core `cl-tty-kit` build or CI** — the core
system keeps its single `sb-posix` dependency. These modules pull additional
libraries from Quicklisp and are loaded explicitly.

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

`contrib/verify-contrib.lisp` exercises both integrations (bridge translation +
clweb tangle) without needing an external Prolog binary:

```bash
sbcl --script contrib/verify-contrib.lisp
```
