# Changelog

## Unreleased

- harden terminal escape, input, color, mouse, PTY, and image parsing against
  malformed or adversarial data, including bounded numeric parsing, OSC/control
  sanitization, vector element validation, and bracketed-paste preflight limits
- make screen and layout operations fail atomically for invalid bounds, display
  widths, ratios, and source slices while preserving existing successful output
- improve render diff, sixel, kitty image, and text-layout hot paths by avoiding
  redundant string work, streaming output builders, and precomputing color state
- validate public cell and terminal FD boundaries explicitly, and stream render
  command output without per-command intermediate strings
- harden the embedded Prolog engine against malformed and adversarial programs:
  bound term nesting depth, detect circular terms and variable chains, add an
  occurs check, validate clause databases, goals, bindings, and primitive
  arities, and prove negation goals by existence instead of materializing every
  binding

## 0.2.0 - 2026-07-20

- greatly expand the ANSI helper set: cursor motion (`ansi-cursor-up`/`-down`/
  `-forward`/`-back`/`-column`), `ansi-save-cursor`/`ansi-restore-cursor`,
  `ansi-scroll-up`/`ansi-scroll-down`/`ansi-set-scroll-region`,
  `ansi-set-window-title`, `ansi-set-cursor-style`,
  `ansi-enable-mouse`/`ansi-disable-mouse`, a general `ansi-sgr` builder, and the
  remaining SGR text attributes (`ansi-dim`, `ansi-italic`, `ansi-underline`,
  `ansi-blink`, `ansi-reverse`, `ansi-hidden`, `ansi-strikethrough`)
- enrich the style model: recognize the `:blink`, `:hidden`, and `:strikethrough`
  modifiers, add `style-ansi` to emit an SGR string for text rendered outside the
  screen grid, and add `named-color` mapping the sixteen ANSI color names (plus
  `:gray`/`:grey`) to palette indices for use with `style-fg`/`style-bg`
- add a display-width-aware text layout module: `truncate-string` (with optional
  ellipsis), `pad-string` (`:left`/`:right`/`:center`), and `wrap-string`
  (greedy word wrap with hard-splitting of over-long words); all measure in
  terminal columns via `char-width`, so wide CJK glyphs are never split
- add screen operations: `screen-copy` (deep snapshot), `screen-blit` (clipped
  region compositing), `screen-row-string` (row inspection), `screen-scroll`
  (vertical scroll with fill), and `screen-fill` (whole-grid fill)
- add a box-drawing module: `screen-draw-box`, `screen-draw-horizontal-line`, and
  `screen-draw-vertical-line`, with `:single`, `:rounded`, `:double`, `:heavy`,
  and `:ascii` border styles
- add SGR (1006) mouse decoding: a `mouse-event` struct with button, action,
  0-based coordinates, and modifiers; a standalone `decode-mouse-sequence`; and
  integration into the CSI decode path so `decode-input`/`decode-input-chunk`
  surface mouse events inline with key events (including across chunk boundaries)
- add `examples/boxed-panel.lisp` and `examples/mouse-decoding.lisp` showcasing
  the new box, layout, color, and mouse APIs
- add a color-conversion module: `parse-hex-color` (`#rrggbb`/`#rgb`),
  `color-256-to-rgb` and `rgb-to-256` (xterm 256-palette round-tripping, with
  near-gray inputs mapping to the smoother grayscale ramp), and `blend-colors`
- add higher-level screen text placement: `screen-write-lines` (multi-line,
  clipped), `screen-write-wrapped` (wrap-and-place, returning the on-screen line
  count), and `screen-to-string` (plain-text snapshot of the grid)
- add textual widgets: `format-progress-bar` (sub-cell-accurate Unicode block bar)
  and `format-columns` (padded, aligned columns joined by a separator)
- add focus reporting: `ansi-enable-focus-reporting`/`ansi-disable-focus-reporting`
  plus `ESC[I`/`ESC[O` decoding into :FOCUS-IN/:FOCUS-OUT special key events
