# Roadmap

`cl-tty-kit` is intentionally scoped to terminal primitives. This file records
what is intentionally deferred so the repository stays honest about its
boundaries.

## Deferred on purpose

- full terminal emulation
- window manager or multiplexer behavior
- editor UI
- shell application logic
- CLI framework behavior
- event bus or general application runtime
- broad utility helpers unrelated to TTY work

## Possible future improvements

- richer diff rendering strategies for large screens
- more examples for embedding the library in real terminal tools

## Deferred capabilities from the feature audit

`docs/FEATURE-AUDIT.md` is the comprehensive enumeration of the terminal-toolkit
capability space, marking each item DONE / GAP / DEFERRED across three passes
(domain knowledge, a research-backed diff against crossterm/ratatui, notcurses,
tcell/termbox2, rich/prompt_toolkit/blessed, and a pass closing the feasible
deferrals). Every in-scope gap it found was implemented; what remains
deliberately deferred, with rationale:

- **Wide-cell skip flag** — a design alternative to the spacer-cell model already
  used for double-width glyphs, not a capability gap.
- **Kitty graphics protocol** — `format-sixel` already covers bitmap output on
  the widely supported format; a second image mechanism would duplicate it.
- **Non-SBCL portability** — would require shipping the Unicode tables the library
  borrows from `sb-unicode`, against the intentionally-small ethos.

Every decodable/feasible item from the audit has been implemented (across nine
waves and five enumeration passes) -- including, after re-examination,
grapheme-cluster segmentation, constraint-based `layout-split`, the full kitty
input surface (event kinds, associated text, shifted/base-layout alternates), the
CSI in-place editing escapes, and `format-sixel` graphics. What is left above is
deferred on principle, not effort.

## Principle

Every new feature should stay small, testable, and aligned with terminal
primitives rather than application framework behavior.

