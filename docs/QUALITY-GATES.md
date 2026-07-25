# Quality Gates

`cl-tty-kit` ships a small API surface, but the bar for changes should still be
high. This document defines the repository-local gates a patch must satisfy
before it is treated as release-ready.

## Functional requirements

- public APIs remain executable through tests or runnable examples
- pure subsystems stay pure: screen state, cursor state, rendering, UTF-8, and
  input decoding must not gain ambient I/O requirements
- implementation-specific behavior stays isolated to SBCL-only modules such as
  raw mode and PTY handling
- unsupported implementation paths must signal `unsupported-feature` instead of
  silently degrading

## Non-functional requirements

- every repository entrypoint must be deterministic and bounded by an explicit
  timeout
- tests and examples must run from a clean source-registry discoverability
  check plus the repository bootstrap, not only from an already-loaded image
- public contracts must be human-readable in `README.md`, not hidden only in
  tests or source comments
- behavior changes in rendering, input event shape, or exported symbols must be
  treated as contract changes and documented in the same patch

## Verification gate

Run these commands from the project root:

```bash
sbcl --script scripts/test.lisp
sbcl --script scripts/examples.lisp
sbcl --script scripts/source-registry-smoke.lisp
sbcl --script scripts/verify.lisp
sbcl --script scripts/coverage.lisp
git diff --check
```

Expected outcomes:

- the test suite passes without flaky retries
- every example loads and its explicit runner completes
- the source-registry smoke test can discover `cl-tty-kit` and
  `cl-tty-kit/test`, then load and test the system in a fresh SBCL process via
  the repository bootstrap
- `scripts/verify.lisp` succeeds as the maintainer-grade local release gate
- coverage output is regenerated and inspected for meaningful gaps
- the working tree contains no whitespace or merge-marker defects

## Coverage policy

The target is meaningful coverage, not vanity percentages.

- new public behavior requires direct regression coverage
- complex control flow should be covered through high-level tests first, then
  internal edge tests only where public entrypoints cannot isolate the branch
- files dominated by top-level definitions may under-report under `sb-cover`;
  treat those reports as instrumentation artifacts only after the exported
  contract is already exercised elsewhere

## Macro usage policy

`defmacro` is for genuine compile-time shape: a family of near-identical
top-level definitions (`define-ansi-function` in `src/ansi.lisp`,
`define-tty-kit-condition`/`define-formatted-tty-kit-condition` in
`src/conditions.lisp`, `%define-rect-split` in `src/rect.lisp`,
`%define-osc-color-query` in `src/ansi-osc.lisp`), a binding/control form that
must run its body in a specific dynamic extent (`with-terminal-session`,
`with-raw-mode`), or hygiene around evaluation order a function cannot express.

A macro is the wrong tool when a function would do: converting an ordinary
`defun` to a `defmacro` "for consistency" is a regression, not an improvement.
Unlike a function, a macro cannot be passed to `funcall`/`mapcar`/`apply`/
`sort`/`reduce`, cannot be `flet`-shadowed for a test double, and its
expansion is invisible to `paredit inspect calls`/`inspect similarity` and
similar tooling. Prefer a plain function (optionally parameterized, as
`%bounded-digit-run-p` in `src/mouse.lisp` and `%proper-list-p` in
`src/clamp.lisp` are) for any duplication whose only variation is a runtime
value; reach for a macro only when the duplication is in the *shape* of the
code itself.

## File organization policy

Split a file by concern, not by line count. A large file whose forms serve one
cohesive purpose (a single data table, a single parser, a single constraint
solver) is not a splitting candidate merely for being long; forcing an
unrelated split fragments code that is meant to be read together. A genuine
splitting candidate has independently-loadable, independently-testable
sub-concerns bundled under one name -- the kind `0c6c678` (`ansi`/`ansi-control`/
`ansi-osc`, `screen`/`screen-regions`/`screen-text`, `pty`/`pty-fd`) and the
`t/screen.lisp` test-body decomposition already acted on. Before splitting,
check whether the file's own section-banner comments (`;;; ---`) already
describe one purpose or several; a file with one banner describing one
concern, however long, is usually already at its natural grain.

## Documentation gate

Before merging or releasing:

- `README.md` matches the exported API and runnable examples
- `CHANGELOG.md` records externally visible changes under `Unreleased`
- `CONTRIBUTING.md`, `SECURITY.md`, and `RELEASING.md` still describe the
  current workflow

## Change rejection criteria

Reject or rework a patch when it does any of the following:

- adds backward-compatibility shims instead of clarifying the contract
- mixes data transformation with terminal side effects in pure modules
- introduces unbounded waits, hidden global state, or implementation-dependent
  behavior without an explicit contract
- expands the public API without tests, examples, and documentation in the same
  patch
