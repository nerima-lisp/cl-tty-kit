# Contributing

`cl-tty-kit` is intentionally small and SBCL-first. Contributions should keep
the core API focused, testable, and easy to embed in terminal applications.

## Before you change code

- read `README.md` to confirm the scope
- keep platform-specific behavior isolated
- prefer small, composable public functions over broad abstractions

## Verification

Run the repository-local test entrypoint from the project root:

```bash
sbcl --script scripts/test.lisp
```

Run the example smoke test as well:

```bash
sbcl --script scripts/examples.lisp
```

Run the fresh source-registry smoke test too:

```bash
sbcl --script scripts/source-registry-smoke.lisp
```

For the complete repository gate, run:

```bash
sbcl --script scripts/verify.lisp
```

If you want to work from a REPL, load the bootstrap first and then the core
system:

```lisp
(load "scripts/bootstrap.lisp")
(cl-tty-kit/bootstrap:load-core-system)
```

Project policy documents:

- `CODE_OF_CONDUCT.md`
- `SECURITY.md`
- `docs/QUALITY-GATES.md`

## Testing expectations

- add regression coverage for new public behavior
- keep tests deterministic and fast
- make SBCL-specific behavior explicit in both code and tests
- preserve the `unsupported-feature` contract for implementation-specific APIs
- keep pure modules free from ambient I/O and timeout-free waits

## Reporting issues

When filing a bug, include:

- the SBCL version
- the exact input that triggered the problem
- the observed output or exception
- whether the issue is specific to raw mode, PTY, or pure data structures
