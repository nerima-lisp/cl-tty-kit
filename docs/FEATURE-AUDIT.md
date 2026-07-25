# Feature audit

This document is the **enumeration ("洗い出し") phase**: a systematic sweep of the
capability space of a terminal toolkit, cross-referenced against the established
libraries in the field (notcurses, crossterm, tcell/termbox, blessed, Python
`rich`/`prompt_toolkit`, ncurses), with each capability marked against
`cl-tty-kit`'s actual public API.

Status legend:

- **DONE** — implemented and tested in the public API.
- **GAP** — a reasonable, in-scope capability that was missing; addressed in the
  "wave 5" pass unless noted.
- **DEFERRED** — intentionally out of scope for now, with a rationale. These are
  also recorded in `ROADMAP.md`.

The guiding constraint (see `ROADMAP.md`) is *terminal primitives, SBCL-only,
small and testable* — not an application framework. "Comprehensive" is measured
against that boundary, not against full terminal emulation.

---

## A. Terminal I/O and modes

| Capability | Status | Notes |
|---|---|---|
| Raw mode (enter/leave, nesting) | DONE | `enable-raw-mode`, `disable-raw-mode`, `with-raw-mode` |
| Alternate screen buffer | DONE | `ansi-enter-alternate-screen`, `ansi-exit-alternate-screen` |
| Terminal session lifecycle | DONE | `with-terminal-session` |
| Cursor show/hide | DONE | `ansi-hide-cursor`, `ansi-show-cursor` |
| Bracketed paste mode | DONE | enable/disable + streaming collection |
| Focus reporting | DONE | enable/disable + `:focus-in`/`:focus-out` decode |
| Mouse tracking modes | DONE | `ansi-enable-mouse`/`-disable-mouse` (:normal/:button/:any + SGR) |
| Kitty keyboard enhancement | DONE | `ansi-set/push/pop-keyboard-enhancements` |
| Cursor position query | DONE | `ansi-request-cursor-position` + `decode-cursor-position-report` |
| Terminal bell | GAP → DONE | `ansi-bell` |
| Synchronized output (DEC 2026) | GAP → DONE | `ansi-begin-synchronized-update`/`-end-synchronized-update` (flicker-free repaints) |
| Terminal soft reset | GAP → DONE | `ansi-reset-terminal` (RIS) |
| Runtime terminal size | GAP → DONE | `terminal-size` (ioctl TIOCGWINSZ; returns NIL off a tty) |
| PTY window-size propagation | DONE (third pass) | `pty-resize` (ioctl TIOCSWINSZ) |

## B. ANSI escape building

| Capability | Status | Notes |
|---|---|---|
| Clear screen / line (with modes) | DONE | `ansi-clear-screen`, `ansi-clear-line` |
| Absolute cursor move | DONE | `ansi-move-cursor`, `ansi-cursor-column` |
| Relative cursor move | DONE | `ansi-cursor-up`/`-down`/`-forward`/`-back` |
| Save / restore cursor | DONE | `ansi-save-cursor`, `ansi-restore-cursor` |
| Scroll up/down + scroll region | DONE | `ansi-scroll-up`/`-down`/`-set-scroll-region` |
| Window title | DONE | `ansi-set-window-title` |
| Cursor shape | DONE | `ansi-set-cursor-style` |
| SGR text attributes | DONE | bold/dim/italic/underline/blink/reverse/hidden/strikethrough + generic `ansi-sgr` |
| SGR reset | DONE | `ansi-reset-style` |
| Default fg/bg (SGR 39/49) | GAP → DONE | `ansi-default-foreground`, `ansi-default-background` |
| OSC 8 hyperlinks | DONE | `ansi-hyperlink` |
| 256-color / truecolor SGR | DONE | via the style model + `style-ansi` |

## C. Input decoding

| Capability | Status | Notes |
|---|---|---|
| Printable / control / Alt-prefixed keys | DONE | `decode-input`, `decode-key-sequence` |
| Named special & function keys (CSI / SS3 / CSI-u / kitty) | DONE | key tables |
| Modifier decoding & normalization | DONE | shift/alt/control |
| Streaming / chunked decode | DONE | `make-input-decoder`, `decode-input-chunk`, `flush-input-decoder` |
| Bracketed paste (streaming) | DONE | `:paste` events / marker events |
| SGR mouse (press/release/drag/move/wheel) | DONE | `decode-mouse-sequence` + inline via `decode-input` |
| Focus in/out | DONE | `:focus-in`/`:focus-out` |
| Cursor position report | DONE | standalone `decode-cursor-position-report` |
| Human-readable key labels | DONE | `key-event->string` |
| Device attributes (DA) response decode | DONE (third pass) | `ansi-request-device-attributes` + `decode-device-attributes` |

