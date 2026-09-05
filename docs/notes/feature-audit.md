# Feature Audit

This note maps terminal-toolkit capabilities to `cl-tty-kit`'s public API. It
is kept under `docs/notes/`, not published under `docs/src/`.

Status:

- **DONE** — implemented and tested in the public API.
- **DEFERRED** — outside the supported scope; see
  [Roadmap](../src/project/roadmap.md).

The scope is terminal primitives on SBCL, not terminal emulation or an
application framework.

---

## A. Terminal I/O and modes

| Capability | Status | Notes |
|---|---|---|
| Raw mode (enter/leave, nesting) | DONE | `enable-raw-mode`, `disable-raw-mode`, `with-raw-mode` — see [Terminal Session](../src/guide/terminal-session.md) |
| Alternate screen buffer | DONE | `ansi-enter-alternate-screen`, `ansi-exit-alternate-screen` |
| Terminal session lifecycle | DONE | `with-terminal-session` |
| Cursor show/hide | DONE | `ansi-hide-cursor`, `ansi-show-cursor` |
| Bracketed paste mode | DONE | enable/disable + streaming collection — see [Input Decoding](../src/guide/input-decoding.md) |
| Focus reporting | DONE | enable/disable + `:focus-in`/`:focus-out` decode |
| Mouse tracking modes | DONE | `ansi-enable-mouse`/`-disable-mouse` (:normal/:button/:any + SGR) — see [Mouse Input](../src/guide/mouse-input.md) |
| Kitty keyboard enhancement | DONE | `ansi-set/push/pop-keyboard-enhancements` |
| Cursor position query | DONE | `ansi-request-cursor-position` + `decode-cursor-position-report` |
| Terminal bell | DONE | `ansi-bell` |
| Synchronized output (DEC 2026) | DONE | `ansi-begin-synchronized-update`/`-end-synchronized-update` (flicker-free repaints) |
| Terminal soft reset | DONE | `ansi-reset-terminal` (RIS) |
| Runtime terminal size | DONE | `terminal-size` (ioctl TIOCGWINSZ; returns NIL off a tty) |
| PTY window-size propagation | DONE | `pty-resize` — see [PTY](../src/guide/pty.md) |

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
| Default fg/bg (SGR 39/49) | DONE | `ansi-default-foreground`, `ansi-default-background` |
| OSC 8 hyperlinks | DONE | `ansi-hyperlink` |
| 256-color / truecolor SGR | DONE | via the style model + `style-ansi` — see [ANSI Helpers](../src/guide/ansi-helpers.md) |

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
| Device attributes (DA) response decode | DONE | `ansi-request-device-attributes` + `decode-device-attributes` |

See [Input Decoding](../src/guide/input-decoding.md) and [Mouse Input](../src/guide/mouse-input.md) for
the full API.

## D. Unicode and text measurement

| Capability | Status | Notes |
|---|---|---|
| Per-character terminal column width | DONE | `char-width` (zero/one/two-width via `sb-unicode`) |
| String column width | DONE | `string-width` |
| Width-aware truncation (+ ellipsis) | DONE | `truncate-string` |
| Width-aware padding / alignment | DONE | `pad-string` |
| Word wrapping (+ hard split) | DONE | `wrap-string` |
| Grapheme-cluster segmentation | DONE | `string-graphemes`, `grapheme-count`, `grapheme-width` via `sb-unicode:graphemes` |

See [Text Layout](../src/guide/text-layout.md) for the full API.

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
| Region extraction | DONE | `screen-crop` |

## F. Rendering

| Capability | Status | Notes |
|---|---|---|
| Full repaint | DONE | `render-screen` |
| Minimal diff repaint | DONE | `render-diff` (clear-line runs, dimension-aware) |
| Cursor render | DONE | `render-cursor` |
| Frame (screen + cursor) | DONE | `render-frame`, `render-frame-diff` |
| Double-buffered render loop | DONE | `renderer` (`renderer-render` emits only changes + snapshots) |
| Synchronized-update wrapping | DONE (B) | `ansi-begin/end-synchronized-update` can bracket a `renderer-render` |

See [Screen and Rendering](../src/guide/screen-and-rendering.md) for the full API.

## G. Color

| Capability | Status | Notes |
|---|---|---|
| 16 named colors → index | DONE | `named-color` |
| Hex parse (`#rrggbb` / `#rgb`) | DONE | `parse-hex-color` |
| xterm-256 ↔ RGB | DONE | `color-256-to-rgb`, `rgb-to-256` |
| RGB blend / gradient ramp | DONE | `blend-colors`, `color-gradient` |
| RGB → nearest 16-color | DONE | `rgb-to-ansi16` (for low-color terminals) |
| Perceived luminance | DONE | `color-luminance` (e.g. to pick readable fg over a bg) |
| HSL / HSV round-tripping | DONE | `rgb-to-hsl`/`hsl-to-rgb`, `rgb-to-hsv`/`hsv-to-rgb` |
| Unified color parsing | DONE | `parse-color` (hex / `rgb(...)` / name), `contrast-color` |

