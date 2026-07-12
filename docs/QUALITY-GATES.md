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