## D. Unicode and text measurement

| Capability | Status | Notes |
|---|---|---|
| Per-character terminal column width | DONE | `char-width` (zero/one/two-width via `sb-unicode`) |
| String column width | DONE | `string-width` |
| Width-aware truncation (+ ellipsis) | DONE | `truncate-string` |
| Width-aware padding / alignment | DONE | `pad-string` |
| Word wrapping (+ hard split) | DONE | `wrap-string` |
| Grapheme-cluster segmentation | DONE (fourth pass) | `string-graphemes`, `grapheme-count`, `grapheme-width` via `sb-unicode:graphemes`, already in the SBCL image |

## E. Screen / cell model

| Capability | Status | Notes |
|---|---|---|
| Fixed grid of styled cells | DONE | `screen`, `cell`, `make-style` |
| Cell/style construction & normalization | DONE | `style-fg`/`-bg`, `make-style`, `style-merge`, `style-ansi` |
| Put / fill-rect / write-string | DONE | width-aware `screen-write-string` |
| Whole-grid fill | DONE | `screen-fill` |
| Deep copy / region blit / scroll | DONE | `screen-copy`, `screen-blit`, `screen-scroll` |
| Row / whole-screen text extraction | DONE | `screen-row-string`, `screen-to-string` |
| Multi-line / wrapped / aligned placement | DONE | `screen-write-lines`/`-wrapped`/`-aligned` |
| Blank-cell predicate | DONE | `cell-blank-p` |
| Resize preserving content | DONE | `screen-resize` |
| Region extraction | DONE (second pass) | `screen-crop` |

## F. Rendering

| Capability | Status | Notes |
|---|---|---|
| Full repaint | DONE | `render-screen` |
| Minimal diff repaint | DONE | `render-diff` (clear-line runs, dimension-aware) |
| Cursor render | DONE | `render-cursor` |
| Frame (screen + cursor) | DONE | `render-frame`, `render-frame-diff` |
| Double-buffered render loop | DONE | `renderer` (`renderer-render` emits only changes + snapshots) |
| Synchronized-update wrapping | DONE (B) | `ansi-begin/end-synchronized-update` can bracket a `renderer-render` |

## G. Color

| Capability | Status | Notes |
|---|---|---|
| 16 named colors → index | DONE | `named-color` |
| Hex parse (`#rrggbb` / `#rgb`) | DONE | `parse-hex-color` |
| xterm-256 ↔ RGB | DONE | `color-256-to-rgb`, `rgb-to-256` |
| RGB blend / gradient ramp | DONE | `blend-colors`, `color-gradient` |
| RGB → nearest 16-color | GAP → DONE | `rgb-to-ansi16` (for low-color terminals) |
| Perceived luminance | GAP → DONE | `color-luminance` (e.g. to pick readable fg over a bg) |
| HSL / HSV round-tripping | DONE (second pass) | `rgb-to-hsl`/`hsl-to-rgb`, `rgb-to-hsv`/`hsv-to-rgb` |
| Unified color parsing | DONE (second pass) | `parse-color` (hex / `rgb(...)` / name), `contrast-color` |

## H. Layout geometry

| Capability | Status | Notes |
|---|---|---|
| Rect value + accessors | DONE | `rect`, `make-rect`, `rect-x/y/width/height` |
| Inset (margins) | DONE | `rect-inset` |
| Horizontal / vertical split | DONE | `rect-split-horizontal`/`-vertical` |
| Point-in-rect | DONE | `rect-contains-p` |
| Emptiness / area | GAP → DONE | `rect-empty-p`, `rect-area` |
| Intersection / union | GAP → DONE | `rect-intersect`, `rect-union` (clipping & damage bounds) |
| Constraint-based layout split | DONE (fourth pass) | `layout-split` (ratatui-style `:length`/`:percentage`/`:ratio`/`:min`/`:fill`) |
| Full flex/grid constraint solver (Cassowary) | DEFERRED | application-framework territory; `layout-split`/`rect-inset` cover panel layout |

## I. Widgets and formatting

| Capability | Status | Notes |
|---|---|---|
| Box borders + lines (5 styles) | DONE | `screen-draw-box`, `screen-draw-horizontal-line`/`-vertical-line` |
| Box title | GAP → DONE | `screen-draw-box :title`/`:title-align` |
| Progress bar (sub-cell) | DONE | `format-progress-bar` |
| Sparkline | DONE | `format-sparkline` |
| Aligned columns (single row) | DONE | `format-columns` |
| Multi-row table (auto widths) | GAP → DONE | `format-table` |
| Spinner frames | GAP → DONE | `spinner-frame` |
| Bitmap graphics (sixel) | DONE (fifth pass) | `format-sixel` |

