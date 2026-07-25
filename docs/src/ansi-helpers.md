# ANSI Helpers

The `ansi-*` helpers are string builders. Each one returns the escape sequence for a
terminal operation as a plain Lisp string — it does no I/O and touches no OS state.
That single design choice is why the whole family composes and tests so easily: you
`concatenate` sequences, inspect them, snapshot them in tests, and write them to any
stream you like.

```lisp
(concatenate 'string
             (cl-tty-kit:ansi-enter-alternate-screen)
             (cl-tty-kit:ansi-hide-cursor)
             (cl-tty-kit:ansi-move-cursor 1 1))
```

!!! note "Numeric parameters are validated"

    Helpers that take a count, row, column, or mode validate it as a non-negative
    integer and signal a plain `error` otherwise, so a bad parameter fails at the
    call site rather than emitting a malformed escape.

This page groups the helpers by purpose, then covers the reverse side: parsing an
already-styled string back into text and style with `decode-sgr` and
`parse-styled-string`.

## Cursor motion and positioning

| Helper | Sequence | Effect |
| --- | --- | --- |
| `ansi-move-cursor` | `ESC [ row ; col H` | absolute move |
| `ansi-cursor-up` / `-down` | `ESC [ n A` / `B` | relative row move |
| `ansi-cursor-forward` / `-back` | `ESC [ n C` / `D` | relative column move |
| `ansi-cursor-column` | `ESC [ n G` (CHA) | absolute column |
| `ansi-cursor-row` | `ESC [ n d` (VPA) | absolute row |
| `ansi-cursor-next-line` / `-previous-line` | `ESC [ n E` / `F` | move n lines, column 1 |
| `ansi-save-cursor` / `-restore-cursor` | `ESC 7` / `ESC 8` | save / restore position + attributes |

The relative and line helpers take an optional count that defaults to `1`.

```lisp
(cl-tty-kit:ansi-move-cursor 3 10)   ; row 3, column 10
(cl-tty-kit:ansi-cursor-up 2)        ; up two rows
```

## Screen and line clearing

- `ansi-clear-screen` — `ESC [ n J`, default mode `2` (whole screen).
- `ansi-clear-line` — `ESC [ n K`, default mode `2` (whole line).

## Cursor visibility and shape

- `ansi-hide-cursor` / `ansi-show-cursor` — DEC mode 25 toggle.
- `ansi-set-cursor-style` — DECSCUSR, taking a keyword: `:default`,
  `:blinking-block`, `:steady-block`, `:blinking-underline`, `:steady-underline`,
  `:blinking-bar`, `:steady-bar`.

## Alternate screen and bracketed paste

- `ansi-enter-alternate-screen` / `ansi-exit-alternate-screen` — DEC mode 1049.
- `ansi-enable-bracketed-paste` / `ansi-disable-bracketed-paste` — DEC mode 2004.
  Once enabled, pastes arrive wrapped in markers the input decoder recognizes; see
  [Input Decoding](input-decoding.md).

## Scroll regions and scrolling

- `ansi-scroll-up` / `ansi-scroll-down` — `ESC [ n S` / `T`.
- `ansi-set-scroll-region` — DECSTBM, `ESC [ top ; bottom r` (1-based, inclusive;
  homes the cursor to the top of the region).
- `ansi-reset-scroll-region` — restore full-screen scrolling.

## In-place line and character editing

These CSI editing functions modify the current line without a full repaint:

| Helper | Sequence | Effect |
| --- | --- | --- |
| `ansi-insert-line` | `ESC [ n L` (IL) | insert blank lines, push below down |
| `ansi-delete-line` | `ESC [ n M` (DL) | delete lines, pull below up |
| `ansi-insert-char` | `ESC [ n @` (ICH) | insert blanks, shift line right |
| `ansi-delete-char` | `ESC [ n P` (DCH) | delete chars, shift line left |
| `ansi-erase-char` | `ESC [ n X` (ECH) | blank chars in place, no shift |
| `ansi-repeat` | `ESC [ n b` (REP) | repeat the preceding character n times |

## Line wrap and generic modes

- `ansi-enable-line-wrap` / `ansi-disable-line-wrap` — DECAWM (mode 7).
- `ansi-set-mode` / `ansi-reset-mode` — the general primitive. Pass an integer mode;
  by default it emits a DEC **private** mode (`ESC [ ? n h` / `l`), or with
  `:private nil` an ANSI mode (`ESC [ n h` / `l`). Use this to toggle any mode the
  library does not wrap explicitly.

```lisp
(cl-tty-kit:ansi-set-mode 2004)              ; ESC [ ? 2004 h  (private)
(cl-tty-kit:ansi-set-mode 4 :private nil)    ; ESC [ 4 h       (ANSI insert mode)
```

