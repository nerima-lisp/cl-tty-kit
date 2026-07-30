# Quality Gates

`cl-tty-kit` ships a small API surface, but the bar for changes stays high.
This page is the canonical definition of the repository-local gates a patch
must satisfy before it is treated as release-ready.

## Functional requirements

- public APIs remain executable through tests or runnable examples
- pure subsystems stay pure: screen state, cursor state, rendering, UTF-8,
  and input decoding must not gain ambient I/O requirements
- implementation-specific behavior stays isolated to SBCL-only modules such
  as raw mode and PTY handling (see [Compatibility](compatibility.md))
- unsupported implementation paths must signal
  [`unsupported-feature`](conditions.md#unsupported-feature) instead of
  silently degrading

## Non-functional requirements

- every repository entrypoint must be deterministic and bounded by an
  explicit timeout
- tests and examples must run from a clean source-registry discoverability
  check plus the repository bootstrap, not only from an already-loaded image
- public contracts must be human-readable on this site, not hidden only in
  tests or source comments
- behavior changes in rendering, input event shape, or exported symbols must
  be treated as contract changes and documented in the same patch

## Verification gate

Run these commands from the project root. Each `nix run` app applies an
OS-level timeout around SBCL, including ASDF/bootstrap loading. The runner
also supplies the flake-pinned source registry and a temporary `HOME` and XDG
directory, so host ASDF configuration and caches do not affect the result:

```bash
nix run .#test
nix run .#examples
nix run .#source-registry-smoke
nix run .#verify
nix run .#coverage
git diff --check
```

Expected outcomes:

- the test suite passes without flaky retries
- every example loads and its explicit runner completes
- the source-registry smoke test can discover `cl-tty-kit` and
  `cl-tty-kit/test`, then load and test the system in a fresh SBCL process
  via the repository bootstrap
- `scripts/verify.lisp` succeeds as the maintainer-grade local release gate
- coverage output is regenerated and inspected for meaningful gaps
- the working tree contains no whitespace or merge-marker defects

### The local gate is weaker than CI on macOS

!!! warning "A green local run on a Mac is not a green CI run"
    Nix ships with `sandbox = false` on macOS (`nix config show sandbox`), so
    `nix flake check` run locally on a Mac builds `checks.*.test` with the
    host filesystem visible. CI's `x86_64-linux` runner sandboxes it, where
    the only absolute paths that exist are `/bin/sh` and the Nix store.

A test that reaches for any other absolute path — `/bin/sleep`,
`/usr/bin/env`, a system config file — therefore passes locally on a Mac and
fails only in CI. This is not hypothetical: `t/pty-test.lisp`'s SIGTERM case
spawned `/bin/sleep` and did exactly that.

Spawn external programs through `/bin/sh` and let `PATH` resolve the rest
(`:program "/bin/sh" :args '("-c" "exec sleep 5")`), and before trusting a
local green run on macOS for anything touching the filesystem or a
subprocess, reproduce CI's environment:

```bash
nix build --option sandbox true .#checks.aarch64-darwin.default
```

## Macro usage and file organization

`defmacro` is for genuine compile-time shape: a family of near-identical
top-level definitions (`define-ansi-function`,
`define-tty-kit-condition`/`define-formatted-tty-kit-condition`,
`%define-rect-split`, `%define-osc-color-query`) or a binding form that must
run its body in a specific dynamic extent (`with-terminal-session`,
`with-raw-mode`). Converting an ordinary function to a macro "for
consistency" is a regression: unlike a function, a macro cannot be passed to
`funcall`/`mapcar`/`apply`, cannot be shadowed for a test double, and its
expansion is invisible to structural tooling. Duplication whose only
variation is a runtime value gets a plain (optionally parameterized)
function instead.

Files split by concern, not by line count. A long file whose forms serve one
cohesive purpose (a single data table, a single parser, a single solver) is
not a splitting candidate merely for being long — the ANSI/screen/PTY module
boundaries throughout this site (see [API Reference](api-reference.md)) are
what a genuine concern boundary looks like. Coverage percentage follows the
same principle as line count:
files dominated by top-level data definitions (`defparameter` tables,
`defstruct` slot defaults) routinely under-report under `sb-cover` even when
fully exercised, because those forms run exactly once at load time and the
instrumentation does not mark that as "entered" the way an `if`/`when`
branch is marked — treat such a report as a tooling artifact, not a gap,
once the exported contract is verified elsewhere.

The same artifact shows up one level down, inside ordinary `defun`s: an
`&key`/`&optional` default-value init-form (`(defun make-cell (&key (char
#\Space) style)) ...)`) is compiled as part of the lambda-list-parsing
prologue rather than the instrumented function body, so `sb-cover` marks it
"not executed" even when the function is called without that argument --
`%blank-cell` calls `(make-cell)` on every blank screen cell in this
codebase, and `char`'s `#\Space` default in `src/cell.lisp` still reports as
uncovered. Verify by testing what the function *returns* when the argument
is omitted (already true for `make-cell`'s default, per the test above),
not by chasing the source form itself to a covered state -- it cannot
reach one.

The same artifact reaches *branch* coverage too, not only expression
coverage, once a validation call goes through `DEFINE-SIMPLE-ASSERT`/
`DEFINE-VALIDATING-ASSERT`: `src/cursor.lisp`'s `%ASSERT-CURSOR-COORDINATE`
wraps a single `(typep value '(integer 0 *))` check, and `t/cursor-test.lisp`
demonstrably exercises both outcomes -- `(make-cursor)` for the true branch,
`(make-cursor :x -1)` (asserting `CURSOR-PARAMETER-INVALID`) for the false
branch -- yet `sb-cover` still reports that `typep` as a partially-covered
branch. Treat a low branch-coverage percentage on a file dominated by these
macros the same way: confirm both outcomes have a passing test, not that
`sb-cover`'s own percentage reaches 100. For a stronger, artifact-free signal
on a specific pure function, prefer mutation testing over chasing the
`sb-cover` percentage -- see `t/properties-test.lisp`'s "clamp's body has no
surviving mutant" block, built on `cl-weave:run-mutations`: it takes `CLAMP`'s
own body form, applies cl-weave's arithmetic/comparison/branch mutation
operators, and asserts every mutant produces a different result from the
real function on a case battery covering both branches and their boundary --
a claim no line-coverage percentage can make, since a mutant and the
original take the identical source paths by construction.

## Documentation gate

Before merging or releasing:

- the [API Reference](api-reference.md) matches the exported symbols, which
  `t/package-readme-test.lisp` checks mechanically
- [Examples](examples.md) lists every runnable file under `examples/`
- `CHANGELOG.md` records externally visible changes under `[Unreleased]`
- [Development](development.md) and [Release Process](release-process.md)
  still describe the current workflow

## Change rejection criteria

Reject or rework a patch when it does any of the following:

- adds backward-compatibility shims instead of clarifying the contract
- mixes data transformation with terminal side effects in pure modules
- introduces unbounded waits, hidden global state, or implementation-dependent
  behavior without an explicit contract
- expands the public API without tests, examples, and documentation in the
  same patch

## What CI actually runs

The gate above is what `.github/workflows/ci.yml` enforces on every push and
pull request. The `check` job runs `nix flake check --all-systems` across an
`x86_64-linux` / `aarch64-darwin` matrix, which evaluates every platform in
`flake.nix`'s `systems` list rather than only the runner's own, and covers
four checks: `default` (the hermetic test suite), `paredit-lint` (the
structural-parse gate), `formatting` (treefmt/nixfmt), and `docs`
(`mkdocs build --strict`).

Two jobs sit alongside it, each for work the Nix sandbox cannot do. The
`coverage` job uploads the report as a build artifact. The `contrib` job
exercises the opt-in integrations under `contrib/` (see [Contrib](contrib.md))
and needs network access for Quicklisp; it is `continue-on-error` so that
Quicklisp flakiness never blocks a core merge.

See [Release Process](release-process.md) for how this gate fits into
cutting a tagged release.

## Production readiness

"Production ready" is not a separate, informal judgment call layered on top
of the gates above -- it is what passing all of them, together, means. A
release is production ready when every one of these holds simultaneously:

- **API contract**: the 1.x line has a semantic-versioning guarantee (see
  `README.md`'s "API stability" section), checked mechanically against the
  live package by `t/package-introspection-test.lisp`
- **Reproducible build**: `nix build` produces the hermetic package from a
  flake-pinned source registry, with no reliance on host ASDF configuration
  or caches (see the verification gate above)
- **CI matrix, not just local**: `.github/workflows/ci.yml` runs the same
  `nix flake check --all-systems` across `x86_64-linux` and `aarch64-darwin`
  on every push, not only whichever platform a contributor develops on (see
  "The local gate is weaker than CI on macOS" above)
- **Bounded execution**: every entry point (test, example, coverage,
  benchmark, verify) runs under an explicit OS-level timeout, so a hang is a
  failed run, not a stuck CI job -- see "Non-functional requirements" above
- **No backward-compatibility debt**: the change-rejection criteria above
  reject shims and dual code paths on sight, so the tree carries no
  deprecated surface waiting to be a future incident
- **Documented contract**: the documentation gate above keeps the API
  reference, examples list, and CHANGELOG mechanically or procedurally tied
  to the actual exported surface, so "production ready" also means
  "explainable to a new integrator without reading the source"
- **Security and support policy**: the org-wide
  [security policy](https://github.com/nerima-lisp/.github/blob/main/SECURITY.md)
  and [support policy](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md)
  apply to this repository, so a vulnerability report has a defined
  intake path rather than an ad hoc one

None of these is new process -- each is an existing, already-enforced gate.
This section exists so "is this production ready" has one page to check
against instead of an implicit standard scattered across this site.