## J. PTY / process

| Capability | Status | Notes |
|---|---|---|
| Spawn under PTY | DONE | `make-pty` |
| Read / write / close | DONE | `pty-read`, `pty-write`, `close-pty` |
| Window-size propagation | DONE (third pass) | `pty-resize`, see A |
| Fd-centric byte-transparent I/O (multiplexer use) | DONE | `pty-fd`, `pty-pid`, `fd-read-octets`, `fd-write-octets` |

## K. Embedded logic engine

| Capability | Status | Notes |
|---|---|---|
| Unification + CPS resolution + clause DB | DONE | `nerima-lisp/cl-prolog`, a test-suite dependency (differential-testing oracle) |

---

## Second pass — competitive research (2026-07-20)

The first pass above was from domain knowledge. To make the enumeration genuinely
comprehensive rather than recalled, a second pass surveyed the *actual* published
capability surfaces of the major terminal libraries — `crossterm`/`ratatui`
(Rust), `notcurses` (C), `tcell`/`termbox2` (Go), and `rich`/`prompt_toolkit`/
`blessed` (Python) — and diffed each capability against the then-current public
API. The diff surfaced primitives that appeared across two or more of those
libraries but were missing here. All of them were then implemented:

- **Style / SGR** — extended underline styles `:double-underline`,
  `:curly-underline`, `:dotted-underline`, `:dashed-underline` (SGR 4:2..4:5),
  `:overline` (SGR 53), and a separate underline color via `style-underline-color`
  (SGR 58). *(crossterm, notcurses, termbox2, rich.)*
- **Color** — `rgb-to-hsl`/`hsl-to-rgb`, `rgb-to-hsv`/`hsv-to-rgb`, a unified
  `parse-color` (hex / `rgb(...)` / name), and `contrast-color`. *(ratatui,
  rich, termenv.)*
- **ANSI / OSC** — `ansi-set-clipboard` (OSC 52, base64), `ansi-set-palette-color`
  (OSC 4) / `ansi-reset-palette` (OSC 104), `ansi-request-foreground-color` /
  `ansi-request-background-color` (OSC 10/11) with `decode-color-report` for the
  reply, `ansi-enable-line-wrap` / `ansi-disable-line-wrap` (DECAWM), and
  `ansi-cursor-next-line` / `ansi-cursor-previous-line` (CNL/CPL). *(notcurses,
  crossterm.)*
- **Unicode / text** — East Asian Ambiguous width policy
  (`*east-asian-ambiguous-wide*`), `expand-tabs`, `chop-string` (hard column
  chop), and `strip-ansi` (sequence-aware measurement). *(notcurses,
  prompt_toolkit, rich, blessed.)*
- **Screen** — `screen-crop` (extract a rect region as a new screen). *(rich
  `set_shape`, ratatui.)*
- **Input** — horizontal wheel `:wheel-left`/`:wheel-right` in mouse decoding.
  *(crossterm ScrollLeft/Right.)*

## Third pass — closing the feasible deferrals (2026-07-20)

A review of the second-pass "Deferred" list separated items that were genuinely
out of scope from ones deferred only for expected effort. The feasible ones were
then implemented:

- **Kitty keyboard event kinds** — `key-event-kind` (:PRESS / :REPEAT / :RELEASE),
  decoded from the CSI-u (and general CSI) `MODIFIER:EVENT` sub-parameter, so
  every key event now carries its kind (default :PRESS off the kitty protocol).
- **Extended named keys** — the kitty private-use function/keypad/media codes
  were already tabled; added the legacy CSI-tilde codes for **F13–F20**.
- **Reverse ANSI parsing** — `decode-sgr` (an SGR escape → normalized style, the
  inverse of `style-ansi`) and `parse-styled-string` (a styled string → a list of
  (text . style) segments, accumulating style across sequences via `style-merge`).
- **Device Attributes** — `ansi-request-device-attributes` (DA1) and
  `decode-device-attributes` for the `ESC [ ? ... c` reply.
- **PTY window-size propagation** — `pty-resize` (ioctl TIOCSWINSZ on the PTY's
  descriptor). Implementing this also **surfaced and fixed a latent bug**:
  `terminal-size` had been calling a hand-declared `ioctl` alien routine, which on
  the arm64 variadic ABI passes the winsize pointer in a register instead of on
  the stack, so the ioctl always failed with EFAULT and the function silently
  returned NIL. Both now go through `sb-unix:unix-ioctl`, which marshals correctly;
  `terminal-size` actually reports the size now (verified by a `pty-resize` →
  `terminal-size` round-trip in the tests).

