# API Reference

A fast, scannable map of the public `cl-tty-kit` package, grouped by subsystem.
Every symbol below is exported from `src/package.lisp`. This page is for lookup
and navigation; each group links to the guide page that carries the depth.

!!! tip "Scope"
    The core toolkit is a single package, `cl-tty-kit`. The test suite's
    embedded logic engine is [`nerima-lisp/cl-prolog`](https://github.com/nerima-lisp/cl-prolog)
    itself, used directly under its own `cl-prolog` package — see
    [Logic Engine (Prolog)](logic-engine.md).

## Conditions

Error hierarchy rooted at `tty-kit-error`. See [Conditions](conditions.md) for
slots and signaling sites.

Accessors are written out in full rather than abbreviated to a `-suffix`,
because the full name is what you type and what you search for.

| Condition | Reader accessors |
| --- | --- |
| `tty-kit-error` | — (the root type) |
| `unsupported-feature` | `unsupported-feature-feature` |
| `invalid-utf8-sequence` | `invalid-utf8-sequence-position`, `invalid-utf8-sequence-octet`, `invalid-utf8-sequence-reason` |
| `raw-mode-operation-failed` | `raw-mode-operation-failed-operation`, `raw-mode-operation-failed-fd`, `raw-mode-operation-failed-reason` |
| `pty-operation-failed` | `pty-operation-failed-operation`, `pty-operation-failed-pty`, `pty-operation-failed-reason` |
| `screen-index-out-of-bounds` | `screen-index-out-of-bounds-screen`, `screen-index-out-of-bounds-x`, `screen-index-out-of-bounds-y`, `screen-index-out-of-bounds-width`, `screen-index-out-of-bounds-height` |
| `screen-dimensions-invalid` | `screen-dimensions-invalid-width`, `screen-dimensions-invalid-height` |
| `cursor-parameter-invalid` | `cursor-parameter-invalid-parameter`, `cursor-parameter-invalid-value`, `cursor-parameter-invalid-expected` |
| `unsupported-code-point` | `unsupported-code-point-code-point` |

## Raw mode

SBCL-specific terminal mode control. See
[Terminal Session and Raw Mode](terminal-session.md).

`enable-raw-mode`, `disable-raw-mode`, `with-raw-mode`.

## Terminal session

Lifecycle helper and runtime size query. See
[Terminal Session and Raw Mode](terminal-session.md).

`with-terminal-session`, `terminal-size`.

## ANSI helpers

String builders for escape sequences — cursor motion, screen/mode control, OSC,
and SGR text attributes. All return strings. See [ANSI Helpers](ansi-helpers.md).

| Category | Symbols |
| --- | --- |
| Screen / cursor visibility | `ansi-move-cursor`, `ansi-clear-screen`, `ansi-clear-line`, `ansi-hide-cursor`, `ansi-show-cursor`, `ansi-enter-alternate-screen`, `ansi-exit-alternate-screen` |
| Cursor motion | `ansi-cursor-up`, `ansi-cursor-down`, `ansi-cursor-forward`, `ansi-cursor-back`, `ansi-cursor-column`, `ansi-cursor-row`, `ansi-cursor-next-line`, `ansi-cursor-previous-line`, `ansi-save-cursor`, `ansi-restore-cursor` |
| In-place editing | `ansi-insert-line`, `ansi-delete-line`, `ansi-insert-char`, `ansi-delete-char`, `ansi-erase-char`, `ansi-repeat` |
| Scrolling / modes | `ansi-scroll-up`, `ansi-scroll-down`, `ansi-set-scroll-region`, `ansi-reset-scroll-region`, `ansi-set-mode`, `ansi-reset-mode`, `ansi-enable-line-wrap`, `ansi-disable-line-wrap` |
| Input modes | `ansi-enable-bracketed-paste`, `ansi-disable-bracketed-paste`, `ansi-enable-focus-reporting`, `ansi-disable-focus-reporting`, `ansi-set-keyboard-enhancements`, `ansi-push-keyboard-enhancements`, `ansi-pop-keyboard-enhancements`, `ansi-enable-mouse`, `ansi-disable-mouse` |
| Requests / reports | `ansi-request-cursor-position`, `ansi-request-device-attributes`, `ansi-request-foreground-color`, `ansi-request-background-color` |
| OSC | `ansi-set-window-title`, `ansi-hyperlink`, `ansi-set-clipboard`, `ansi-set-palette-color`, `ansi-reset-palette`, `ansi-set-cursor-style` |
| Session / misc | `ansi-bell`, `ansi-reset-terminal`, `ansi-begin-synchronized-update`, `ansi-end-synchronized-update` |
| SGR attributes | `ansi-default-foreground`, `ansi-default-background`, `ansi-bold`, `ansi-dim`, `ansi-italic`, `ansi-underline`, `ansi-blink`, `ansi-reverse`, `ansi-hidden`, `ansi-strikethrough`, `ansi-reset-style`, `ansi-sgr` |

## Input decoding

Terminal input to `key-event` objects, plus reverse SGR/report parsers. See
[Input Decoding](input-decoding.md).

| Category | Symbols |
| --- | --- |
| Key events | `key-event`, `make-key-event`, `key-event-type`, `key-event-code`, `key-event-modifiers`, `key-event-kind`, `key-event-text`, `key-event-shifted-key`, `key-event-base-key`, `key-event->string` |
| Decoders | `input-decoder`, `make-input-decoder`, `decode-input`, `decode-input-chunk`, `decode-key-sequence`, `flush-input-decoder` |
| Report / SGR parsing | `decode-cursor-position-report`, `decode-color-report`, `decode-device-attributes`, `decode-sgr`, `parse-styled-string` |

## Mouse input

SGR mouse-report decoding. See [Mouse Input](mouse-input.md).

`mouse-event`, `make-mouse-event`, `mouse-event-button`, `mouse-event-action`,
`mouse-event-x`, `mouse-event-y`, `mouse-event-modifiers`,
`decode-mouse-sequence`.

## Character width

Unicode terminal column width and grapheme segmentation. See
[Text Layout and Unicode Width](text-layout.md).

`char-width`, `string-width`, `string-graphemes`, `grapheme-count`,
`grapheme-width`.

## Text layout

Display-width-aware truncation, padding, wrapping, and ANSI stripping. See
[Text Layout and Unicode Width](text-layout.md).

`truncate-string`, `pad-string`, `wrap-string`, `expand-tabs`, `chop-string`,
`strip-ansi`, `*east-asian-ambiguous-wide*`.

## Color utilities

Parsing, conversions, and blending across hex/RGB/xterm-256/HSL/HSV. See
[Color](color.md).

`parse-hex-color`, `parse-color`, `color-256-to-rgb`, `rgb-to-256`,
`rgb-to-ansi16`, `color-luminance`, `contrast-color`, `rgb-to-hsl`,
`hsl-to-rgb`, `rgb-to-hsv`, `hsv-to-rgb`, `blend-colors`, `color-gradient`.

## Formatting widgets

Textual widgets rendered to strings. See [Widgets](widgets.md).

`format-progress-bar`, `format-columns`, `format-table`, `format-sparkline`,
`spinner-frame`, `format-sixel`, `ansi-kitty-image`.

## Rectangles and layout

Layout geometry and the constraint-based splitter. See
[Layout and Rects](layout.md).

| Category | Symbols |
| --- | --- |
| Struct / accessors | `rect`, `make-rect`, `rect-x`, `rect-y`, `rect-width`, `rect-height`, `rect-right`, `rect-bottom` |
| Operations | `rect-inset`, `rect-split-horizontal`, `rect-split-vertical`, `rect-contains-p`, `rect-empty-p`, `rect-area`, `rect-intersect`, `rect-union`, `layout-split` |

## Screen and cells

The pure screen/cell model, style construction, and text placement. See
[Screen and Rendering](screen-and-rendering.md).

| Category | Symbols |
| --- | --- |
| Cells / styles | `cell`, `make-cell`, `cell-char`, `cell-style`, `make-style`, `style-fg`, `style-bg`, `style-underline-color`, `style-ansi`, `style-merge`, `named-color`, `copy-cell`, `cell-blank-p` |
| Screen struct | `screen`, `make-screen`, `screen-width`, `screen-height`, `screen-cell`, `screen-resize`, `screen-clear` |
| Writing / filling | `screen-put-cell`, `screen-fill-rect`, `screen-fill`, `screen-write-string`, `screen-write-lines`, `screen-write-wrapped`, `screen-write-aligned` |
| Region ops | `screen-copy`, `screen-blit`, `screen-crop`, `screen-scroll` |
| Inspection | `screen-row-string`, `screen-to-string` |

## Box drawing

Border and line drawing onto a screen. See
[Screen and Rendering](screen-and-rendering.md).

`screen-draw-box`, `screen-draw-horizontal-line`, `screen-draw-vertical-line`.

## Cursor and rendering

Cursor state plus screen/diff/frame ANSI emitters. See
[Screen and Rendering](screen-and-rendering.md).

| Category | Symbols |
| --- | --- |
| Cursor | `cursor`, `make-cursor`, `cursor-x`, `cursor-y`, `cursor-visible-p`, `move-cursor` |
| Rendering | `render-screen`, `render-cursor`, `render-diff`, `render-frame`, `render-frame-diff` |

!!! note "Rendering contract"
    `render-screen` and `render-diff` render cell content only. Use
    `render-cursor`, `render-frame`, or `render-frame-diff` when final cursor
    position and visibility are part of the frame.

## Double-buffered renderer

Wraps the diff-render loop with an internal previous-frame buffer. See
[Screen and Rendering](screen-and-rendering.md).

`renderer`, `make-renderer`, `renderer-screen`, `renderer-width`,
`renderer-height`, `renderer-render`, `renderer-clear`, `renderer-resize`.

## PTY

Minimal SBCL PTY abstraction, with a byte-transparent fd-centric layer
alongside the stream API. See [PTY](pty.md).

| Category | Symbols |
| --- | --- |
| Struct / stream | `pty`, `make-pty`, `pty-process`, `pty-stream`, `pty-read`, `pty-write`, `pty-resize`, `pty-alive-p`, `pty-exit-code`, `close-pty` |
| fd-centric layer | `pty-fd`, `pty-pid`, `fd-read-octets`, `fd-write-octets` |
