# Contributing Guide

`cl-tty-kit` is intentionally small and SBCL-first. Contributions should keep
the core API focused, testable, and easy to embed in terminal applications —
see [Roadmap](roadmap.md) for what stays explicitly out of scope.

## Before you change code

- read the root `README.md` to confirm the change fits the project's scope
- keep platform-specific behavior isolated behind the pure/OS-facing split
  described in [Compatibility](compatibility.md)
- prefer small, composable public functions over broad abstractions

## Verification

Run the repository-local test entrypoint from the project root:

```bash
sbcl --script scripts/test.lisp
```

Run the example smoke test as well — every file in `examples/` is loaded and
its runner executed (see [Examples](examples.md)):

```bash
sbcl --script scripts/examples.lisp
```

Run the fresh source-registry smoke test too, which confirms `cl-tty-kit` and
`cl-tty-kit/test` are discoverable and loadable in a clean SBCL process via
the repository bootstrap:

```bash
sbcl --script scripts/source-registry-smoke.lisp
```

For the complete repository gate — the same one CI runs — see
[Quality Gates](quality-gates.md):

```bash
sbcl --script scripts/verify.lisp
```

If you want to work from a REPL, load the bootstrap first and then the core
system, as described in [Installation](installation.md):

```lisp
(load "scripts/bootstrap.lisp")
(cl-tty-kit/bootstrap:load-core-system)
```

Project policy documents live at the repository root and under `docs/`:

- `CODE_OF_CONDUCT.md`
- `SECURITY.md`
- [Quality Gates](quality-gates.md) (`docs/QUALITY-GATES.md`)

## Testing expectations

- add regression coverage for new public behavior
- keep tests deterministic and fast
- make SBCL-specific behavior explicit in both code and tests
- preserve the [`unsupported-feature`](conditions.md#unsupported-feature)
  contract for implementation-specific APIs
- keep pure modules free from ambient I/O and timeout-free waits

## Reporting issues

When filing a bug, include:

- the SBCL version
- the exact input that triggered the problem
- the observed output or exception
- whether the issue is specific to raw mode, PTY, or pure data structures

## Documentation changes

This site is built from `docs/src/*.md` with [MkDocs](https://www.mkdocs.org/)
and the [Material](https://squidfunk.github.io/mkdocs-material/) theme.
Preview changes locally before opening a pull request:

```bash
pip install mkdocs-material
mkdocs serve --config-file docs/mkdocs.yml
```

`mkdocs build --strict --config-file docs/mkdocs.yml` is what CI runs to
publish to GitHub Pages (see [Release Process](release-process.md)) — a
broken internal link or an unlisted page fails that build, so run it before
submitting a documentation patch.
