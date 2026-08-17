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
  described in [Compatibility](../reference/compatibility.md)
- prefer small, composable public functions over broad abstractions

## Nix entry points

Nix is the supported way to get `cl-prolog-kit`/`cl-weave` onto
`CL_SOURCE_REGISTRY` (see [Getting Started](../getting-started.md#install-with-nix)); everything
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

## Running the bounded suite commands

Run the repository-local test entry point from the project root:

```bash
nix run .#test
```

Run the example smoke test as well — every file in `examples/` is loaded and
its runner executed (see [Examples](../guide/examples.md)):

```bash
nix run .#examples
```

Run the fresh source-registry smoke test too, which confirms `cl-tty-kit` and
`cl-tty-kit/test` are discoverable and loadable in a clean SBCL process via
the repository bootstrap:

```bash
nix run .#source-registry-smoke
```

For the complete local repository gate, see [Quality Gates](quality-gates.md):

```bash
nix run .#verify
```

Generate an SBCL coverage report for `src/`:

```bash
nix run .#coverage
```

`nix run .#verify` runs the repository-local tests, the example smoke
checks, and the fresh source-registry packaging smoke in one pass. The
canonical test package is `cl-tty-kit/test`, and the tests live in `t/`.

If you want to work from a REPL, load the bootstrap first and then the core
system, as described in [Getting Started](../getting-started.md):

```lisp
(load "scripts/bootstrap.lisp")
(cl-tty-kit/bootstrap:load-core-system)
```

## Testing expectations

- add regression coverage for new public behavior
- keep tests deterministic and fast
- make SBCL-specific behavior explicit in both code and tests
- preserve the [`unsupported-feature`](../reference/conditions.md#unsupported-feature)
  contract for implementation-specific APIs
- keep pure modules free from ambient I/O and timeout-free waits
- write new tests against
  [cl-weave](https://github.com/nerima-lisp/cl-weave)'s `describe`/`it`/`expect`
  DSL, not the retired `is`/`is-equal`/`signals` macros in `t/suite.lisp` —
  every file in `t/` shares one package, `cl-tty-kit/test`, which already has
  `describe` (shadowed), `expect`, `it`, and `it-property` available. A
  table-driven case (several inputs checked the same way) is a `dolist` over
  the case data with an `it` registered per iteration — see any of the
  `prolog-*-test.lisp` files — not `it-each`, whose case list must be a
  literal known at macro-expansion time and so cannot take a `defparameter`
  table. Property-based invariants (a law that must hold for all inputs, not
  a worked example) belong in `t/properties-test.lisp` via `it-property`.

## Renderer performance regression checks

The normal test entry point executes the fixed renderer, diff-renderer, and
renderer example suites in addition to the property suite. Keep renderer
changes correct before optimizing them: the diff tests compare ANSI output and
exercise cursor-coordinate boundaries where decimal escape-sequence lengths
change.

`t/properties-test.lisp` also includes an allocation regression guard for an
80x24 full repaint. It uses a deliberately generous 2 MiB ceiling to catch
accidental per-cell string construction without treating machine-specific GC
noise as a failure. Do not claim a latency or throughput improvement without a
separate, repeatable benchmark on an otherwise idle host.

Use the renderer benchmark for stable stateless-diff, sparse-update renderer,
and full-repaint renderer measurements:

```sh
nix run .#benchmark-renderer
nix run .#benchmark-renderer -- 500000
```

It warms up SBCL, then reports throughput and allocated bytes per frame for an
80x24 screen. Compare runs only on the same idle host, SBCL build, and
iteration count; it is a regression signal, not a portable performance claim.
The renderer cases reuse their alternating cell templates, so their allocation
figures do not include constructing a new cell for every input mutation.

`scripts/benchmark-hotpaths.lisp` complements the renderer benchmark with
function-level measurements for other hot paths: the render threshold check,
`screen-write-string` on ASCII and mixed-width input, the streaming input
decoder's empty-chunk paths, `ansi-set-clipboard`'s OSC 52 base64 encoding,
`format-table`, and `rgb-to-256`. It is a standalone script, not wired into
`flake.nix`'s apps, since it is a development aid rather than a CI gate:

```sh
sbcl --script scripts/benchmark-hotpaths.lisp
sbcl --script scripts/benchmark-hotpaths.lisp 500000
```

Same caveats as above: same idle host and iteration count across runs, a
regression signal rather than a portable claim.

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