## Window title

- `ansi-set-window-title` — `ESC ] 0 ; title BEL`. The title payload is sanitized of
  control bytes so it cannot break out of the OSC frame.

## Mouse and focus reporting toggles

- `ansi-enable-mouse` / `ansi-disable-mouse` — mouse reporting in `:normal`,
  `:button`, or `:any` tracking mode, always with SGR coordinates. Covered in full
  on the [Mouse Input](mouse-input.md) page.
- `ansi-enable-focus-reporting` / `ansi-disable-focus-reporting` — DEC mode 1004.
  The terminal then emits `ESC [ I` on focus and `ESC [ O` on blur, which the input
  decoder surfaces as `:special :focus-in` / `:focus-out` key events.

## SGR text attributes

Each named attribute builder returns a single SGR sequence:

| Helper | Attribute |
| --- | --- |
| `ansi-bold` | bold |
| `ansi-dim` | dim / faint |
| `ansi-italic` | italic |
| `ansi-underline` | underline |
| `ansi-blink` | blink |
| `ansi-reverse` | reverse video |
| `ansi-hidden` | hidden / concealed |
| `ansi-strikethrough` | strikethrough |
| `ansi-default-foreground` / `ansi-default-background` | reset fg / bg to default |
| `ansi-reset-style` | reset all styles (`ESC [ 0 m`) |

### The general SGR builder

`ansi-sgr` is the general builder the named emitters specialize. It joins its
arguments — non-negative integers or digit/colon sub-parameter strings like
`"4:3"` — into a single `ESC [ ... m`, semicolon-separated:

```lisp
(cl-tty-kit:ansi-sgr 1 4 38 5 196)   ; bold, underline, fg = 256-color 196
;; => "<ESC>[1;4;38;5;196m"

(cl-tty-kit:ansi-sgr "4:3")          ; extended underline: curly
(cl-tty-kit:ansi-sgr)                ; bare "<ESC>[m" reset
```

This is how you reach the extended attributes that do not have a named helper:
extended underline styles (`4:1` straight, `4:2` double, `4:3` curly, `4:4` dotted,
`4:5` dashed), underline color (`58;5;N` or `58;2;R;G;B`), and overline (`53`).

## OSC helpers

OSC (Operating System Command) sequences are framed `ESC ] ... ST` and carry a
string payload, so these helpers sanitize their input before framing.

- **`ansi-hyperlink`** — wrap text in an OSC 8 hyperlink: `(ansi-hyperlink uri text)`.
  Supporting terminals render `text` as clickable; others show it unchanged.
- **`ansi-set-clipboard`** — OSC 52 clipboard write. `(ansi-set-clipboard text)` or
  with `:target` selecting the buffer (`"c"` clipboard, `"p"` primary). The text is
  UTF-8 encoded and base64-wrapped per the protocol.
- **`ansi-set-palette-color`** — OSC 4, redefine palette entry `index` to
  `red green blue` (each 0-255).
- **`ansi-reset-palette`** — OSC 104, reset one entry (with an index) or the whole
  palette (with none) to terminal defaults.
