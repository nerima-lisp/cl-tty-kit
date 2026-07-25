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

See [Compatibility](compatibility.md) for the parallel, narrower deferral of
multi-implementation (non-SBCL) support.

## Possible future improvements

- richer diff rendering strategies for large screens
- more examples for embedding the library in real terminal tools

## Deferred capabilities from the feature audit

[Feature Audit](feature-audit.md) is the comprehensive enumeration of the
terminal-toolkit capability space, marking each item DONE / GAP / DEFERRED
across three research passes (domain knowledge, a diff against
crossterm/ratatui, notcurses, tcell/termbox2, and Python's
rich/prompt_toolkit/blessed, plus a pass closing the feasible deferrals).
Every in-scope gap it found was implemented; what remains deliberately
deferred, with rationale:

- **Wide-cell skip flag** — a design alternative to the spacer-cell model
  already used for double-width glyphs, not a capability gap.
- **Kitty graphics protocol** — `format-sixel` (see [Widgets](widgets.md))
  already covers bitmap output on the widely supported format; a second
  image mechanism would duplicate it.
- **Non-SBCL portability** — would require shipping the Unicode tables the
  library borrows from `sb-unicode`, against the intentionally-small ethos.

Every decodable/feasible item from the audit has been implemented — across
nine waves and five enumeration passes — including grapheme-cluster
segmentation, constraint-based `layout-split`, the full kitty input surface
(event kinds, associated text, shifted/base-layout alternates), the CSI
in-place editing escapes, and `format-sixel` graphics. What remains above is
deferred on principle, not effort.

## Principle

Every new feature should stay small, testable, and aligned with terminal
primitives rather than application framework behavior.
