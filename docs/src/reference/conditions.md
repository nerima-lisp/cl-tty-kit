# Conditions

All error conditions in `cl-tty-kit` descend from a single base, `tty-kit-error`,
and are defined in `src/conditions.lisp`. Each carries structured slots (with
reader functions) so callers can inspect *what* failed programmatically, not just
read a formatted message.

!!! note "Design principle: signal, don't silently degrade"
    A repository quality gate (see [Quality Gates](../project/quality-gates.md)) requires that
    *unsupported implementation paths must signal `unsupported-feature` instead
    of silently degrading*. When a runtime feature cannot be provided, the
    library raises a specific condition rather than returning a plausible-looking
    wrong value. Argument validation is equally strict — invalid coordinates,
    dimensions, or byte sequences are rejected at the boundary.

## Hierarchy

```text
error
└── tty-kit-error                (base for everything below)
    ├── unsupported-feature
    ├── invalid-utf8-sequence
    ├── unsupported-code-point
    ├── screen-index-out-of-bounds
    ├── screen-dimensions-invalid
    ├── cursor-parameter-invalid
    ├── raw-mode-operation-failed
    └── pty-operation-failed
```

Catch `tty-kit-error` to handle any library error by base type. (An internal,
unexported guard condition, `input-buffer-exceeded`, also inherits from
`tty-kit-error` so it is catchable by base type, but it is not part of the
documented public symbol set.)

## `tty-kit-error`

The abstract base condition. It has no slots; its only role is to give every
library error a common supertype.

## `unsupported-feature`

Raised when an operation is not available in the current implementation.

| Slot | Reader | Value |
| --- | --- | --- |
| feature | `unsupported-feature-feature` | keyword naming the missing feature |

Signaled via the internal `unsupported` helper. Because the whole library
requires SBCL, this is what the non-SBCL stubs of the OS-facing layers raise:
the raw-mode operations signal it with `:raw-mode` (`src/raw-mode.lisp`), and
every PTY entry point signals it with `:pty` (`src/pty.lisp`, `src/pty-fd.lisp`)
when loaded on an unsupported implementation.

## `invalid-utf8-sequence`

Raised when terminal input cannot be decoded as UTF-8.

| Slot | Reader | Value |
| --- | --- | --- |
| position | `invalid-utf8-sequence-position` | octet index where decoding failed |
| octet | `invalid-utf8-sequence-octet` | offending octet, or `nil` when none applies |
| reason | `invalid-utf8-sequence-reason` | keyword: `:non-octet`, `:overlong-sequence`, `:surrogate-half`, `:code-point-too-large`, `:truncated-sequence`, `:invalid-leading-byte` |

Signaled throughout the UTF-8 decoder (`src/utf8.lisp`, via
`%signal-invalid-utf8-sequence`) when a byte vector from the terminal is
malformed. Streaming decoders buffer partial code units across reads, so a split
read does not raise this until the caller flushes.

## `unsupported-code-point`

Raised when a character cannot be represented in the current terminal.

| Slot | Reader | Value |
| --- | --- | --- |
| code-point | `unsupported-code-point-code-point` | the Unicode code point |

Signaled from UTF-8 transcoding (`src/utf8.lisp`) and from key decoding
(`src/keys-decode-internals.lisp`) when a code point is out of range for the
current encoding path.

## `screen-index-out-of-bounds`

Raised when a screen coordinate lies outside the screen bounds.

| Slot | Reader | Value |
| --- | --- | --- |
| screen | `screen-index-out-of-bounds-screen` | the screen that reported the access |
| x | `screen-index-out-of-bounds-x` | offending column |
| y | `screen-index-out-of-bounds-y` | offending row |
| width | `screen-index-out-of-bounds-width` | screen width |
| height | `screen-index-out-of-bounds-height` | screen height |

Signaled from cell access and region operations (`src/screen.lisp`,
`src/screen-regions.lisp`) when a coordinate falls outside the grid — for
example an out-of-range `screen-cell` or `screen-put-cell`.

## `screen-dimensions-invalid`

Raised when screen dimensions are not non-negative integers.

| Slot | Reader | Value |
| --- | --- | --- |
| width | `screen-dimensions-invalid-width` | width value that failed validation |
| height | `screen-dimensions-invalid-height` | height value that failed validation |

Signaled from `make-screen` / resize validation (`src/screen.lisp`) when a
supplied width or height is not a valid non-negative integer.

## `cursor-parameter-invalid`

Raised when a cursor coordinate, bound, or visibility value is invalid.

| Slot | Reader | Value |
| --- | --- | --- |
| parameter | `cursor-parameter-invalid-parameter` | name of the rejected parameter |
| value | `cursor-parameter-invalid-value` | the rejected value |
| expected | `cursor-parameter-invalid-expected` | description of the required contract |

Signaled from cursor construction and setters (`src/cursor.lisp`).
Coordinates must be non-negative integers (expected: *"a non-negative integer"*)
and `cursor-visible-p` accepts only booleans (expected: *"a boolean"*).

## `raw-mode-operation-failed`

Raised when switching a terminal file descriptor into or out of raw mode fails.

| Slot | Reader | Value |
| --- | --- | --- |
| operation | `raw-mode-operation-failed-operation` | `:enable` or `:disable` |
| fd | `raw-mode-operation-failed-fd` | the file descriptor |
| reason | `raw-mode-operation-failed-reason` | underlying condition |

Signaled via `%signal-raw-mode-operation-failed` from the SBCL raw-mode layer
(`src/raw-mode-sbcl.lisp`) when the underlying `tcgetattr`/`tcsetattr` fails —
`:enable` on entry, `:disable` on restore.

## `pty-operation-failed`

Raised when a PTY operation fails.

| Slot | Reader | Value |
| --- | --- | --- |
| operation | `pty-operation-failed-operation` | `:spawn`, `:read`, `:write`, etc. |
| pty | `pty-operation-failed-pty` | the PTY object, or `nil` for spawn failures |
| reason | `pty-operation-failed-reason` | underlying condition |

Signaled via `%signal-pty-operation-failed` from the PTY layer (`src/pty.lisp`).
Spawn failures report `:spawn` with a `nil` PTY slot because no PTY object was
created; read and write failures (including closed-stream cases after shutdown)
report `:read` or `:write`. Hard OS errors from the fd-centric layer are wrapped
here too. `close-pty` is idempotent and always clears the stored process and
stream, even when shutdown itself fails.

## See also

- [API Reference](api.md) — the full condition symbol list in context
- [Terminal Session and Raw Mode](../guide/terminal-session.md) — where raw-mode errors arise
- [PTY](../guide/pty.md) — PTY lifecycle and the failures it can raise
- [Input Decoding](../guide/input-decoding.md) — where UTF-8 and code-point errors arise