- **`ansi-request-foreground-color`** / **`ansi-request-background-color`** — OSC 10
  / 11 queries for the terminal's default colors. The reply is parsed by
  `decode-color-report` (see [below](#querying-the-terminal)).

```lisp
(cl-tty-kit:ansi-hyperlink "https://example.com" "click me")
(cl-tty-kit:ansi-set-palette-color 1 255 0 0)   ; palette slot 1 -> pure red
```

## Querying the terminal

Some helpers issue a request the terminal answers on stdin; the toolkit pairs each
with a decoder for the reply.

- **Device attributes** — `ansi-request-device-attributes` emits the DA1 query
  `ESC [ c`. The reply `ESC [ ? ... c` is parsed by `decode-device-attributes`,
  which returns `(values params consumed)` — the integer feature parameters and how
  many characters the report spanned.
- **Cursor position** — `ansi-request-cursor-position` emits the DSR query
  `ESC [ 6 n`. The reply `ESC [ row ; col R` is parsed by
  `decode-cursor-position-report`, returning `(values row col consumed)` converted to
  0-based coordinates. This reply is *not* folded into `decode-input`, because a bare
  `ESC [ r ; c R` is ambiguous with a modified F3 key — decode it explicitly right
  after issuing the request.
- **Default colors** — `decode-color-report` parses the OSC 10/11 reply
  `ESC ] 10 ; rgb:RR../GG../BB.. ST` into `(values r g b consumed)`, each channel
  scaled to 0-255. The ST terminator may be BEL or `ESC \`.

Each decoder declines cleanly (returning `nil` and `0`) when the input is not a
complete report, so you can call it against a buffer that may not have the reply yet.

## Kitty keyboard enhancement

The kitty progressive-enhancement protocol unlocks the richer key reporting
described in [Input Decoding](input-decoding.md) (press/repeat/release kinds,
associated text, shifted/base alternates):

- `ansi-set-keyboard-enhancements` — `ESC [ = flags ; mode u`. `mode` is `1` to
  replace the current flags, `2` to set bits, `3` to reset bits.
- `ansi-push-keyboard-enhancements` — `ESC [ > flags u`, pushing flags onto the
  terminal's stack for scoped enablement.
- `ansi-pop-keyboard-enhancements` — `ESC [ < n u`, popping `n` scopes (default `1`)
  to restore the previous flags.

The push/pop pair is the safe way to enable enhancements for the duration of your app
and restore the terminal's prior state on exit; the [Terminal Session](terminal-session.md)
helper wires this into its lifecycle via `:keyboard-enhancements`.

## Bell, reset, and synchronized updates

- `ansi-bell` — returns a string of `count` BEL (`^G`) characters (default `1`).
- `ansi-reset-terminal` — RIS (`ESC c`), a hard reset to initial state.
- `ansi-begin-synchronized-update` / `ansi-end-synchronized-update` — DEC mode 2026.
  Terminals that support it buffer output between the two, so a full repaint or a
  `renderer-render` appears without tearing.

```lisp
(concatenate 'string
             (cl-tty-kit:ansi-begin-synchronized-update)
             (cl-tty-kit:render-screen screen)
             (cl-tty-kit:ansi-end-synchronized-update))
```

## Reverse parsing: recovering text and style

The helpers above *write* styled output; the reverse-parsing pair *reads* it back.
This is the read counterpart to emitting styled runs with `style-ansi` and the
`ansi-*` attribute builders.

### `decode-sgr`

`decode-sgr` is the inverse of `style-ansi`: it parses one SGR escape into a
normalized style. It accepts a full `ESC [ ... m` sequence or just the
semicolon-separated parameter body, and returns `(values style reset-p)` — the style
list plus a flag that is true when a reset parameter (`0` or empty) was present.

```lisp
(cl-tty-kit:decode-sgr "1;38;5;196")
;; => (:BOLD (:FG 196)), NIL
```

It recognizes the text attributes (bold, dim, italic, the underline styles, blink,
reverse, hidden, strikethrough, overline), the basic 30-37/90-97 and 40-47/100-107
colors, and `38`/`48`/`58` with a `5;N` (indexed) or `2;R;G;B` (truecolor) argument.
`39`/`49`/`59` drop the matching color channel; unknown parameters are ignored.

### `parse-styled-string`

`parse-styled-string` walks a whole string containing SGR escapes and returns a list
of `(text . style)` segments — the text of each run paired with the style in force
over it (`nil` when unstyled). Consecutive SGR sequences accumulate via `style-merge`
until a reset; non-SGR escape sequences are dropped.

`examples/styled-parse.lisp` builds a styled log line with the attribute builders,
then reverses it:

```lisp
(let ((styled (concatenate
               'string
               (cl-tty-kit:style-ansi :bold (cl-tty-kit:style-fg 196))
               "ERROR" (cl-tty-kit:ansi-reset-style)
               " " (cl-tty-kit:style-ansi :underline)
               "main.lisp" (cl-tty-kit:ansi-reset-style)
               ":" (cl-tty-kit:style-ansi (cl-tty-kit:style-fg 33))
               "42" (cl-tty-kit:ansi-reset-style))))
  (cl-tty-kit:parse-styled-string styled))
;; => (("ERROR" :BOLD (:FG 196)) (" ") ("main.lisp" :UNDERLINE) (":") ("42" (:FG 33)))
```

This is useful for measuring, re-styling, or re-flowing text that already carries
ANSI attributes — and it pairs with `strip-ansi` (see [Text Layout and Unicode
Width](text-layout.md)) when you only need the plain text.

## See also

- [Screen and Rendering](screen-and-rendering.md) — `style-ansi` and how styled
  cells are emitted
- [Input Decoding](input-decoding.md) — bracketed paste, kitty keyboard, and focus
  events these helpers enable
- [Mouse Input](mouse-input.md) — `ansi-enable-mouse` in depth
- [Text Layout and Unicode Width](text-layout.md) — `strip-ansi` and width-aware
  measurement of styled text
- [Terminal Session and Raw Mode](terminal-session.md) — scoping these modes over an
  app lifetime
- [API Reference](api-reference.md) — the complete exported symbol list