- add `key-event->string` for human-readable key labels (`C-a`, `S-Up`, `Enter`,
  `<paste N bytes>`)
- add `examples/progress-dashboard.lisp` showcasing box, progress bars, columns,
  and color together
- add a `rect` layout-geometry module: `make-rect` with accessors, `rect-inset`
  (carve a bordered box's interior), `rect-split-horizontal`/`rect-split-vertical`
  (with an optional gap), and `rect-contains-p`
- add `format-sparkline` (an eight-level Unicode block sparkline), `style-merge`
  (union modifiers, override colors win), and `cell-blank-p` (the emptiness test
  RENDER-DIFF uses, exposed)
- add `ansi-request-cursor-position` and a standalone `decode-cursor-position-report`
  returning 0-based (VALUES ROW COL CONSUMED); kept out of DECODE-INPUT because a
  bare `ESC[r;cR` is ambiguous with a modified F3 key
- add a double-buffered `renderer` (`make-renderer`, `renderer-screen`,
  `renderer-width`/`-height`, `renderer-render`, `renderer-clear`,
  `renderer-resize`) that wraps the draw-then-diff loop: draw into the back
  buffer, `renderer-render` emits only the changes and snapshots the frame (the
  first render, and any render after a resize, repaints in full)
- add `screen-write-aligned` for horizontally and vertically aligned text within
  a `rect` (label centering), `ansi-hyperlink` (OSC 8), and `color-gradient`
- add `examples/renderer-loop.lisp` showing a full paint followed by a diff-only
  update
- add `docs/FEATURE-AUDIT.md`, a systematic enumeration of the terminal-toolkit
  capability space (cross-referenced against notcurses/crossterm/tcell/rich)
  marking each item DONE/GAP/DEFERRED, and close every GAP it found:
  - rect geometry: `rect-empty-p`, `rect-area`, `rect-intersect` (clipping),
    `rect-union` (damage bounds)
  - ANSI: `ansi-bell`, `ansi-reset-terminal`, `ansi-begin-synchronized-update`/
    `ansi-end-synchronized-update` (tear-free repaints), `ansi-default-foreground`/
    `ansi-default-background`
  - `screen-draw-box` gains `:title`/`:title-align`/`:title-style`
  - widgets: `format-table` (auto-width multi-row) and `spinner-frame`
  - color: `rgb-to-ansi16` (16-color downsample) and `color-luminance` (Rec. 601)
  - `terminal-size` (ioctl TIOCGWINSZ on Linux/Darwin; NIL off a tty)
  Deferred items (PTY resize, grapheme clustering, flex/grid solver, DA decode,
  sixel, non-SBCL portability) are recorded with rationale in `ROADMAP.md`.
- extend `docs/FEATURE-AUDIT.md` with a second, research-backed enumeration pass
  that diffed the public API against the actual capability surfaces of crossterm/
  ratatui, notcurses, tcell/termbox2, and rich/prompt_toolkit/blessed, and close
  every additional gap it found:
  - style: `:double-underline`/`:curly-underline`/`:dotted-underline`/
    `:dashed-underline` (SGR 4:2..4:5), `:overline` (SGR 53), and
    `style-underline-color` (SGR 58)
  - color: `rgb-to-hsl`/`hsl-to-rgb`, `rgb-to-hsv`/`hsv-to-rgb`, `parse-color`
    (hex/`rgb()`/name), and `contrast-color`
  - ANSI/OSC: `ansi-set-clipboard` (OSC 52), `ansi-set-palette-color` (OSC 4)/
    `ansi-reset-palette` (OSC 104), `ansi-request-foreground-color`/
    `ansi-request-background-color` (OSC 10/11) with `decode-color-report`,
    `ansi-enable-line-wrap`/`ansi-disable-line-wrap`, and
    `ansi-cursor-next-line`/`ansi-cursor-previous-line`
  - text: `*east-asian-ambiguous-wide*` width policy, `expand-tabs`,
    `chop-string`, and `strip-ansi`
  - screen: `screen-crop`; input: `:wheel-left`/`:wheel-right` mouse decoding
- close the feasible items previously deferred in `docs/FEATURE-AUDIT.md`:
  - `key-event-kind` (:PRESS/:REPEAT/:RELEASE) decoded from the kitty CSI-u
    `MODIFIER:EVENT` sub-parameter, plus legacy CSI-tilde F13-F20 keys
  - `decode-sgr` (SGR escape → normalized style, inverse of `style-ansi`) and
    `parse-styled-string` (styled string → (text . style) segments)
  - `ansi-request-device-attributes` (DA1) and `decode-device-attributes`
  - `pty-resize` (ioctl TIOCSWINSZ); this also fixed a latent `terminal-size`
    bug where a hand-declared variadic `ioctl` alien routine failed with EFAULT
    on the arm64 ABI (silently returning NIL) -- both now use
    `sb-unix:unix-ioctl`, so `terminal-size` actually reports the size
- re-examine two more audit deferrals and implement them:
  - grapheme clusters via the in-image `sb-unicode:graphemes` (no shipped
    tables): `string-graphemes`, `grapheme-count`, `grapheme-width` (empty-string
    edge guarded)
  - `layout-split`, a ratatui-style constraint layout dividing a rect by
    `(:length N)`/`(:percentage P)`/`(:ratio A B)`/`(:min N)`/`(:fill WEIGHT)`
    constraints with spacing, sharing leftover space by weight
- close the last feasible audit deferrals:
  - kitty associated text: `key-event-text` (decoded from the CSI-u field-3 code
    points; the shifted-key subfield of field 1 is skipped to the primary key)
  - CSI in-place editing escapes: `ansi-insert-line`/`ansi-delete-line` (IL/DL),
    `ansi-insert-char`/`ansi-delete-char`/`ansi-erase-char` (ICH/DCH/ECH),
    `ansi-cursor-row` (VPA), `ansi-repeat` (REP)
  - `format-sixel`: encode a raw RGB pixel buffer into a sixel DCS string
    (xterm-256 quantization, 6-row bands, run-length compression)
  - kitty shifted / base-layout key alternates: `key-event-shifted-key` and
    `key-event-base-key` (decoded from the CSI-u first field's sub-fields),
    completing the kitty input surface
  - generic `ansi-set-mode`/`ansi-reset-mode` (DECSET/DECRST/SM/RM by number, the
    base primitive the specific ANSI-ENABLE-* toggles specialize -- covers the
    long tail of private modes) and `ansi-reset-scroll-region`
  - `pty-alive-p`, so a read loop can tell "no data yet" from "the child exited",
    and `pty-exit-code` for the child's status -- completing the PTY lifecycle
    (`make-pty` -> `pty-alive-p` -> `pty-exit-code` -> `close-pty`)
- add `examples/color-report.lisp` demonstrating the color subsystem
  (`color-gradient`, `rgb-to-256`, `named-color`, `color-luminance`) and
  `format-table` together, which previously had no runnable example
- add `examples/layout-dashboard.lisp` demonstrating `layout-split` constraint
  layout (a header/sidebar/main/footer dashboard) with `rect-inset` and
  `screen-write-aligned`
- add `examples/text-panel.lisp` demonstrating display-width text layout:
  `screen-write-wrapped` word-wrap and `truncate-string` with an ellipsis
- add `examples/hsl-rainbow.lisp` demonstrating `hsl-to-rgb` by sweeping the hue
  circle into a colored panel
- add `examples/styled-parse.lisp` demonstrating reverse ANSI parsing:
  `parse-styled-string` recovers (text . style) segments from a styled string
- add `examples/graphemes.lisp` demonstrating grapheme-cluster segmentation:
  `string-graphemes` and `grapheme-width` on a mix of combining marks and CJK
- add `examples/sixel-image.lisp` demonstrating `format-sixel` on a small
  red-to-blue gradient; with this every major subsystem has a runnable example

## 0.1.0 - 2026-07-20

- correct the README "Compatibility" section: the library requires SBCL and no
  longer claims that its pure subsystems run on other Common Lisp
  implementations (they use `sb-unicode`/`sb-ext`); the pure/OS-facing split is
  documented as an internal architecture property, not a portability guarantee
- gate the `sb-posix` dependency on `#+sbcl` and fail fast with a clear
  "requires SBCL" error on other implementations, instead of ASDF reporting a
  confusing missing `sb-posix` system
- widen the `cursor` coordinate slots to `(integer 0)` and tighten
  `%assert-screen-dimensions` (non-negative fixnum sides whose product fits
  `array-total-size-limit`) so out-of-range coordinates/dimensions signal the
  documented `cursor-parameter-invalid` / `screen-dimensions-invalid` instead of
  a raw `type-error` or `make-array` failure
- fix the README embedded-logic-engine example, which stated an output of
  `((ISAAC JACOB JOSEPH))` without defining the `(parent jacob joseph)` clause
- stop `%preferred-diff-commands` fully rendering both the full-screen and diff command lists into throwaway strings just to compare their byte lengths; it now sums each command's part lengths directly, cutting a screen-sized render pass (or two) out of every diff frame that shares its previous frame's dimensions
- add a memoization cache for a cell's SGR escape sequence (`%cell-style-sequence`), so the same style's escape string is built once and reused across the length-comparison and real-render passes and across every cell sharing that style, instead of being rebuilt from scratch each time
- make `%cell-equal-p` compare cells' already-normalized raw style lists first and only fall back to rebuilding their SGR code lists when the raw styles actually differ, avoiding per-cell SGR recomputation for the common case (matching cells) on every diff frame
- add an ASCII/Latin fast path to `char-width`'s code-point classification (code points below U+0300, verified to contain no zero-width or wide code point) so writing plain ASCII/Latin text no longer pays a `sb-unicode:general-category` table lookup per character; verified to agree with the prior classification across every Unicode code point (0 through U+10FFFF)
- serialize raw-mode enable/disable (`*raw-mode-states*` plus the accompanying `TCGETATTR`/`TCSETATTR` calls) behind a mutex on threaded SBCL builds, closing a check-then-act race that could corrupt the depth refcount or drop a saved termios snapshot when two threads share a raw-mode fd, potentially leaving the real terminal stuck in raw mode after exit
- reset a `pty`'s `process`/`stream` slots in `close-pty` even when shutdown signals `pty-operation-failed`, since the underlying stream is already closed by that point; previously a failed close left the slots pointing at an already-closed stream and a give-up process, so a caller could reuse a dead stream or double-close on retry
- cap the digit run `%parse-csi-integer` (CSI parameter parsing) will parse at 18 digits, so an attacker-controlled multi-megabyte all-digit CSI body can no longer force an unbounded bignum parse; over-long runs fall back to ordinary character-by-character decoding like other malformed escapes
- fix `screen-write-string` ignoring `char-width`: it used to advance one column per character, so a double-width character (CJK/emoji) misaligned every following cell on the row and a run that didn't actually fit in the requested display width was silently accepted; it now advances by each character's `char-width` and fills the trailing column of a double-width character with a blank spacer cell, so the bounds check reflects real display width
- vendor `takeokunn/cl-prolog` and `takeokunn/cl-weave` as git submodules under `vendor/`, pinned to their latest upstream HEAD (both are ahead of their newest tagged release and are not distributed by Quicklisp), and add two opt-in contrib integrations on top of them: `cl-tty-kit-cl-prolog-csi-grammar`, a DCG recognizer for the ECMA-48 CSI byte-class grammar, and `cl-tty-kit-weave-tests`, a property-based fuzz suite that generates thousands of arbitrary octet sequences against `src/utf8.lisp`'s decoder and the public `decode-input` entry point and asserts they only ever fail with a documented `tty-kit-error`, never an undocumented Lisp error; see `contrib/README.md`
- restore compilation on modern SBCL by fixing the condition `:report` macro expansion
- implement the documented public API that was missing: `make-screen`, `screen-resize`, `screen-clear`, `screen-fill-rect`, `screen-write-string`, `make-cursor`, `cursor-visible-p`, `move-cursor`, `string-width`, `decode-input`, `decode-input-chunk`, and `flush-input-decoder`
- restore and extend the embedded logic engine's public API: `make-clause-db`, `define-clauses`, and the advanced relational predicates `or/*`, `true/0`, `fail/0`, `call/1`, and `findall/3`
- append clauses in O(1) amortized time so large rule sets load in linear time
- resolve East Asian / emoji wide-character width by binary search over the sorted range table instead of a linear scan, speeding up `string-width` on wide text (verified equivalent across every Unicode code point)
- keep full runtime safety when decoding untrusted terminal input (drop `(optimize (safety 0))`)
- bound the streaming input decoder's buffered tail (`make-input-decoder :max-pending`, 4 MiB default) so an unterminated escape or bracketed paste from an untrusted source cannot exhaust memory
- fix input decoding bugs: control-byte and Alt-prefixed key mapping, CSI final-byte detection, streaming UTF-8 boundary buffering, and bracketed-paste event ordering
- stop `decode-input` crashing with an uncaught TYPE-ERROR on an empty CSI-u body such as `ESC [ u`; it now falls back to ordinary decoding like other malformed escapes
- make the logic engine's `call/1`, `findall/3`, and variable goals in `and`/`or` fail gracefully on a non-compound goal term instead of crashing, and give `findall/3` fresh variables for template positions the goal leaves unbound (ISO behavior)
- fix diff rendering emitting only the last changed run and make terminal-session setup resilient to a failed setup step
- add opt-in `contrib/` integrations with the latest external libraries, isolated from the core build and CI: a `cl-prolog2` bridge that runs the embedded clause database on an external ISO Prolog, and a `clweb` (literate "weave") module; see `contrib/README.md` and `contrib/verify-contrib.lisp`
- make the test harness robust to ASDF output translations so `scripts/test.lisp` runs regardless of fasl cache configuration
- define a repository-local quality gate for release readiness and contract discipline
- document project governance and security reporting
- add a runnable streaming bracketed-paste collector example
- add tests for public package exports and error-report text
- expand key decoding coverage for control bytes and SS3 sequences
- cover bracketed paste markers and BackTab in key decoding tests and example output
- add examples for rendering, key decoding, and screen update flows
- add a styled rendering example and deduplicate example loading lists
- split examples into pure return-value functions plus explicit runners
- remove recursive ASDF reload warnings from example-backed tests
- add a regression test for style-only render-diff updates
- document and test `render-diff` fallback/full-redraw behavior and multi-row updates
- enforce README example and verification command coverage in package tests
- make `scripts/verify.lisp` run the fresh source-registry packaging smoke as part of the main gate
- lock the README Quick Start rendering example to an executable test
- enforce that runnable `examples/*.lisp` files stay registered in `scripts/example-files.lisp`
- broaden regression coverage for extended kitty/fixterms CSI `u` special keys
- normalize style modifiers so equivalent style sets compare consistently
- add indexed and truecolor cell styling for foreground and background render paths
- add public `make-style`, `style-fg`, and `style-bg` helpers for validated color style construction
- add a deterministic event-loop example that composes streaming input decode with frame diffs
- align PTY unsupported behavior across implementations
- document compatibility boundaries and unsupported-feature contracts
- keep the public API focused on terminal primitives and TTY handling
- publish ASDF homepage, issue tracker, source-control, maintainer, and version metadata
- add explicit SBCL timeouts to repository verification, examples, and coverage scripts
