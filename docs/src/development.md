# Development

`cl-tty-kit` is intentionally small and SBCL-first. Contributions should keep
the core API focused, testable, and easy to embed in terminal applications —
see [Roadmap](roadmap.md) for what stays explicitly out of scope.

The org-wide policy documents — the
[contribution guide](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md),
the [code of conduct](https://github.com/nerima-lisp/.github/blob/main/CODE_OF_CONDUCT.md),
the [security policy](https://github.com/nerima-lisp/.github/blob/main/SECURITY.md)
and [support](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md) —
live in the `nerima-lisp/.github` repository and apply to every package in the
org. This page covers only what is specific to this repository.

## Before you change code

- read the root `README.md` to confirm the change fits the project's scope
- keep platform-specific behavior isolated behind the pure/OS-facing split
  described in [Compatibility](compatibility.md)
- prefer small, composable public functions over broad abstractions

## Nix entry points

Nix is the supported way to get `cl-prolog`/`cl-weave` onto
`CL_SOURCE_REGISTRY` (see [Installation](installation.md#nix)); everything
below assumes either `nix develop` or one of these wrappers.

```bash
nix develop          # SBCL, Git, paredit-cli and treefmt on PATH
nix run .#test       # the test suite
nix run .#verify     # the full local release gate
nix run .#coverage   # regenerate the sb-cover report under coverage/
nix build            # the hermetic cl-tty-kit package
nix build .#docs     # this site, built offline with --strict
nix flake check      # tests + paredit-lint + formatting + docs, the CI gate
nix fmt              # format Nix sources (treefmt/nixfmt)
```

## Running the suites directly

Run the repository-local test entry point from the project root:

```bash
sbcl --script run-tests.lisp
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

Generate an SBCL coverage report for `src/`:

```bash
sbcl --script scripts/coverage.lisp
```

`scripts/verify.lisp` runs the repository-local tests, the example smoke
checks, and the fresh source-registry packaging smoke in one pass. The
canonical test package is `cl-tty-kit/test`, and the tests live in `t/`.

If you want to work from a REPL, load the bootstrap first and then the core
system, as described in [Installation](installation.md):

```lisp
(load "scripts/bootstrap.lisp")
(cl-tty-kit/bootstrap:load-core-system)
```

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

For a security-sensitive finding, follow the org
[security policy](https://github.com/nerima-lisp/.github/blob/main/SECURITY.md)
rather than opening a public issue. Reports against this package are usually
about one of these areas, and naming the one you mean makes a report
reproducible much faster:

- raw mode transitions
- PTY lifecycle handling
- UTF-8 or terminal input decoding
- screen buffer bounds or rendering correctness

## Documentation changes

This site is built from `docs/src/*.md` with [MkDocs](https://www.mkdocs.org/)
and the [Material](https://squidfunk.github.io/mkdocs-material/) theme.
`nix build .#docs` is what CI runs to publish to GitHub Pages (see
[Release Process](release-process.md)) — it builds fully offline in
`--strict` mode, so a broken internal link or an unlisted nav page fails the
build rather than publishing a silent gap. The same derivation is also wired
in as `checks.docs`, so a documentation break fails the pull request rather
than the post-merge deploy. Review it locally before opening a documentation
pull request:

```bash
nix build .#docs
open result/index.html   # or: xdg-open result/index.html on Linux
```