## Fourth pass — re-examining two more deferrals (2026-07-20)

Two items previously deferred turned out to be feasible after a closer look:

- **Grapheme-cluster segmentation** — it was deferred on the assumption it would
  require *shipping* Unicode grapheme-break tables. In fact `sb-unicode:graphemes`
  is already in the SBCL image, so `string-graphemes`, `grapheme-count`, and
  `grapheme-width` were added for free. (SB-UNICODE's `graphemes` errors on the
  empty string; that edge is guarded.)
- **Constraint-based layout** — a full Cassowary solver is application territory,
  but the practical `ratatui`-style constraint split is a geometry primitive:
  `layout-split` divides a rect along an axis by a list of `(:length N)`,
  `(:percentage P)`, `(:ratio A B)`, `(:min N)`, and `(:fill WEIGHT)` constraints
  (with spacing), sharing leftover space by weight via largest-remainder.

## Fifth pass — closing the remaining feasible items (2026-07-20)

- **Kitty associated text** — the CSI-u text field (field 3) is now decoded into
  `key-event-text` (the string a key inserts, for IME/international input), and
  the shifted-key subfield of field 1 is skipped to the primary key. Combined
  with `key-event-kind`, the practical kitty input surface is covered.
- **In-place editing escapes** — `ansi-insert-line`/`ansi-delete-line` (IL/DL),
  `ansi-insert-char`/`ansi-delete-char`/`ansi-erase-char` (ICH/DCH/ECH),
  `ansi-cursor-row` (VPA), and `ansi-repeat` (REP) round out the CSI editing set
  that terminal libraries use for partial-line updates.
- **Sixel graphics** — `format-sixel` encodes a raw RGB pixel buffer into a sixel
  DCS string (xterm-256 quantization, 6-row bands, run-length compression), so a
  sixel-capable terminal can render bitmaps. This closes the "graphics" gap for
  the widely supported sixel format.

Also closed the last decodable kitty field: the CSI-u first field's shifted and
base-layout key alternates now populate `key-event-shifted-key` and
`key-event-base-key` (for layout-independent keybindings), completing the kitty
input surface.

A follow-up sweep of the ANSI mode surface added the generic `ansi-set-mode` /
`ansi-reset-mode` (DECSET/DECRST/SM/RM by number) -- the base primitive the
specific `ansi-enable-*` toggles specialize, so the long tail of DEC private
modes this library does not individually wrap (1047, 47, 12, 1005, 1015, 1016,
...) is now reachable -- plus `ansi-reset-scroll-region`. (Hardware tab stops and
SCS character-set designation were considered and left out as legacy: modern TUIs
position explicitly and draw with Unicode, so wrapping them would be padding, not
capability.)

## Deferred — genuine scope boundaries (not feasibility)

What remains is deferred on principle, not effort. Each is either a design choice
or outside the "small, SBCL-only, terminal-primitives" ethos; none is a decodable
capability left on the table:

- **Wide-cell skip flag** — a design *alternative* to the spacer-cell model this
  library already uses for double-width glyphs, not a missing capability. Both
  render and diff correctly; choosing the other representation would be a rewrite
  for no user-visible gain.
- **Kitty graphics protocol** — a second bitmap-output mechanism; `format-sixel`
  already covers image output on the widely supported format. Adding kitty
  graphics would duplicate that surface for terminals that mostly also do sixel.
- **Window manipulation (XTWINOPS `CSI Ps … t`: resize, move, minimize,
  raise/lower, report position/size)** — considered (crossterm exposes a
  `SetSize`). Left out because it is *window-manager* behavior, which `ROADMAP.md`
  defers on purpose; the size *query* it overlaps with is already served by
  `terminal-size` (ioctl). Providing the in-terminal rendering escapes is in
  scope; manipulating the terminal window is not.
- **Non-SBCL portability** — would require shipping Unicode category/width/
  grapheme tables the library currently borrows from `sb-unicode`, against the
  intentionally-small ethos. Recorded as a standing ROADMAP item.

Everything marked **GAP → DONE**, and every item under the second- through
fifth-pass lists, was implemented after enumeration and is covered by tests. A
later category-by-category re-check against the competitor inventory found no
remaining in-scope, non-padding primitive gap: the trivially-derivable candidates
(`rgb-to-hex`, an `ansi-cursor-home` alias of `move 1;1`, legacy X10 mouse
decoding, hardware tab stops) were rejected as padding, and the only substantive
candidate (XTWINOPS) is the window-manipulation boundary above. The enumeration is
exhausted down to these principled boundaries.
