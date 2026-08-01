# Architecture

`src/` is flat, and each file holds one concern. The split exists so the pure
logic — everything that turns data into data — can be tested without a
terminal, while the code that actually talks to the OS stays small enough to
audit. See [Compatibility](compatibility.md) for why that boundary is drawn
where it is.

## The layers

| Layer | Files | OS access |
| --- | --- | --- |
| Conditions | `conditions.lisp` | none |
| Utilities and codecs | `clamp.lisp`, `string-empty.lisp`, `utf8.lisp` | none |
| Character width | `char-width.lisp`, `char-width-data.lisp` | none |
| Text layout | `text-layout.lisp` | none |
| Color, widgets, geometry | `color.lisp`, `format.lisp`, `rect.lisp` | none |
| ANSI sequences | `ansi.lisp`, `ansi-control.lisp`, `ansi-osc.lisp`, `sixel.lisp` | none |
| Input decoding | `key-tables.lisp`, `keys.lisp`, `keys-decode*.lisp`, `input-state.lisp`, `input-decode*.lisp`, `mouse.lisp` | none |
| Screen and cells | `cell.lisp`, `screen.lisp`, `screen-regions.lisp`, `screen-text.lisp`, `box.lisp`, `cursor.lisp` | none |
| Rendering | `render-style.lisp`, `sgr-parse.lisp`, `render-commands.lisp`, `render-diff-plan.lisp`, `render-diff.lisp`, `render.lisp`, `renderer.lisp` | none |
| Raw mode and size | `raw-mode.lisp`, `raw-mode-sbcl.lisp`, `terminal-size.lisp` | **SBCL-specific** |
| Session lifecycle | `session.lisp` | **SBCL-specific** |
| PTY | `pty.lisp`, `pty-fd.lisp` | **SBCL-specific** |

Only the last three rows touch the operating system. Everything above them is
a function from values to values, which is why the test suite can assert on
exact escape-sequence output and decoded event shapes without allocating a
terminal.

## Notable boundaries

`conditions.lisp` defines the public condition types, the `%assert`
validation macro that the rest of the library signals through (so an invalid
argument produces a typed condition with the offending value rather than a
generic error), and two macros that declare a whole `%assert-*` validation
helper in one form: `define-simple-assert` for a helper that validates as a
pure side effect, and `define-validating-assert` for one that also returns
its checked argument so the call composes as an expression. Most
argument-validating helpers across `src/` are one of these two shapes; a
helper with real control flow beyond that (composing several checks,
dispatching on a `case`) stays a plain `defun`. See
[Conditions](conditions.md).

`char-width.lisp` expresses width as relations over the East Asian and
combining-mark data tables in `char-width-data.lisp`, which keeps the tables
reviewable as data and the policy (including the East Asian ambiguous-width
switch) reviewable as code. See [Text Layout](../guide/text-layout.md).

The ANSI layer is split three ways because the sequence families have
different shapes: `ansi.lisp` builds the core SGR and cursor strings,
`ansi-control.lisp` the scroll/mode control sequences, and `ansi-osc.lisp`
the OSC string-terminated ones. See [ANSI Helpers](../guide/ansi-helpers.md).

Rendering separates the *decision* from the *emission*:
`render-commands.lisp` and `render-diff.lisp` decide which cells changed and
what to do about it, and `render-style.lisp` turns a normalized style into
bytes. That is what lets `t/properties-test.lisp` assert the property that matters
— a diff's visible result matches a full repaint, and is never longer than
one — instead of pinning a byte-for-byte transcript. See
[Screen and Rendering](../guide/screen-and-rendering.md).

`render-diff-plan.lisp` owns the reusable packed diff operation plan and
changed-cell snapshot application, while `render-diff.lisp` owns ANSI
emission and strategy.

`pty.lisp` wraps the SBCL process and stream; `pty-fd.lisp` sits alongside it
as a byte-transparent layer over the bare master file descriptor, for callers
running their own `select(2)` loop over many descriptors. See [PTY](../guide/pty.md).

## See also

- [feature audit note](https://github.com/nerima-lisp/cl-tty-kit/blob/main/docs/notes/feature-audit.md) — what exists, what was deferred, and why
- [API Reference](api.md) — every exported symbol, by subsystem
- [Quality Gates](../project/quality-gates.md) — the file-organization policy this split follows
