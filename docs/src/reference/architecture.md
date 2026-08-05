# Architecture

`src/` is flat, and each file holds one concern. The split exists so the pure
logic — everything that turns data into data — can be tested without a
terminal, while the code that actually talks to the OS stays small enough to
audit. See [Compatibility](compatibility.md) for why that boundary is drawn
where it is.

## The layers

| Layer | Files | OS access |
| --- | --- | --- |
| Conditions | `conditions.lisp`, `condition-types.lisp` | none |
| Utilities and codecs | `clamp.lisp`, `string-empty.lisp`, `utf8.lisp` | none |
| Character width | `char-width.lisp`, `char-width-data.lisp` | none |
| Text layout | `text-layout.lisp`, `text-wrap.lisp` | none |
| Color, widgets, geometry | `color.lisp`, `color-space.lisp`, `format.lisp`, `rect.lisp`, `layout.lisp` | none |
| ANSI sequences | `ansi.lisp`, `ansi-style.lisp`, `ansi-control.lisp`, `ansi-osc.lisp`, `sixel.lisp`, `kitty-image.lisp` | none |
| Input decoding | `key-tables.lisp`, `keys.lisp`, `csi-field-parsing.lisp`, `keys-decode*.lisp`, `input-state.lisp`, `input-decode*.lisp`, `mouse.lisp` | none |
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

`conditions.lisp` is the condition/validation macro DSL: the `%assert`
macro every signal in the library goes through (so an invalid argument
produces a typed condition with the offending value rather than a generic
error), `define-simple-assert`/`define-validating-assert` for declaring a
whole `%assert-*` validation helper in one form (the pure-side-effect and
returns-its-checked-argument shapes respectively -- most argument-validating
helpers across `src/` are one of these two; a helper with real control flow
beyond that, composing several checks or dispatching on a `case`, stays a
plain `defun`), `define-tty-kit-condition`/`define-formatted-tty-kit-condition`
for declaring a whole condition class in one form, and `document-function`
for the `(setf (documentation 'name 'function) ...)` shape a `defstruct`
accessor (or any function whose definition form has no docstring slot of its
own) needs -- one macro instead of the same three-symbol boilerplate at each
of the 33 call sites across `src/`. `condition-types.lisp` is this file's
data: every condition class this library actually signals, built on those
macros -- the policy/data split runs through this pair the same way it does
for `char-width.lisp`/`char-width-data.lisp` below. See
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

`input-decode-internals.lisp`'s `%decode-plain-events` and `%decode-paste-events`
each walk a chunk once, calling a continuation per decoded event instead of
building a list themselves; `%collect-plain-events`/`%collect-paste-events` are
the thin list-collecting policies on top of them. This is the same shape
`text-wrap.lisp`'s `%call-with-wrapped-lines` and `tick-loop.lisp`'s
`advance`/`render`/`stop` callbacks already use elsewhere in `src/`: separate
the one walk over the input from what a caller does with each result, so a
future streaming consumer does not need a second walk.

Every internal helper that is never passed as a first-class value (never
`#'name`, never handed to `mapcar`/`funcall`/`apply`) and never recursive is a
`defmacro`, not a `defun`. This is a standing policy for all of `src/` going
forward, not a closed list of past conversions: `clamp.lisp`, `color.lisp`,
`color-space.lisp`, `layout.lisp`, `text-layout.lisp`, `text-wrap.lisp`, and
the CSI-parameter validators in `ansi.lisp`/`ansi-style.lisp` are where it
has already been applied, and the rest of `src/` is expected to follow the
same rule as it is touched. Each such macro wraps its original body in a
`let` that binds its parameters to the (unevaluated, backquote-spliced)
argument forms -- evaluated once, in the same left-to-right order a function
call already used, so this changes nothing about calling behavior. What it
does *not* apply to: any of `src/`'s 132 exported functions (breaking
`#'name`/`funcall` for public API is a compatibility break other
`nerima-lisp` repositories that depend on this library would hit), anything
passed as a value even internally (there are 8 of these, found by scanning
every `#'name`/`(function name)` occurrence across `src/`, `t/`, and
`examples/`), and anything recursive or using `return-from` against its own
name (a `defmacro`'s expansion has no implicit block the way `defun` does).

Before landing a new conversion, run the three-hazard verification
documented in
[Quality Gates](../project/quality-gates.md#macro-usage-and-file-organization):
compile-time-literal risk on a typed struct slot, hygiene/capture risk in
the macro's own bindings, and `:serial t` load-order risk. These are not
optional -- skipping them is how a prior broad conversion sweep introduced
5 bugs that only running the test suite caught, none of them at
`compile-file` time.

## See also

- [feature audit note](https://github.com/nerima-lisp/cl-tty-kit/blob/main/docs/notes/feature-audit.md) — what exists, what was deferred, and why
- [API Reference](api.md) — every exported symbol, by subsystem
- [Quality Gates](../project/quality-gates.md) — the file-organization policy this split follows
