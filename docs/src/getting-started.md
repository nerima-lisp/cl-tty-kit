# Getting Started

This page takes you from an empty checkout to a styled, diff-rendered screen
and a first decoded key event.

!!! info "Prerequisites"

    `cl-tty-kit` requires [SBCL](https://www.sbcl.org/) — see
    [Compatibility](reference/compatibility.md) for why. The core system is
    otherwise dependency-free; its test system, `:cl-tty-kit/test`,
    additionally depends on [`cl-prolog`](https://github.com/nerima-lisp/cl-prolog)
    and [`cl-weave`](https://github.com/nerima-lisp/cl-weave), neither of
    which is on Quicklisp — [Nix](https://nixos.org) is the supported way to
    put both on ASDF's `CL_SOURCE_REGISTRY`, via this repository's
    `flake.nix`. There is no packaged release artifact for non-Nix installs;
    the project is distributed as source, loaded through
    [ASDF](https://asdf.common-lisp.dev/).

## Install with Nix

```sh
nix develop              # SBCL, Git, paredit-cli, treefmt on PATH; CL_SOURCE_REGISTRY pre-wired
nix run .#test           # test suite wrapper
nix run .#verify
nix build                # hermetic `cl-tty-kit` package (sbcl.buildASDFSystem)
nix build .#docs         # hermetic MkDocs (Material) site build, --strict
nix flake check          # hermetic test suite + a paredit-lint structural-parse gate
```

`flake.nix` declares `nerima-lisp/cl-prolog`, `nerima-lisp/cl-weave`, and
`nerima-lisp/paredit-cli` as development inputs. Only `cl-prolog` and
`cl-weave` are ASDF dependencies, and only for `:cl-tty-kit/test`; the core
system depends on SBCL's `sb-posix` layer. The Nix apps, checks, and
`devShell` put the test dependencies on `CL_SOURCE_REGISTRY`; `paredit-cli`
is a development binary.

## Install without Nix

Put the repository somewhere ASDF can see it, for example:

```text
~/quicklisp/local-projects/cl-tty-kit/
```

and make `cl-prolog` and `cl-weave` discoverable the same way — as their own
`local-projects` checkouts, or your own `CL_SOURCE_REGISTRY` entry — since
neither ships with `cl-tty-kit` or Quicklisp. Any directory ASDF already
searches works too, for example a path added to `asdf:*central-registry*`.

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
and example files. This is the supported way to load the core code from a
plain checkout with no environment variables to export first:

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

The core system exports its public API from the `cl-tty-kit` package. The
remaining examples on this page assume it is in scope:

```lisp
(use-package :cl-tty-kit)
```

## Render a screen

`screen` is a pure grid of `cell` objects — no terminal I/O happens until you
explicitly render it. `make-screen` creates one, `screen-write-string` lays
out text, and `render-screen` turns the grid into an ANSI string:

```lisp
(let ((screen (make-screen 20 4)))
  (screen-write-string screen 0 0 "Hi")
  (format t "~A~%" (render-screen screen)))
```

Nothing here touches a TTY — `render-screen` returns a plain string, so you
can print it, test it, or feed it into any output stream. The full data model
is covered in [Screen and Rendering](guide/screen-and-rendering.md).

## Add style

`make-style` builds a normalized style list from modifier keywords and color
entries. `screen-put-cell` accepts a `:style` argument per cell:

```lisp
(let ((screen (make-screen 12 1)))
  (screen-put-cell screen 0 0 #\H :style (make-style :bold (style-fg 196)))
  (screen-put-cell screen 1 0 #\i :style (make-style (style-fg 33)))
  (format t "~A~%" (render-screen screen)))
```

`style-fg`/`style-bg` accept either an indexed color (`(style-fg 196)`, xterm
256-palette) or RGB bytes (`(style-bg 17 34 51)`). See
[Color](guide/color.md) for the full conversion API.

## Render only what changed

Real terminal apps redraw many times per second. `render-diff` compares two
screens of the same dimensions and emits only the changed cells — this is
what `examples/screen-update.lisp` and `examples/styled-render.lisp`
demonstrate:

```lisp
(let ((previous (make-screen 10 2))
      (current (make-screen 10 2)))
  (screen-put-cell current 0 0 #\H)
  (screen-put-cell current 1 0 #\i)
  (screen-put-cell current 0 1 #\!)
  (format t "~A~%" (render-diff current previous)))
```

For a real render loop across many frames, reach for the double-buffered
`renderer` instead of hand-tracking the previous screen yourself — see
[Screen and Rendering](guide/screen-and-rendering.md#the-double-buffered-renderer).

## Decode input

`decode-input` turns a raw terminal input string — printable characters,
control bytes, escape sequences, kitty-protocol sequences, bracketed paste
markers — into a list of `key-event` structures:

```lisp
(decode-input (concatenate 'string "a" (string (code-char 3)) (string #\Esc) "[A"))
;; => (#S(KEY-EVENT :TYPE :CHARACTER :CODE #\a :MODIFIERS NIL)
;;     #S(KEY-EVENT :TYPE :SPECIAL :CODE :CONTROL-C :MODIFIERS NIL)
;;     #S(KEY-EVENT :TYPE :SPECIAL :CODE :UP :MODIFIERS NIL))
```

For a real terminal reading loop, use the streaming decoder instead of
one-shot `decode-input`, so partial reads at chunk boundaries don't produce
spurious errors — see [Input Decoding](guide/input-decoding.md).

## Verifying the install

From a Nix shell (`nix develop`), the repository-local scripts double as an
installation smoke test:

```sh
nix run .#test                  # run the test suite
nix run .#examples              # run every example as a smoke test
nix run .#source-registry-smoke # fresh source-registry discoverability
nix run .#verify                # all of the above in one pass
```

## Where to go next

- Work through more of `examples/` — every file is a small, runnable,
  documented program. See [Examples](guide/examples.md) for the full index.
- Read [Layout](guide/layout.md) and [Widgets](guide/widgets.md) for the rest
  of the display-side API.
- Read [Terminal Session](guide/terminal-session.md) for putting a real
  terminal into raw mode and the alternate screen safely.
- Check [Compatibility](reference/compatibility.md) before deploying —
  `cl-tty-kit` requires SBCL.
- Optional, opt-in integrations that layer external libraries on top of the
  core toolkit live under `contrib/` and are never part of the core build or
  CI. See [Contrib](guide/contrib.md) for how to load them.
