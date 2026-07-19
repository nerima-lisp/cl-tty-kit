# cl-tty-kit

[![CI](https://github.com/takeokunn/cl-tty-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/takeokunn/cl-tty-kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

`cl-tty-kit` is a small Common Lisp toolkit for terminal and TTY work.
The goal is to provide a tight, reusable core for building terminal apps
without turning the library into a UI framework or shell.

## Status

- requires SBCL (see [Compatibility](#compatibility)) and intentionally small
- test-backed public API
- PTY support is limited to SBCL
- examples are runnable from `examples/`
- maintainer-grade local quality gates are documented in `docs/QUALITY-GATES.md`
- project governance docs are available in `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, and `SECURITY.md`

## Compatibility

`cl-tty-kit` currently **requires SBCL**. It relies on SBCL-only facilities:
`sb-posix` for terminal control, `sb-unicode` for character-width
classification, and `sb-ext` for UTF-8 transcoding and process/PTY handling.
Loading the system on another Common Lisp implementation fails fast with a
clear "requires SBCL" error rather than a confusing missing-dependency report.

Internally the code is still organized by portability of *concern*, which keeps
the OS-facing surface small and isolated and makes the pure logic easy to test:

- pure logic (no OS calls): ANSI helpers, key/input decoding, character width,
  screen and cursor state, rendering, and the embedded logic engine
- OS-facing, SBCL-specific: raw-mode control, the terminal-session helper, and
  PTY support

Broader multi-implementation support is a possible future direction (see
`ROADMAP.md`); today the supported and tested target is SBCL.

Within a supported (SBCL) build, when an OS-facing runtime feature cannot be
provided, the library signals `unsupported-feature` instead of silently
degrading.

## What it provides

- raw mode helpers for SBCL
- terminal session lifecycle helper
- ANSI escape sequence helpers
- key-event decoding from terminal input
- streaming bracketed-paste collection for chunked reads
- Unicode terminal column width for layout (`char-width`, `string-width`)
- a pure screen and cell model
- cursor state helpers
- ANSI rendering and diff rendering
- frame-oriented render helpers that compose screen diffs with final cursor state
- a minimal PTY abstraction for SBCL
- runnable examples for rendering, input decoding, screen diffs, and terminal session lifecycle
- a short roadmap, release process, and change history in `ROADMAP.md`, `RELEASING.md`, and `CHANGELOG.md`
- an explicit repository-local quality gate in `docs/QUALITY-GATES.md`

## Architecture

The implementation is split by concern:

- `src/prolog-bindings.lisp`, `src/prolog-db.lisp`, `src/prolog-engine.lisp`, and
  `src/prolog-primitives.lisp` for the embedded logic engine and its data/logic split
- `src/conditions.lisp` for public condition types and signaling helpers
- `src/clamp.lisp`, `src/string-empty.lisp`, `src/output-utils.lisp`, and `src/utf8.lisp` for reusable utilities and codec helpers
- `src/char-width.lisp` for Unicode terminal column width, expressed as width
  relations over East Asian and combining-mark data tables in `src/char-width-data.lisp`
- `src/raw-mode.lisp` for SBCL-specific terminal mode control
- `src/ansi.lisp` for escape-sequence string builders
- `src/key-tables.lisp` for key decoding tables and `src/keys.lisp`, `src/input-state.lisp`, and `src/input-decode.lisp` for decoding logic
- `src/cell.lisp` for cell/style data, `src/screen.lisp` and `src/cursor.lisp` for state transitions, `src/render-style.lisp` for ANSI style emission, and `src/render.lisp` for repaint/diff output
- `src/pty.lisp` for the SBCL PTY wrapper

The pure parts stay easy to test, while platform-specific code is isolated.

## API Overview

The public API is intentionally small and grouped by subsystem.

### Conditions

- `tty-kit-error`
- `unsupported-feature`
- `unsupported-feature-feature`
- `invalid-utf8-sequence`
- `invalid-utf8-sequence-position`
- `invalid-utf8-sequence-octet`
- `invalid-utf8-sequence-reason`
- `raw-mode-operation-failed`
- `raw-mode-operation-failed-operation`
- `raw-mode-operation-failed-fd`
- `raw-mode-operation-failed-reason`
- `pty-operation-failed`
- `pty-operation-failed-operation`
- `pty-operation-failed-pty`
- `pty-operation-failed-reason`
- `screen-index-out-of-bounds`
- `screen-index-out-of-bounds-screen`
- `screen-index-out-of-bounds-x`
- `screen-index-out-of-bounds-y`
- `screen-index-out-of-bounds-width`
- `screen-index-out-of-bounds-height`
- `screen-dimensions-invalid`
- `screen-dimensions-invalid-width`
- `screen-dimensions-invalid-height`
- `cursor-parameter-invalid`
- `cursor-parameter-invalid-parameter`
- `cursor-parameter-invalid-value`
- `cursor-parameter-invalid-expected`
- `unsupported-code-point`
- `unsupported-code-point-code-point`

### Raw mode

- `enable-raw-mode`
- `disable-raw-mode`
- `with-raw-mode`

### Terminal session

- `with-terminal-session`

### ANSI helpers

- `ansi-move-cursor`
- `ansi-clear-screen`
- `ansi-clear-line`
- `ansi-hide-cursor`
- `ansi-show-cursor`
- `ansi-enter-alternate-screen`
- `ansi-exit-alternate-screen`
- `ansi-enable-bracketed-paste`
- `ansi-disable-bracketed-paste`
- `ansi-set-keyboard-enhancements`
- `ansi-push-keyboard-enhancements`
- `ansi-pop-keyboard-enhancements`
- `ansi-bold`
- `ansi-reset-style`

### Input decoding

- `key-event`
- `make-key-event`
- `key-event-type`
- `key-event-code`
- `key-event-modifiers`
- `input-decoder`
- `make-input-decoder`
- `decode-input`
- `decode-input-chunk`
- `decode-key-sequence`
- `flush-input-decoder`

### Character width

- `char-width`
- `string-width`

### Screen and cells

- `cell`
- `make-cell`
- `cell-char`
- `cell-style`
- `make-style`
- `style-fg`
- `style-bg`
- `copy-cell`
- `screen`
- `make-screen`
- `screen-width`
- `screen-height`
- `screen-cells`
- `screen-cell`
- `screen-resize`
- `screen-clear`
- `screen-put-cell`
- `screen-fill-rect`
- `screen-write-string`

### Cursor and rendering

- `cursor`
- `make-cursor`
- `cursor-x`
- `cursor-y`
- `cursor-visible-p`
- `move-cursor`
- `render-screen`
- `render-cursor`
- `render-diff`
- `render-frame`
- `render-frame-diff`

`make-cursor`, `move-cursor`, and the exported cursor setters require
non-negative integer coordinates. `cursor-visible-p` only accepts booleans.
Invalid cursor coordinates, bounds, or visibility values signal
`cursor-parameter-invalid` with the parameter name, rejected value, and
expected contract. `render-cursor` turns a `cursor` object into ANSI output,
so callers can explicitly compose final cursor placement and visibility with
`render-screen` or `render-diff`. `render-frame` and `render-frame-diff`
provide that composition directly, including the common "diff plus final
cursor restore" path for app render loops.

### PTY

- `pty`
- `make-pty`
- `pty-process`
- `pty-stream`
- `pty-read`
- `pty-write`
- `close-pty`

If PTY startup, shutdown, reads, or writes fail, `make-pty`, `close-pty`,
`pty-read`, and `pty-write` signal `pty-operation-failed` with the operation
and underlying condition. Spawn failures report `:spawn` and use `nil` for the
PTY slot because no PTY object was created. Read and write failures report
`:read` or `:write`, including closed-stream cases after shutdown. `close-pty`
is idempotent and always clears the stored process and stream, even when
shutdown itself fails, since the stream is already closed at the OS level by
that point.

`make-pty`'s `PROGRAM` is resolved against `PATH` and `ARGS`/`ENVIRONMENT` are
passed straight through to the spawned process (`sb-ext:run-program :search
t`) — this is the intended API surface, but it means callers who forward
attacker-influenced strings into `PROGRAM`, `ARGS`, or `ENVIRONMENT` are
choosing to let that data drive process execution; `make-pty` does not
sanitize them.

PTY support is part of the OS-facing, SBCL-specific layer (see
[Compatibility](#compatibility)); the whole library requires SBCL, so `make-pty`
and `close-pty` are available on every build that loads.

## Installation

Put the repository in a place ASDF can see, for example:

```text
~/quicklisp/local-projects/cl-tty-kit/
```

Then load the repository-local bootstrap and core sources:

```lisp
(load "scripts/bootstrap.lisp")
(cl-tty-kit/bootstrap:load-core-system)
```

## Quick Start

```lisp
(use-package :cl-tty-kit)

(let ((screen (make-screen 20 4)))
  (screen-write-string screen 0 0 "Hi")
  (format t "~A~%" (render-screen screen)))
```

More examples live in `examples/`:

- `examples/simple-render.lisp`: full repaint of a small screen
- `examples/styled-render.lisp`: styled cells with modifier, foreground, and background ANSI output
- `examples/key-decoding.lisp`: decode printable, modified, and paste-related input events
- `examples/streaming-paste.lisp`: collect a bracketed paste block across streaming input chunks
- `examples/frame-render.lisp`: compose a frame render with an explicit final cursor state
- `examples/screen-update.lisp`: diff two screens and emit only the changed cells
- `examples/event-loop.lisp`: compose a deterministic terminal event loop from streaming decode and diff rendering
- `examples/terminal-session.lisp`: scope alternate-screen lifecycle, cursor visibility, and input modes
- `examples/status-dashboard.lisp`: render an initial dashboard frame followed by incremental updates

## Core Concepts

### Screen model

`screen` is a pure grid of `cell` objects. The screen API is intentionally
small so the data model stays easy to test and reuse.

`make-screen` and `screen-clear` accept either a `cell` template or a single
character, which keeps common setup and reset paths straightforward.
`screen-resize` updates an existing screen in place, preserving the overlapping
top-left region and filling any new area from a supplied template or blank
cells.
`screen-put-cell` also respects an explicit `:style nil`, so callers can clear
styling when replacing an existing cell.
`screen-write-string` builds on `screen-put-cell` for the common case of laying
out text runs, with optional `:style`, `:start`, and `:end` arguments for
partial writes. It advances the column by each character's `char-width`
rather than by one column per character, so a double-width character (a CJK
ideograph or common emoji) also fills the column after it with a blank
spacer cell — keeping the grid's column count aligned with what a real
terminal displays, and making the bounds check ("does this run fit?") a
display-width check rather than a character count.
`screen-fill-rect` applies the same cell/template semantics to rectangular
regions, which keeps higher-level drawing code data-oriented instead of
spelling out nested update loops at each call site.
Out-of-bounds access signals `screen-index-out-of-bounds`, which includes the
screen dimensions and the offending coordinates.
Invalid dimensions passed to `make-screen` signal `screen-dimensions-invalid`,
which includes the width and height that failed validation.

`make-style` builds normalized style lists from modifier keywords such as
`:bold`, `:italic`, `:underline`, `:dim`, and `:reverse`, plus color entries
constructed with `style-fg` and `style-bg`. Those helpers accept either an
indexed color (`(style-fg 196)`) or RGB bytes (`(style-bg 17 34 51)`).
`cell-style` returns that normalized representation, which is still a plain
list containing modifiers and `(:fg ...)` / `(:bg ...)` entries. The renderer
emits ANSI styling for supported entries and resets the style after each
styled cell. Unsupported style keywords or malformed raw color entries are
ignored by rendering and diff generation. Style lists are normalized so
equivalent style sets compare consistently; modifiers are deduplicated and the
last valid foreground/background entry wins.

### Input decoding

`decode-input` turns terminal input into a list of `key-event` objects.
It handles printable characters, control bytes such as `C-c`, `Tab`, and
`Enter`, UTF-8 byte vectors, arrow keys, SS3 application-cursor sequences,
modified CSI sequences, alt prefixes, common CSI `~` keys such as
insert/delete/page up/page down/F1-F12, bracketed paste markers, and
kitty/fixterms-style CSI `u` sequences for Unicode characters plus a tested
set of extended special keys including menu, F13-F35, keypad navigation and
editing keys, media transport keys, and left/right modifier keys. Malformed
UTF-8 byte vectors signal
`invalid-utf8-sequence`. Incomplete or malformed escape sequences are not
partially reinterpreted as synthetic special keys; they fall back to a literal
`ESC` event followed by the remaining characters.

For streaming terminal reads, use `make-input-decoder` with
`decode-input-chunk`. The decoder buffers trailing partial UTF-8 code units and
incomplete escape sequences across read boundaries, so split reads do not emit
spurious `ESC` or invalid UTF-8 errors until the caller decides to flush.
`flush-input-decoder` forces the buffered tail through the one-shot fallback
rules, which is useful at EOF or when a transport closes.

One-shot `decode-input` keeps bracketed paste visible as `:paste-start` and
`:paste-end` marker events. If a streaming reader wants a single payload event
instead, construct the decoder with `:collect-bracketed-paste t`; completed
paste blocks are then emitted as `#S(KEY-EVENT :TYPE :PASTE :CODE <string>
:MODIFIERS NIL)`. If EOF arrives before `ESC [ 201 ~`, flushing falls back to
the raw marker-plus-characters stream so no input is discarded or invented.
`examples/event-loop.lisp` shows the next step up: feeding chunked input
through a decoder, updating application state, and rendering each state
transition as an incremental frame.

```lisp
(let ((decoder (make-input-decoder)))
  (decode-input-chunk decoder (string #\Esc))
  (decode-input-chunk decoder "[A"))
;; => (#S(KEY-EVENT :TYPE :SPECIAL :CODE :UP :MODIFIERS NIL))
```

```lisp
(let ((decoder (make-input-decoder :collect-bracketed-paste t)))
  (decode-input-chunk decoder (concatenate 'string (string #\Esc) "[200~"))
  (decode-input-chunk decoder "hello")
  (decode-input-chunk decoder (concatenate 'string (string #\Esc) "[201~")))
;; => (#S(KEY-EVENT :TYPE :PASTE :CODE "hello" :MODIFIERS NIL))
```

### Character width

A terminal cell is a column, not a character. `char-width` returns how many
columns a character occupies: control characters and zero-width combining marks
return 0, East Asian wide/fullwidth code points and common emoji return 2, and
everything else returns 1. `string-width` sums those widths across a string, so
callers can align text that mixes ASCII, CJK, and emoji.

```lisp
(char-width #\A)                          ; => 1
(char-width (code-char #x65E5))           ; => 2  (CJK ideograph)
(string-width "ab")                       ; => 2
```

### Design: relations and continuations

The toolkit ships a small, self-contained embedded logic engine, split across
`src/prolog-bindings.lisp`, `src/prolog-db.lisp`, `src/prolog-engine.lisp`, and
`src/prolog-primitives.lisp`, and exposed as the `cl-tty-kit/prolog` package
(nickname `tty-prolog`). It provides unification with an occurs check, a
continuation-passing resolver with branch-local cycle detection and
ground-goal failure memoization, and an explicit clause database. Rules are
kept separate from the plain data tables they reason about (width ranges, key
decoding tables, style codes), so the classification logic can be expressed as
relations while the data stays ordinary Lisp.

The engine is a first-class part of the public API. `install-standard-primitives`
installs the relational combinators `and/*`, `or/*`, and `not/1`, unification
`=/2`, and the advanced predicates `true/0`, `fail/0`, meta-call `call/1`, and
aggregation `findall/3`. Clauses are added in O(1) amortized time, so large
rule sets load in linear time.

```lisp
(let ((db (tty-prolog:install-standard-primitives (tty-prolog:make-clause-db))))
  (tty-prolog:define-clauses db
    ((parent abraham isaac))
    ((parent isaac jacob))
    ((parent jacob joseph))
    ((ancestor ?a ?b) (parent ?a ?b))
    ((ancestor ?a ?b) (parent ?a ?c) (ancestor ?c ?b)))
  (tty-prolog:solutions db '(tty-prolog:findall ?d (ancestor abraham ?d) ?ds) '?ds))
;; => ((ISAAC JACOB JOSEPH))
```

For advanced usage beyond this embedded engine — a DCG grammar for the
ECMA-48 CSI byte-class shape, property-based fuzz testing of the untrusted-
input decoders, and bridges to an external ISO Prolog and to a literate
"weave" toolchain — see the opt-in integrations under `contrib/` (not part of
the core build or CI; `contrib/README.md` has the full list).

### ANSI helpers

The ANSI helpers return strings, which makes them easy to compose, inspect,
and test.

Alongside screen and cursor controls, the package exposes explicit input-mode
sequences for bracketed paste and kitty keyboard progressive enhancement.
`ansi-enable-bracketed-paste` / `ansi-disable-bracketed-paste` emit the
standard DEC private mode toggles, `ansi-set-keyboard-enhancements` emits a
direct `CSI = flags ; mode u` request, and the push/pop helpers provide a
scoped `CSI u` stack for callers that want automatic restoration.

`render-diff` emits only changed cells when the two screens share the same
dimensions, and it can collapse a changed trailing blank suffix into
`ansi-clear-line` for shorter output. When a same-size diff would be longer
than a full repaint, it falls back to `render-screen` instead; it also falls
back to a full redraw when `previous` is `nil` or sized differently.
`render-screen` and `render-diff` intentionally only render cell content; use
`render-cursor` when the final cursor position or visibility is part of the
frame contract.

### Raw mode

`enable-raw-mode` and `disable-raw-mode` are SBCL-specific. They exist as a
small machine-dependent layer, separate from the pure terminal logic.
If terminal state changes fail, they signal `raw-mode-operation-failed` with
the operation, file descriptor, and underlying condition.
Nested `with-raw-mode` or repeated `enable-raw-mode` calls on the same file
descriptor are reference-counted, so the terminal is restored only when the
outermost scope exits successfully.

### Terminal session

`with-terminal-session` is a thin composition helper for terminal lifecycle
code. It can enter the alternate screen, hide the cursor, flush output, and
guarantee restoration with `unwind-protect`. `:bracketed-paste t` scopes paste
markers to the session, and `:keyboard-enhancements <flags>` pushes kitty
keyboard enhancement flags for the duration of the body before automatically
popping them during cleanup. If `:raw-mode t` is supplied, it wraps the
session with `with-raw-mode` using the provided `:fd`.

## Testing

Run the test suite from a fresh checkout with:

```bash
sbcl --script scripts/test.lisp
```

Run the example scripts as a smoke test with:

```bash
sbcl --script scripts/examples.lisp
```

Run a fresh source-registry packaging smoke test with:

```bash
sbcl --script scripts/source-registry-smoke.lisp
```

Run the full verification suite with:

```bash
sbcl --script scripts/verify.lisp
```

`scripts/verify.lisp` runs the repository-local tests, example smoke checks,
and the fresh source-registry packaging smoke in one pass.

Generate an SBCL coverage report for `src/` with:

```bash
sbcl --script scripts/coverage.lisp
```

The canonical test package is `cl-tty-kit/test`. Repository-local scripts are
the supported way to load the code, run tests, and exercise the examples. See
`CONTRIBUTING.md` for the expected verification flow and contribution
guidelines.

## Non-goals

- no shell implementation
- no full terminal emulator
- no widget toolkit
- no opinionated application framework

## Roadmap

The current repository intentionally stops at terminal primitives.
See `ROADMAP.md` for the explicit deferred areas and likely future work.

## License

MIT
