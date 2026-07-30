# cl-tty-kit

[![CI](https://github.com/nerima-lisp/cl-tty-kit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-tty-kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-tty-kit/)

`cl-tty-kit` is a small Common Lisp toolkit for terminal and TTY work: raw
mode, ANSI escape helpers, key and mouse input decoding, Unicode-aware text
layout, a pure screen/cell model with diff rendering, and PTY support. It
targets SBCL, and the core system is dependency-free. It is a set of terminal
primitives, not a UI framework or a shell — everything above the primitives is
left to you.

Full documentation is published at <https://nerima-lisp.github.io/cl-tty-kit/>.
The source for that site lives in [docs/src/](docs/src/).

## Quick Start

```lisp
(use-package :cl-tty-kit)

(let ((screen (make-screen 20 4)))
  (screen-write-string screen 0 0 "Hi")
  (format t "~A~%" (render-screen screen)))
```

The `examples/` directory holds 21 more runnable programs, from a full repaint
to a double-buffered render loop; see
[Examples](https://nerima-lisp.github.io/cl-tty-kit/examples/).

## Install

The core `cl-tty-kit` system is dependency-free, but its test system depends on
[`cl-prolog`](https://github.com/nerima-lisp/cl-prolog) and
[`cl-weave`](https://github.com/nerima-lisp/cl-weave), neither of which is on
Quicklisp. Nix is the supported way to put both on `CL_SOURCE_REGISTRY`:

```nix
# flake.nix
inputs.cl-tty-kit = {
  url = "github:nerima-lisp/cl-tty-kit/v1.0.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Note the pinned tag. Consumers inside this org pin a release tag rather than
follow the default branch. Without Nix, put this repository and the two test
dependencies somewhere ASDF can see them, then:

```lisp
(load "scripts/bootstrap.lisp")
(cl-tty-kit/bootstrap:load-core-system)
```

See [Installation](https://nerima-lisp.github.io/cl-tty-kit/installation/) for
the full setup, including the non-Nix path.

## Documentation

- [Quick Start](https://nerima-lisp.github.io/cl-tty-kit/quick-start/) — the smallest end-to-end render
- [Screen and Rendering](https://nerima-lisp.github.io/cl-tty-kit/screen-and-rendering/) — the screen model and the diff renderer
- [Input Decoding](https://nerima-lisp.github.io/cl-tty-kit/input-decoding/) — turning terminal bytes into key events
- [API Reference](https://nerima-lisp.github.io/cl-tty-kit/api-reference/) — every exported symbol, by subsystem
- [Compatibility](https://nerima-lisp.github.io/cl-tty-kit/compatibility/) — why SBCL-only, and the API stability guarantee

## Development

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
nix run .#test       # run the test suite
nix flake check      # tests + paredit-lint + formatting + docs, the same gate CI uses
nix fmt              # format Nix sources (treefmt)
```

Tests live in `t/` and run under
[cl-weave](https://github.com/nerima-lisp/cl-weave), the org's test framework;
`nix run .#test` is the supported bounded test entry point. The Lisp-level
script remains useful for debugger sessions. See
[Development](https://nerima-lisp.github.io/cl-tty-kit/development/) for the
coverage, example-smoke and source-registry scripts, and
[Quality Gates](https://nerima-lisp.github.io/cl-tty-kit/quality-gates/) for
the bar a patch has to clear.

The renderer keeps public screen access checked, while its private full-frame
and diff loops traverse the screen's backing vector directly. It reuses a
preallocated diff plan and copies only its recorded changed runs into the
private front buffer after a sparse render. This avoids a second comparison
pass, temporary render-part lists, and a full-frame buffer copy for sparse
updates. The rendered byte stream is unchanged.

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).
