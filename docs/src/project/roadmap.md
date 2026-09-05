# Roadmap

`cl-tty-kit` is intentionally scoped to terminal primitives. This page
records what is intentionally deferred so the project stays honest about its
boundaries.

## Deferred on purpose

- full terminal emulation
- window manager or multiplexer behavior
- editor UI
- shell application logic
- CLI framework behavior
- event bus or general application runtime
- broad utility helpers unrelated to TTY work

See [Compatibility](../reference/compatibility.md) for the parallel, narrower deferral of
multi-implementation (non-SBCL) support.

## Possible future improvements

- richer diff rendering strategies for large screens
- more examples for embedding the library in real terminal tools

## Related nerima-lisp projects, and why these particular ones aren't dependencies

Depending on a `nerima-lisp` sibling is not itself out of scope: `cl-tty-kit`'s
core `:depends-on` already carries `cl-codec-kit` (the UTF-8 codec) and
`cl-concurrent-kit` (raw mode's lock), because each replaces logic
this library would otherwise hand-roll. The projects below are excluded on
their own merits — a dependency cycle, or no call site — not by a blanket rule
against org dependencies.

[`cl-process-kit`](https://github.com/nerima-lisp/cl-process-kit)'s `cl-process-kit/pty`
subsystem already depends on `cl-tty-kit` (for `terminal-size`'s default rows/cols) and
layers session/job-control semantics -- `spawn-pty`, `pty-resize`, session-wide
SIGTERM/SIGKILL -- on top of a native PTY trampoline. A caller wanting that layer should
reach for `cl-process-kit/pty` directly rather than cl-tty-kit growing an equivalent; the
reverse dependency also means `cl-tty-kit` itself must never depend on `cl-process-kit`,
which would create a cycle. `cl-log-kit` (structured logging) and `cl-boundary-kit`
(swappable-fake testing seams for external effects) were evaluated too: both are
application-level concerns with no current call site in this primitives
library, and `cl-boundary-kit`'s own docs are explicit that its process boundary is a
testing seam, not a PTY-shaped runner.

## Deferred capabilities

The [feature audit note](https://github.com/nerima-lisp/cl-tty-kit/blob/main/docs/notes/feature-audit.md) records
the terminal-toolkit capabilities reviewed against this library. Every
in-scope gap was implemented; what remains deferred, with rationale:

- **Wide-cell skip flag** — a design alternative to the spacer-cell model
  already used for double-width glyphs, not a capability gap.
- **Kitty graphics protocol** — `format-sixel` (see [Widgets](../guide/widgets.md))
  already covers bitmap output on the widely supported format; a second
  image mechanism would duplicate it.
- **Non-SBCL portability** — would require shipping the Unicode tables the
  library borrows from `sb-unicode`, against the intentionally-small ethos.

Every decodable/feasible item from the audit has been implemented, including
grapheme-cluster
segmentation, constraint-based `layout-split`, the full kitty input surface
(event kinds, associated text, shifted/base-layout alternates), the CSI
in-place editing escapes, and `format-sixel` graphics. What remains above is
deferred on principle, not effort.

## Principle

Every new feature should stay small, testable, and aligned with terminal
primitives rather than application framework behavior.
