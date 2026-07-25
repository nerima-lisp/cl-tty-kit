# Installation

!!! info "Prerequisites"

    `cl-tty-kit` requires [SBCL](https://www.sbcl.org/) — see
    [Compatibility](compatibility.md) for why. The core system is otherwise
    dependency-free; its test system, `:cl-tty-kit/test`, additionally
    depends on [`cl-prolog`](https://github.com/nerima-lisp/cl-prolog) and
    [`cl-weave`](https://github.com/nerima-lisp/cl-weave), neither of which
    is on Quicklisp — [Nix](https://nixos.org) is the supported way to put
    both on ASDF's `CL_SOURCE_REGISTRY`, via this repository's `flake.nix`.
    There is no packaged release artifact for non-Nix installs; the project
    is distributed as source, loaded through
    [ASDF](https://asdf.common-lisp.dev/).

## Nix

```sh
nix develop              # SBCL, Git, paredit-cli, nixpkgs-fmt on PATH; CL_SOURCE_REGISTRY pre-wired
nix run .#test           # same scripts CI's `nix` job runs: test / verify / coverage
nix run .#verify
nix run .#coverage
nix build                # hermetic `cl-tty-kit` package (sbcl.buildASDFSystem)
nix build .#docs         # hermetic MkDocs (Material) site build, --strict
nix flake check          # hermetic test suite + a paredit-lint structural-parse gate
```

`flake.nix` declares `nerima-lisp/cl-prolog`, `nerima-lisp/cl-weave`, and
`nerima-lisp/paredit-cli` as flake inputs — the same systems `cl-tty-kit.asd`
depends on — and every app, check, and `devShell` above puts them on
`CL_SOURCE_REGISTRY`. Continue with [Load it](#load-it) below once you're in
a Nix shell (or have `CL_SOURCE_REGISTRY` set some other way).

## Without Nix

Put the repository somewhere ASDF can see it, for example:

```text
~/quicklisp/local-projects/cl-tty-kit/
```

and make `cl-prolog` and `cl-weave` discoverable the same way — as their own
`local-projects` checkouts, or your own `CL_SOURCE_REGISTRY` entry — since
neither ships with `cl-tty-kit` or Quicklisp.

Any directory ASDF already searches works too — for example a path added to
`asdf:*central-registry*` or `CL_SOURCE_REGISTRY`.

=== "git clone"

    ```sh
    git clone https://github.com/nerima-lisp/cl-tty-kit.git \
      ~/quicklisp/local-projects/cl-tty-kit
    ```

=== "git submodule"

    If you are vendoring `cl-tty-kit` inside another project:

    ```sh
    git submodule add https://github.com/nerima-lisp/cl-tty-kit.git \
      vendor/cl-tty-kit
    ```

## Load it

`cl-tty-kit` ships a repository-local bootstrap script,
`scripts/bootstrap.lisp`, that registers the project tree with ASDF's source
registry and exposes helpers for loading the core system, the test system,
and example files. This is the supported way to load the code — it works from
a plain checkout with no environment variables to export first, as long as
`cl-prolog` is already on `CL_SOURCE_REGISTRY` (see above):

```lisp
(load "scripts/bootstrap.lisp")
(cl-tty-kit/bootstrap:load-core-system)
```

`load-core-system` calls `(asdf:load-system :cl-tty-kit)` after registering
the source tree, and is idempotent — calling it again is a no-op unless you
pass `:force t`.

If you already load systems through Quicklisp-style `local-projects`
discovery and don't need the bootstrap helpers, a plain ASDF load also works
once the project is on the source registry:

```lisp
(asdf:load-system :cl-tty-kit)
```

## Package and nicknames

The core system exports its public API from the `cl-tty-kit` package. The
test suite's embedded logic engine is [`nerima-lisp/cl-prolog`](https://github.com/nerima-lisp/cl-prolog)
itself, used directly under its own `cl-prolog` package — see
[Logic Engine](logic-engine.md).

```lisp
(use-package :cl-tty-kit)
```

## Dependencies

The core `:cl-tty-kit` system has exactly one, conditional, dependency:
`sb-posix`, used only by the SBCL-specific raw-mode layer, gated behind
`#+sbcl` so ASDF never fails dependency resolution with a confusing "system
not found" on a non-SBCL host. On any other implementation, loading
`cl-tty-kit` fails fast with a clear "requires SBCL" error instead — see
[Compatibility](compatibility.md). Everything else — screen state, cursor
state, rendering, UTF-8 handling, and input decoding — is pure Common Lisp
with no external dependencies.

`:cl-tty-kit/test` additionally depends on `cl-prolog` (the test suite's
differential-testing oracle; see [Logic Engine](logic-engine.md)) and
`cl-weave` (the test framework). Neither is distributed by Quicklisp; `nix
develop`/`nix build`/`nix run` (see [Nix](#nix) above) put both on
`CL_SOURCE_REGISTRY` via this repository's `flake.nix`, and
`cl-tty-kit.asd`'s `:depends-on` resolves them from there.

## Verifying the install

From a Nix shell (`nix develop`), the repository-local scripts double as an
installation smoke test:

```sh
sbcl --script scripts/test.lisp               # run the test suite
sbcl --script scripts/examples.lisp            # run every example as a smoke test
sbcl --script scripts/source-registry-smoke.lisp  # fresh source-registry discoverability
sbcl --script scripts/verify.lisp              # all of the above in one pass
```

`scripts/verify.lisp` is what CI's `nix` job runs (via `nix flake check`) on
Linux and macOS on every push — see [Quality Gates](quality-gates.md).

## Optional integrations

Optional, opt-in integrations that layer external libraries on top of the
core toolkit — two independent CSI grammars (a `nerima-lisp/cl-prolog` DCG
and a `nerima-lisp/cl-parser-kit` combinator parser), property-based fuzz
tests via `nerima-lisp/cl-weave`, an external ISO Prolog bridge, and a
literate-program source — live under `contrib/` and are never part of the
core build or CI. See [Contrib](contrib.md) for how to load them.

## Next steps

Continue with [Quick Start](quick-start.md) to render your first screen, or
jump straight to [Compatibility](compatibility.md) for the SBCL-only
contract details.
