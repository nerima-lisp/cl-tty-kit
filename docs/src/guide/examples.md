# Examples

The `examples/` directory contains ~22 self-contained, runnable programs that
exercise the public API. Each demonstrates a use case you can read as
documentation and run as a smoke test.

## The example pattern

Every example file follows the same shape, so once you have read one you can
read them all:

```lisp
(require :asdf)

;; Load the shared bootstrap, which loads cl-tty-kit if it isn't already.
(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

;; When non-nil (the default), loading the file also runs it.
(defvar *cl-tty-kit-run-example-on-load* t)

(defun simple-render-example ()
  ...)                       ; the demonstration, returning its output

(defun run-simple-render-example ()
  (format t "~A~%" (simple-render-example)))   ; print it

(when *cl-tty-kit-run-example-on-load*
  (run-simple-render-example))
```

Each file exposes a pure `foo-example` function that builds and returns a value,
a `run-foo-example` runner that prints it, and a load-time trigger guarded by
`*cl-tty-kit-run-example-on-load*`. The shared `examples/bootstrap.lisp` loads
the core system once; individual examples never load the library themselves.

!!! tip "Reading vs. running"
    Because the demonstration lives in a plain function that returns a value,
    you can `(load "examples/simple-render.lisp")` to see output immediately, or
    bind `*cl-tty-kit-run-example-on-load*` to `nil` first and call the
    `*-example` function yourself to inspect the return value in a REPL.

## Rendering basics

| File | What it shows |
| --- | --- |
| `simple-render.lisp` | full repaint of a small screen |
| `styled-render.lisp` | styled cells with modifier, foreground, and background ANSI output |
| `frame-render.lisp` | compose a frame render with an explicit final cursor state |
| `screen-update.lisp` | diff two screens and emit only the changed cells |
| `renderer-loop.lisp` | drive a double-buffered renderer, emitting a full paint then a diff-only update |
| `interactive-dashboard.lisp` | run a resize-aware resident TUI with fd readiness and incremental input decoding |
| `status-dashboard.lisp` | render an initial dashboard frame followed by incremental updates |

## Input decoding

| File | What it shows |
| --- | --- |
| `key-decoding.lisp` | decode printable, modified, and paste-related input events |
| `streaming-paste.lisp` | collect a bracketed paste block across streaming input chunks |
| `event-loop.lisp` | compose a deterministic terminal event loop from streaming decode and diff rendering |
| `mouse-decoding.lisp` | decode SGR mouse press, release, wheel, and drag reports |
| `styled-parse.lisp` | recover text and style segments from an ANSI-styled string with `parse-styled-string` |

## Layout, boxes, and dashboards

| File | What it shows |
| --- | --- |
| `boxed-panel.lisp` | frame a rounded box with a title, padded fields, and colored status text |
| `progress-dashboard.lisp` | compose a boxed dashboard with colored progress bars and aligned columns |
| `layout-panels.lisp` | split a frame into bordered panels with a sparkline and a columns table |
| `layout-dashboard.lisp` | lay out a header, sidebar, main, and footer dashboard with `layout-split` constraints |
| `text-panel.lisp` | frame a word-wrapped paragraph under an ellipsized title by display width |

## Color and Unicode

| File | What it shows |
| --- | --- |
| `color-report.lisp` | render a color gradient bar and a table of named color indices and luminance |
| `hsl-rainbow.lisp` | sweep the HSL hue circle across a panel with `hsl-to-rgb` color conversion |
| `graphemes.lisp` | split a mixed string into grapheme clusters and report each cluster's display width |
| `sixel-image.lisp` | encode a small red-to-blue gradient image as a sixel DCS string |

## Terminal lifecycle

| File | What it shows |
| --- | --- |
| `terminal-session.lisp` | scope alternate-screen lifecycle, cursor visibility, and input modes |

## Running the examples

Run every example as a smoke test from a clean checkout:

```bash
nix run .#examples
```

The runner loads the core system once, then loads and runs each example file in
turn, bounded by a per-run timeout so the suite is deterministic. Individual
files can also be loaded directly (`sbcl --script examples/simple-render.lisp`),
since each pulls in the shared bootstrap on its own.

## See also

- [Getting Started](../getting-started.md) — the smallest end-to-end render
- [Screen and Rendering](screen-and-rendering.md) — the model behind the render examples
- [API Reference](../reference/api.md) — every symbol the examples use
