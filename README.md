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
[Examples](https://nerima-lisp.github.io/cl-tty-kit/guide/examples/).

## Shell integration, terminal queries, and grapheme clusters

Added in 1.8.0: the kit builds the sequences a shell prompt emits and parses the
replies a terminal sends back. Every builder returns a string; nothing is
written to the terminal until you write it.

- OSC 133 prompt marks: `ansi-prompt-start`, `ansi-command-start`,
  `ansi-command-output-start`, `ansi-command-finished`.
- OSC 7 working directory: `ansi-set-working-directory`.
- Desktop notifications over OSC 777, OSC 9, or kitty's OSC 99: `ansi-notify`
  with `:protocol`.
- Queries and their reply decoders: XTVERSION (`ansi-request-terminal-version`,
  `decode-terminal-version`), DECRQM/DECRPM (`ansi-request-mode`,
  `decode-mode-report`), and kitty keyboard flags
  (`ansi-request-keyboard-enhancements`,
  `decode-keyboard-enhancements-report`).

For grapheme clusters, `next-grapheme-boundary`, `do-grapheme-boundaries`,
`grapheme-boundaries` (with `:into`), and `string-display-width` walk a string
without allocating, using the same width table as `string-width`. See
[Text Layout](https://nerima-lisp.github.io/cl-tty-kit/guide/text-layout/) and
[ANSI Helpers](https://nerima-lisp.github.io/cl-tty-kit/guide/ansi-helpers/).

## Install

The core `cl-tty-kit` system is dependency-free, but its test system depends on
[`cl-prolog-kit`](https://github.com/nerima-lisp/cl-prolog-kit) and
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

See [Getting Started](https://nerima-lisp.github.io/cl-tty-kit/getting-started/) for
the full setup, including the non-Nix path.

## Documentation

- [Getting Started](https://nerima-lisp.github.io/cl-tty-kit/getting-started/) — install, then the smallest end-to-end render
- [Animation](https://nerima-lisp.github.io/cl-tty-kit/guide/animation/) — deterministic and real-time tick loops, including timing events
- [Screen and Rendering](https://nerima-lisp.github.io/cl-tty-kit/guide/screen-and-rendering/) — the screen model and the diff renderer
- [Input Decoding](https://nerima-lisp.github.io/cl-tty-kit/guide/input-decoding/) — turning terminal bytes into key events
- [API Reference](https://nerima-lisp.github.io/cl-tty-kit/reference/api/) — every exported symbol, by subsystem
- [Compatibility](https://nerima-lisp.github.io/cl-tty-kit/reference/compatibility/) — why SBCL-only, and the API stability guarantee

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
[Development](https://nerima-lisp.github.io/cl-tty-kit/project/development/) for the
coverage, example-smoke and source-registry scripts, and
[Quality Gates](https://nerima-lisp.github.io/cl-tty-kit/project/quality-gates/) for
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
