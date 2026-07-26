# Logic Engine (Prolog)

`cl-tty-kit`'s embedded logic engine is
[`nerima-lisp/cl-prolog`](https://github.com/nerima-lisp/cl-prolog) itself,
not reimplemented. It is a `:cl-tty-kit/test` dependency, not a `:cl-tty-kit`
one (see [Installation](installation.md)): the core toolkit ships hand-written
imperative decoders on its hot paths, and the test suite states part of that
same classification logic as *relations* over ordinary Lisp data, using the
engine to cross-check the two independently rather than to decide anything at
runtime.

!!! note "Why a logic engine in a terminal toolkit?"
    Terminal work is full of small classification problems — which SGR
    parameter touches which color channel, which byte ranges are wide, which
    escape shape a key belongs to. Stating these as relations gives an
    independent, declarative specification that can be cross-checked against the
    fast imperative decoders. See the [SGR oracle](#a-real-example-the-sgr-oracle)
    below for a worked instance from the test suite.

## What the engine provides

- **ISO-flavored unification, always occurs-checked** — `unify` binds logic
  variables and never introduces a cyclic term.
- **A continuation-passing (CPS) resolver** — proof search threads explicit
  success continuations, so backtracking is ordinary Lisp control flow.
- **An immutable-by-default rulebase** — `prolog`/`define-rulebase` build a
  value; `extend-rulebase` returns a *new* rulebase with additional clauses,
  leaving the base untouched. Mutation is available and deliberate via
  `assertz`/`retract` goals with logical-update-view semantics.
- **A rich ISO built-in set** — cut, arithmetic, `findall/3`/`bagof/3`/`setof/3`,
  `assert`/`retract`, DCG grammars, `library(assoc)`, `library(pairs)`, string
  and character-classification predicates, and more. See cl-prolog's own
  [Builtin Goals](https://github.com/nerima-lisp/cl-prolog) reference for the
  full list.
- **Bounded search** — `:max-depth` bounds user-rule resolution (exhaustion
  signals `prolog-depth-limit-exceeded`) and `:limit` caps the number of
  solutions a query collects.

## Logic variables and terms

A **logic variable** is any non-keyword symbol whose name starts with `?` —
`?x`, `?a`, `?channel`. Everything else (numbers, keywords, other symbols, and
cons trees of them) is ordinary data. A **goal** is a non-empty proper list
whose first element is a relation symbol, e.g. `(parent abraham isaac)` or
`(ancestor ?a ?b)`. A **clause** is a list `(HEAD . BODY)`: a head goal
followed by zero or more body goals.

`AND`, `OR`, `NOT`, and `=` are ordinary symbols inherited from `#:CL`, so they
name cl-prolog's builtins from any package without qualification. `CALL`,
`FINDALL`, `TRUE`, and `FAIL` (among others) have no `#:CL` equivalent, so a
goal using one of these from outside the `CL-PROLOG` package must spell it
`cl-prolog:call`, `cl-prolog:findall`, and so on — an unqualified symbol of the
same name is a *different* symbol and the engine reports the goal as an
undefined procedure.

## Building a rulebase

`prolog` builds an anonymous rulebase value from unquoted clauses;
`define-rulebase` is `defparameter` plus `prolog` for a named one:

```lisp
(defparameter *family*
  (cl-prolog:prolog
    ((parent abraham isaac))
    ((parent isaac jacob))
    ((parent jacob joseph))
    ((ancestor ?a ?b) (parent ?a ?b))
    ((ancestor ?a ?b) (parent ?a ?c) (ancestor ?c ?b))))
```

`extend-rulebase` returns a new rulebase with more clauses layered on top,
without touching the original:

```lisp
(defparameter *extended*
  (cl-prolog:extend-rulebase *family*
    ((parent joseph benjamin))))

(cl-prolog:query-prolog *extended* '(parent joseph ?child))  ; sees benjamin
(cl-prolog:query-prolog *family* '(parent joseph ?child))    ; still empty
```

## Querying

| Call | Returns |
| --- | --- |
| `(query-prolog rulebase goal &key limit max-depth project environment)` | a list of solution alists, one per proof |
| `(query-prolog-first rulebase goal &key ...)` | the first solution alist and `t`, or `(values nil nil)` |
| `(prolog-succeeds-p rulebase goal &key max-depth)` | true as soon as `goal` has any proof |
| `(map-prolog-solutions function rulebase goal &key ...)` | streams solutions to `function` as they are proven |
| `(solution-binding variable solution)` | one variable's value from a solution alist |

Each solution is an alist of query-variable bindings — project a single
variable with `solution-binding`:

```lisp
(mapcar (lambda (solution) (cl-prolog:solution-binding '?d solution))
        (cl-prolog:query-prolog *family* '(ancestor abraham ?d)))
;; => (ISAAC JACOB JOSEPH)
```

A ground proof with no variables to bind succeeds with the alist `nil`, so its
solution list is `(nil)` — not `nil` (that means no proof at all). See
cl-prolog's own Querying and Troubleshooting docs for the full result
convention.

!!! warning "Queries are bounded"
    `:max-depth` (default unbounded) bounds **user-rule** resolution depth,
    not every proof step, and exhaustion signals `prolog-depth-limit-exceeded`
    rather than masquerading as failure. A left-recursive rule such as
    `((loop ?x) (loop (s ?x)))` hits this bound instead of hanging. `:limit`,
    when supplied, is a benign cap — asking for more solutions than exist
    simply returns what was found, with no error. A negative `:max-depth` or a
    non-positive `:limit` signals `invalid-max-depth-error` or a `type-error`
    respectively.

## Builtin goals used by this toolkit

| Goal | Meaning |
| --- | --- |
| `(= LEFT RIGHT)` | unify the two terms |
| `(and GOAL...)` | prove every goal (relational conjunction) |
| `(or GOAL...)` | succeed with each solution of any goal (disjunction) |
| `(not GOAL)` | negation as failure: succeed when `GOAL` has no proof |
| `(cl-prolog:true)` | succeed exactly once |
| `(cl-prolog:fail)` | never succeed |
| `(cl-prolog:call GOAL)` | meta-call: prove a (possibly variable) goal term |
| `(cl-prolog:findall TEMPLATE GOAL RESULT)` | unify `RESULT` with the list of `TEMPLATE` instances over every proof of `GOAL` |

`findall/3` is the aggregation escape hatch out of pure relational search. It
succeeds exactly once — with the empty list when the inner goal has no proof.
Unlike `and`/`or`/`not`/`=`, a *totally unbound* goal passed to `call`/`findall`
signals `prolog-instantiation-error` (ISO semantics) rather than silently
failing.

```lisp
(cl-prolog:query-prolog *family*
  (list 'cl-prolog:findall '?d '(ancestor abraham ?d) '?ds))
;; => (((?DS ISAAC JACOB JOSEPH)))
```

## A real example: the SGR oracle

The test suite (`t/sgr-prolog-oracle-test.lisp`) uses the engine as an independent
specification for part of the SGR color decoder. The imperative decoder in
`src/sgr-parse.lisp` classifies color parameters with a hand-written `case`; the
oracle states the same grammar as one relational fact per parameter and
cross-checks the two, catching drift in either direction:

```lisp
(defparameter *sgr-channel-grammar*
  (cl-prolog:prolog
    ((sgr-channel 38 :fg))
    ((sgr-channel 39 :fg))
    ((sgr-channel 48 :bg))
    ((sgr-channel 49 :bg))
    ((sgr-channel 58 :underline-color))
    ((sgr-channel 59 :underline-color))))

;; Which parameters drive the foreground channel, in definition order?
(mapcar (lambda (s) (cl-prolog:solution-binding '?param s))
        (cl-prolog:query-prolog *sgr-channel-grammar* '(sgr-channel ?param :fg)))
;; => (38 39)

;; A basic color parameter is not part of the channel-selection grammar.
(cl-prolog:prolog-succeeds-p *sgr-channel-grammar* '(sgr-channel 30 :fg))
;; => NIL
```

Here `38`/`48`/`58` set an extended color on a channel and `39`/`49`/`59` reset
it. Because the relation enumerates in definition order, `query-prolog`
recovers the set/reset pair for each channel, and the test asserts the
imperative decoder agrees channel-for-channel. This is the intended shape of
engine usage: the plain facts are the *data* (the grammar), the query is the
*logic*, and `query-prolog`/`prolog-succeeds-p` are first-class code.

## See also

- [nerima-lisp/cl-prolog](https://github.com/nerima-lisp/cl-prolog) — the
  engine's own documentation: the full Rule DSL, builtin goal vocabulary,
  querying semantics, and how to extend it with `define-foreign-predicate`
- [API Reference](api-reference.md) — full public symbol map for the core toolkit
- [Text Layout and Unicode Width](text-layout.md) — width classification the engine can specify
- [ANSI Helpers](ansi-helpers.md) — SGR emission that the oracle above cross-checks
- `contrib/cl-tty-kit-cl-prolog-csi-grammar` — a DCG grammar for the ECMA-48
  CSI byte shape, built on this same engine (opt-in, not part of the core
  build or CI; see `contrib/README.md`)
