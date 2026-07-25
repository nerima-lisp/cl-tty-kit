# Installation

!!! info "Prerequisites"

    `cl-tty-kit` requires [SBCL](https://www.sbcl.org/) — see
    [Compatibility](compatibility.md) for why. There is no Nix flake and no
    packaged release artifact; the project is distributed as source, loaded
    through [ASDF](https://asdf.common-lisp.dev/).

## Put the repository where ASDF can find it

The simplest path is Quicklisp's `local-projects` directory:

```text
~/quicklisp/local-projects/cl-tty-kit/
```

Any directory ASDF already searches works too — for example a path added to
`asdf:*central-registry*` or `CL_SOURCE_REGISTRY`.

=== "git clone"

    ```sh
    git clone https://github.com/nerima-lisp/cl-tty-kit.git \
      ~/quicklisp/local-projects/cl-tty-kit
    ```

=== "git submodule"

    If you are vendoring `cl-tty-kit` inside another project (the way
    `cl-tty-kit` itself vendors optional integrations under `vendor/`, see
    [Contrib](contrib.md)):

    ```sh
    git submodule add https://github.com/nerima-lisp/cl-tty-kit.git \
      vendor/cl-tty-kit
    ```

## Load it

`cl-tty-kit` ships a repository-local bootstrap script,
`scripts/bootstrap.lisp`, that registers the project tree with ASDF's source
registry and exposes helpers for loading the core system, the test system,
and example files. This is the supported way to load the code — it works from
a plain checkout with no environment variables to export first:

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
embedded logic engine is [`nerima-lisp/cl-prolog`](https://github.com/nerima-lisp/cl-prolog)
itself, used directly under its own `cl-prolog` package — see
[Logic Engine](logic-engine.md).

```lisp
(use-package :cl-tty-kit)
```

## Dependencies

The core system has two dependencies. `sb-posix` is conditional: used only by
the SBCL-specific raw-mode layer, gated behind `#+sbcl` so ASDF never fails
dependency resolution with a confusing "system not found" on a non-SBCL host.
On any other implementation, loading `cl-tty-kit` fails fast with a clear
"requires SBCL" error instead — see [Compatibility](compatibility.md).
`cl-prolog` (the embedded logic engine) is itself dependency-free and
portable; it is vendored as a git submodule at `vendor/cl-prolog` rather than
distributed by Quicklisp, and `cl-tty-kit.asd` registers that path
automatically, so `(asdf:load-system :cl-tty-kit)` resolves it without any
extra setup once the submodule is checked out (`git submodule update --init
vendor/cl-prolog`).

Everything else — screen state, cursor state, rendering, UTF-8 handling, and
input decoding — is pure Common Lisp with no external dependencies.

## Verifying the install

From a fresh checkout, the repository-local scripts double as an
installation smoke test:

```sh
sbcl --script scripts/test.lisp               # run the test suite
sbcl --script scripts/examples.lisp            # run every example as a smoke test
sbcl --script scripts/source-registry-smoke.lisp  # fresh source-registry discoverability
sbcl --script scripts/verify.lisp              # all of the above in one pass
```

`scripts/verify.lisp` is the same gate the CI matrix (Linux and macOS) runs
on every push — see [Quality Gates](quality-gates.md).

## Optional integrations

Optional, opt-in integrations that layer external libraries on top of the
core toolkit — a DCG grammar bridge, property-based fuzz tests via
`nerima-lisp/cl-weave`, an external ISO Prolog bridge, and a literate-program
source — live under `contrib/` and are never part of the core build or CI.
See [Contrib](contrib.md) for how to load them.

## Next steps

Continue with [Quick Start](quick-start.md) to render your first screen, or
jump straight to [Compatibility](compatibility.md) for the SBCL-only
contract details.