See [Color](../src/guide/color.md) for the full API.

## H. Layout geometry

| Capability | Status | Notes |
|---|---|---|
| Rect value + accessors | DONE | `rect`, `make-rect`, `rect-x/y/width/height` |
| Inset (margins) | DONE | `rect-inset` |
| Horizontal / vertical split | DONE | `rect-split-horizontal`/`-vertical` |
| Point-in-rect | DONE | `rect-contains-p` |
| Emptiness / area | DONE | `rect-empty-p`, `rect-area` |
| Intersection / union | DONE | `rect-intersect`, `rect-union` (clipping & damage bounds) |
| Constraint-based layout split | DONE | `layout-split` (ratatui-style `:length`/`:percentage`/`:ratio`/`:min`/`:fill`) |
| Full flex/grid constraint solver (Cassowary) | DEFERRED | application-framework territory; `layout-split`/`rect-inset` cover panel layout |

See [Layout](../src/guide/layout.md) for the full API.

## I. Widgets and formatting

| Capability | Status | Notes |
|---|---|---|
| Box borders + lines (5 styles) | DONE | `screen-draw-box`, `screen-draw-horizontal-line`/`-vertical-line` |
| Box title | DONE | `screen-draw-box :title`/`:title-align` |
| Progress bar (sub-cell) | DONE | `format-progress-bar` |
| Sparkline | DONE | `format-sparkline` |
| Aligned columns (single row) | DONE | `format-columns` |
| Multi-row table (auto widths) | DONE | `format-table` |
| Spinner frames | DONE | `spinner-frame` |
| Bitmap graphics (sixel) | DONE | `format-sixel` |

See [Widgets](../src/guide/widgets.md) for the full API.

## J. PTY / process

| Capability | Status | Notes |
|---|---|---|
| Spawn under PTY | DONE | `make-pty` |
| Read / write / close | DONE | `pty-read`, `pty-write`, `close-pty` |
| Window-size propagation | DONE | `pty-resize` |
| Fd-centric byte-transparent I/O (multiplexer use) | DONE | `pty-fd`, `pty-pid`, `fd-read-octets`, `fd-write-octets` |

See [PTY](../src/guide/pty.md) for the full API.

## K. Embedded logic engine

| Capability | Status | Notes |
|---|---|---|
| Unification + CPS resolution + clause DB | DONE | `nerima-lisp/cl-prolog-kit`, a test-suite dependency (differential-testing oracle) |

See [Logic Engine](../src/guide/logic-engine.md) for the full API.

---

## Other implemented capabilities

The following capabilities extend the public API:

- **Style / SGR** — extended underline styles `:double-underline`,
  `:curly-underline`, `:dotted-underline`, `:dashed-underline` (SGR
  4:2..4:5), `:overline` (SGR 53), and a separate underline color via
  `style-underline-color` (SGR 58). *(crossterm, notcurses, termbox2, rich.)*
- **Color** — `rgb-to-hsl`/`hsl-to-rgb`, `rgb-to-hsv`/`hsv-to-rgb`, a unified
  `parse-color` (hex / `rgb(...)` / name), and `contrast-color`. *(ratatui,
  rich, termenv.)*
- **ANSI / OSC** — `ansi-set-clipboard` (OSC 52, base64),
  `ansi-set-palette-color` (OSC 4) / `ansi-reset-palette` (OSC 104),
  `ansi-request-foreground-color` / `ansi-request-background-color` (OSC
  10/11) with `decode-color-report` for the reply, `ansi-enable-line-wrap` /
  `ansi-disable-line-wrap` (DECAWM), and `ansi-cursor-next-line` /
  `ansi-cursor-previous-line` (CNL/CPL). *(notcurses, crossterm.)*
- **Unicode / text** — East Asian Ambiguous width policy
  (`*east-asian-ambiguous-wide*`), `expand-tabs`, `chop-string` (hard column
  chop), and `strip-ansi` (sequence-aware measurement). *(notcurses,
  prompt_toolkit, rich, blessed.)*
- **Screen** — `screen-crop` (extract a rect region as a new screen). *(rich
  `set_shape`, ratatui.)*
- **Input** — horizontal wheel `:wheel-left`/`:wheel-right` in mouse
  decoding. *(crossterm ScrollLeft/Right.)*

## Input and PTY capabilities

These APIs are implemented:

- **Kitty keyboard event kinds** — `key-event-kind` (:PRESS / :REPEAT /
  :RELEASE), decoded from the CSI-u (and general CSI) `MODIFIER:EVENT`
  sub-parameter, so every key event now carries its kind (default :PRESS off
  the kitty protocol).
- **Extended named keys** — the kitty private-use function/keypad/media codes
  were already tabled; added the legacy CSI-tilde codes for **F13–F20**.
- **Reverse ANSI parsing** — `decode-sgr` (an SGR escape → normalized style,
  the inverse of `style-ansi`) and `parse-styled-string` (a styled string →
  a list of (text . style) segments, accumulating style across sequences via
  `style-merge`).
- **Device Attributes** — `ansi-request-device-attributes` (DA1) and
  `decode-device-attributes` for the `ESC [ ? ... c` reply.
- **PTY window-size propagation** — `pty-resize` (ioctl TIOCSWINSZ on the
  PTY's descriptor). Implementing this also **surfaced and fixed a latent
  bug**: `terminal-size` had been calling a hand-declared `ioctl` alien
  routine, which on the arm64 variadic ABI passes the winsize pointer in a
  register instead of on the stack, so the ioctl always failed with EFAULT
  and the function silently returned NIL. Both now go through
  `sb-unix:unix-ioctl`, which marshals correctly; `terminal-size` actually
  reports the size now (verified by a `pty-resize` → `terminal-size`
  round-trip in the tests).

## Text and layout capabilities

These APIs are implemented:

- **Grapheme-cluster segmentation** — `sb-unicode:graphemes` is available in
  the SBCL image. `string-graphemes`, `grapheme-count`, and `grapheme-width`
  use it; the empty-string case is handled separately.
- **Constraint-based layout** — `layout-split` is a geometry primitive;
  full Cassowary solving is outside the library's scope. It divides a rect
  along an axis by a list
  of `(:length N)`, `(:percentage P)`, `(:ratio A B)`, `(:min N)`, and
  `(:fill WEIGHT)` constraints (with spacing), sharing leftover space by
  weight via largest-remainder.

## Additional input and graphics capabilities

- **Kitty associated text** — the CSI-u text field (field 3) is now decoded
  into `key-event-text` (the string a key inserts, for IME/international
  input), and the shifted-key subfield of field 1 is skipped to the primary
  key. Together with `key-event-kind`, this covers the supported kitty input
  fields.
- **In-place editing escapes** — `ansi-insert-line`/`ansi-delete-line` (IL/DL),
  `ansi-insert-char`/`ansi-delete-char`/`ansi-erase-char` (ICH/DCH/ECH),
  `ansi-cursor-row` (VPA), and `ansi-repeat` (REP) round out the CSI editing
  set that terminal libraries use for partial-line updates.
- **Sixel graphics** — `format-sixel` encodes a raw RGB pixel buffer into a
  sixel DCS string (xterm-256 quantization, 6-row bands, run-length
  compression), so a sixel-capable terminal can render bitmaps.

The CSI-u first field's shifted and base-layout key alternates populate
`key-event-shifted-key` and `key-event-base-key` for layout-independent
keybindings.

The ANSI mode surface also includes the generic
`ansi-set-mode` / `ansi-reset-mode` (DECSET/DECRST/SM/RM by number) — the
base primitive the specific `ansi-enable-*` toggles specialize, so the long
tail of DEC private modes this library does not individually wrap (1047, 47,
12, 1005, 1015, 1016, ...) is now reachable — plus `ansi-reset-scroll-region`.
(Hardware tab stops and SCS character-set designation are not included;
modern TUIs position explicitly and draw with Unicode.)

## Deferred — scope boundaries

The remaining items are outside the supported scope or are alternative
representations of capabilities already provided:

- **Wide-cell skip flag** — a design *alternative* to the spacer-cell model
  this library already uses for double-width glyphs. Both representations
  support rendering and diffing; this library uses spacer cells.
- **Kitty graphics protocol** — a second bitmap-output mechanism;
  `format-sixel` already covers image output on the widely supported format.
  Adding kitty graphics would duplicate that surface.
- **Window manipulation (XTWINOPS `CSI Ps … t`: resize, move, minimize,
  raise/lower, report position/size)** — this is *window-manager* behavior,
  outside the scope described in [Roadmap](../src/project/roadmap.md). The
  size *query* it overlaps with is already served by `terminal-size` (ioctl).
  In-terminal rendering escapes remain in scope; manipulating the terminal
  window is not.
- **Non-SBCL portability** — would require shipping Unicode
  category/width/grapheme tables the library currently borrows from
  `sb-unicode`, which limits portability beyond SBCL. Recorded as a
  standing [Roadmap](../src/project/roadmap.md) item; see also [Compatibility](../src/reference/compatibility.md).

All **DONE** entries are covered by tests. The remaining entries are the
scope boundaries listed above.
