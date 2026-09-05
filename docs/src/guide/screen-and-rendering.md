# Screen and Rendering

`cl-tty-kit` builds terminal output around a **pure screen model**: a fixed-size
grid of styled cells you mutate freely, then hand to a renderer that turns it
into ANSI. Nothing here touches the OS — a `screen` is an ordinary Lisp value,
so it is easy to build, snapshot, diff, and test.

This page walks the whole pipeline: the `cell`/`screen` data model, the style
system, the screen mutation API, box drawing, and the render/diff functions that
emit ANSI — ending with the double-buffered `renderer` that wraps a full render
loop for you.

!!! note "Package"

    Every symbol below is exported from the `cl-tty-kit` package. The examples
    assume `(use-package :cl-tty-kit)` or a package-qualified call; see
    [Getting Started](../getting-started.md) for loading the system.

## The cell and screen data model

### Cells

A `cell` is a single grid position: a `character` plus an optional normalized
**style list**.

```lisp
(make-cell)                          ; => blank space cell, no style
(make-cell :char #\A)
(make-cell :char #\A :style (make-style :bold))
(cell-char (make-cell :char #\A))    ; => #\A
(cell-style (make-cell :char #\A))   ; => NIL
```

`copy-cell` returns an independent copy, and `cell-blank-p` reports whether a
cell is a space that renders no visible styling — the same emptiness test the
diff renderer uses to decide a cell can be *cleared* rather than repainted.

```lisp
(cell-blank-p (make-cell))                        ; => T
(cell-blank-p (make-cell :char #\A))              ; => NIL
(cell-blank-p (make-cell :style (make-style :bold))) ; => NIL
```

### Screens

A `screen` is a `width` by `height` grid stored in a flat backing vector.
Equivalent cells may share an immutable template; screen mutation APIs replace
the affected vector entries, so normal updates remain isolated. Create one
with `make-screen`:

```lisp
(let ((screen (make-screen 20 4)))
  (screen-width screen)   ; => 20
  (screen-height screen)  ; => 4
  (screen-cell screen 0 0)) ; => a blank CELL
```

`make-screen` accepts an `:initial-cell` — a `cell` template, a bare character,
or `nil` for a blank cell — and initializes every position from one shared,
immutable template:

```lisp
(make-screen 8 2 :initial-cell #\.)   ; a grid of dots
```

Invalid dimensions (negative, non-fixnum, or a cell count past
`array-total-size-limit`) signal `screen-dimensions-invalid` with the offending
width and height. Out-of-bounds coordinate access signals
`screen-index-out-of-bounds`, which carries the screen dimensions and the
rejected coordinates. See [Conditions](../reference/conditions.md) for the full contract.

## The style model

A cell's style is a plain, normalized list mixing **modifier keywords** and
**color entries**. You almost never build it by hand — `make-style` normalizes
whatever you pass:

```lisp
(make-style :bold :underline)              ; => (:BOLD :UNDERLINE)
(make-style :bold (style-fg 196))          ; => (:BOLD (:FG 196))
(make-style (style-bg 17 34 51))           ; => ((:BG 17 34 51))
```

### Modifiers

Supported modifier keywords include `:bold`, `:dim`, `:italic`, `:underline`,
`:blink`, `:reverse`, `:hidden`, `:strikethrough`, `:overline`, and the extended
underline styles `:double-underline`, `:curly-underline`, `:dotted-underline`,
and `:dashed-underline`. Duplicate modifiers are deduplicated during
normalization.

### Colors

Color entries are built with `style-fg`, `style-bg`, and `style-underline-color`.
Each accepts **either** a single palette index in `[0, 255]` **or** three RGB
bytes:

```lisp
(style-fg 196)         ; => (:FG 196)      indexed (xterm-256)
(style-fg 255 0 0)     ; => (:FG 255 0 0)  truecolor RGB
(style-bg 17)          ; => (:BG 17)
(style-underline-color 0 255 0)  ; SGR 58, colors the underline itself
```

`named-color` turns one of the sixteen standard ANSI color names into its
`0-15` index, so intent stays readable:

```lisp
(named-color :bright-green)                ; => 10
(style-fg (named-color :bright-red))       ; => (:FG 9)
```

The recognized names are `:black`, `:red`, `:green`, `:yellow`, `:blue`,
`:magenta`, `:cyan`, `:white`, their `:bright-*` variants, and `:gray`/`:grey`
as aliases for `:bright-black`.

### Merging and emitting

`style-merge` layers one style over another, with the override winning — its
foreground/background replace the base's when present, and modifier keywords
from both are unioned:

```lisp
(style-merge (make-style (style-fg 21))
             (make-style :reverse))
;; => (:REVERSE (:FG 21))
```

`style-ansi` builds the raw SGR escape string for a style, for text you render
**outside** the screen grid. Terminate the run yourself with `ansi-reset-style`
(see [ANSI Helpers](ansi-helpers.md)):

```lisp
(style-ansi :bold (style-fg 208))
;; => the CSI "1;38;5;208m" escape string

(concatenate 'string
             (style-ansi (style-fg (named-color :cyan)))
             "hello"
             (ansi-reset-style))
```

!!! tip "Normalization is your friend"

    Styles are normalized so equivalent sets compare `equal`: modifiers are
    deduplicated, and the last valid foreground/background/underline-color entry
    wins. This is what lets the diff renderer compare two cells' styles cheaply.
    Unsupported keywords and malformed color entries are silently dropped at
    render time rather than erroring.

## Mutating a screen

### Single cells

`screen-put-cell` writes a character or a `cell` at a coordinate, optionally
overriding the style:

```lisp
(let ((screen (make-screen 10 3)))
  (screen-put-cell screen 0 0 #\H)
  (screen-put-cell screen 1 0 #\i :style (make-style :bold)))
```

An explicit `:style nil` **clears** styling when replacing an existing cell —
distinct from omitting `:style`, which keeps a passed `cell`'s own style:

```lisp
(screen-put-cell screen 1 0 #\i :style nil)  ; force a plain, unstyled cell
```

When a frame updates many individual cells, wrap the writes in
`with-screen-batch`. Nested batches are supported, and a batch that makes no
changes does not advance the screen generation:

```lisp
(let ((row 0))
  (with-screen-batch (screen)
    (loop for x below (screen-width screen)
          do (screen-put-cell screen x row (matrix-glyph x)))))
```

The renderer still computes the exact changed cells, so batching changes the
mutation bookkeeping rather than the rendered output. This is the preferred
pattern for matrix effects, particle fields, charts, and other high-update-rate
views.

### Filling regions

`screen-fill-rect` applies the same character/template + `:style` semantics to a
rectangle, and `screen-fill` does it to the whole grid — useful for painting a
background:

```lisp
(screen-fill-rect screen 2 1 6 1 #\- :style (make-style :dim))
(screen-fill screen #\Space :style (make-style (style-bg 236)))
```

`screen-clear` resets every cell to one shared immutable template (default
blank), and `screen-resize` changes the dimensions in place, preserving the
overlapping top-left region and filling any newly exposed area from
`:initial-cell`. Subsequent writes replace only their target entries.

### Writing text

`screen-write-string` is the workhorse for laying out text runs. It applies a
text run as one batched screen mutation and supports `:style`, `:start`, and
`:end` for partial writes:

```lisp
(let ((screen (make-screen 20 3)))
  (screen-write-string screen 0 0 "Hi")
  (screen-write-string screen 0 1 "!")
  (screen-to-string screen))
;; => "Hi                  \n!                   \n                    "
```

Crucially, it advances the column by each character's **`char-width`**, not by
one column per character. A double-width character — a CJK ideograph or a common
emoji — occupies two columns, so `screen-write-string` also fills the column
after it with a blank **spacer cell**. This keeps the grid's column count
aligned with what a real terminal displays, and makes the "does this run fit?"
check a *display-width* check rather than a character count.

```lisp
(let ((screen (make-screen 4 1)))
  (screen-write-string screen 0 0 (string (code-char #x65E5))) ; 日, width 2
  (screen-row-string screen 0))
;; => "日   " — the ideograph, its blank spacer cell, then the two
;;    untouched blank cells that fill out the 4-column row.
```

A run that would extend past the screen edge signals
`screen-index-out-of-bounds` and leaves the screen unchanged. See
[Text Layout and Unicode Width](text-layout.md) for `char-width`, `wrap-string`,
and the measurement helpers underneath.

### Multi-line and aligned text

Three higher-level placers clip to the grid instead of signaling, so a block of
content can be dropped in without measuring first:

- `screen-write-lines` writes a list of strings on successive rows, each clipped
  to the right edge; rows off-screen are skipped.
- `screen-write-wrapped` word-wraps text to a width and writes the lines down,
  returning `(values screen count)` where `count` is how many wrapped lines
  landed on-screen.
- `screen-write-aligned` places a single line inside a `rect` with horizontal
  (`:left`/`:right`/`:center`) and vertical (`:top`/`:middle`/`:bottom`)
  alignment — the natural way to center a label inside a panel carved out with
  `rect-inset` (see [Layout and Rects](layout.md)).

```lisp
(let ((screen (make-screen 20 3)))
  (screen-write-lines screen 0 0 '("first" "second"))
  (screen-write-aligned screen (make-rect :width 20 :height 3)
                        "centered" :align :center :vertical :middle))
```

### Region operations

`screen-regions.lisp` composes the single-cell primitives into whole-grid moves:

- `screen-copy` — an independent backing vector which shares immutable cells;
  a natural previous-frame snapshot for `render-diff`.
- `screen-crop` — extract a `rect` region into a new screen (clipped to bounds).
- `screen-blit` — composite a region of one screen onto another, clipped to the
  overlap; the primitive for dropping panels and widgets onto a frame.
- `screen-scroll` — shift content vertically by a signed row count, filling
  exposed rows from `:fill`.
- `screen-row-string` / `screen-to-string` — read a row, or the whole grid, back
  as plain text (no styling) for snapshots and test assertions.

```lisp
(let ((frame (make-screen 20 6))
      (panel (make-screen 8 3 :initial-cell #\*)))
  (screen-blit frame panel :dest-x 2 :dest-y 1)
  frame)
```

## Box drawing

Three functions draw borders and lines into a screen. `screen-draw-box` outlines
a rectangle; `screen-draw-horizontal-line` and `screen-draw-vertical-line` draw
single runs. All accept a `:border` glyph set and an optional `:style`:

| `:border`  | Style                          |
|------------|--------------------------------|
| `:single`  | `┌─┐ │ └─┘` (default)          |
| `:rounded` | `╭─╮ │ ╰─╯`                    |
| `:double`  | `╔═╗ ║ ╚═╝`                    |
| `:heavy`   | `┏━┓ ┃ ┗━┛`                    |
| `:ascii`   | `+-+ | +-+` (portable)         |

`screen-draw-box` leaves the interior untouched, so a box can frame content
drawn separately. It also takes a `:title` written into the top border between
the corners, positioned by `:title-align` (`:left`/`:center`/`:right`) and styled
with `:title-style` (falling back to `:style`):

```lisp
(let ((screen (make-screen 24 5)))
  (screen-draw-box screen 0 0 24 5
                   :border :rounded
                   :title " Status "
                   :title-align :center
                   :title-style (make-style :bold))
  (screen-write-aligned screen (rect-inset (make-rect :width 24 :height 5) :all 1)
                        "ready" :align :center :vertical :middle
                        :style (make-style (style-fg (named-color :bright-green))))
  (render-screen screen))
```

A one-cell-tall or one-cell-wide box collapses to the matching line; a zero-area
box is a no-op even off-screen; a positive box that leaves the screen signals
`screen-index-out-of-bounds`.

## Rendering to ANSI

Once a screen holds the frame you want, five functions turn it into a string (or
write it to a stream). They render **cell content only** — cursor placement and
visibility are composed separately, so you control the final cursor state as part
of the frame contract.

### Full repaint

`render-screen` emits a complete frame: clear the screen, home the cursor, then
every cell row by row.

```lisp
(let ((screen (make-screen 20 3)))
  (screen-write-string screen 0 0 "Hi")
  (render-screen screen))   ; => a full-repaint ANSI string
```

`render-cursor` turns a `cursor` object into ANSI (move + show/hide), so callers
can compose final cursor placement explicitly.

### Diff rendering

`render-diff` is the incremental path: given the current screen and a
`previous` snapshot, it emits **only changed cells** when the two share the same
dimensions, and it can collapse a changed trailing blank suffix on a row into a
single `ansi-clear-line`:

```lisp
(let ((previous (make-screen 10 2))
      (current (make-screen 10 2)))
  (screen-put-cell current 0 0 #\H)
  (screen-put-cell current 1 0 #\i)
  (screen-put-cell current 0 1 #\!)
  (render-diff current previous))   ; => ANSI for just those three cells
```

`render-diff` transparently falls back to a **full repaint** when a diff would
not pay off:

- `previous` is `nil` (nothing to diff against), or
- `previous` has different dimensions (a resized terminal can't be diffed), or
- a same-size diff would emit *more* bytes than a full repaint.

This last case matters: on a frame where almost everything changed, the diff's
per-run cursor-move overhead can exceed the cost of just repainting, so the
renderer measures both and picks the shorter. You get the incremental win when
it exists and never pay a penalty when it doesn't.

### Frame helpers: content plus cursor

`render-frame` and `render-frame-diff` compose a screen render with a **final
cursor state** in one call — the common "draw the frame, then park the cursor"
path:

```lisp
(let ((previous (make-screen 12 2))
      (current (make-screen 12 2))
      (cursor (make-cursor :x 2 :y 1)))
  (screen-write-string current 0 0 "Hi")
  (screen-write-string current 0 1 "!")
  (render-frame-diff current previous cursor))
```

`render-frame-diff` also takes `:previous-cursor`; when the diff is empty *and*
the cursor is unchanged, it emits nothing at all — the ideal quiescent frame.

## A render loop, step by step

The examples build a full loop incrementally. The one-shot repaint
(`examples/simple-render.lisp`) is the starting point:

```lisp
(let ((screen (make-screen 20 3)))
  (screen-write-string screen 0 0 "Hi")
  (screen-write-string screen 0 1 "!")
  (render-screen screen))
```

`examples/screen-update.lisp` swaps in `render-diff` against a previous frame,
and `examples/frame-render.lisp` adds an explicit final cursor via
`render-frame-diff`. `examples/status-dashboard.lisp` chains three frames —
an initial `render-frame` followed by two `render-frame-diff` updates, each
against the prior frame — which is the shape of a real dashboard that repaints
once and then only touches what changed.

## The double-buffered renderer

Threading the previous screen and cursor by hand across every frame is
error-prone. `renderer` wraps it: it holds a **back buffer** to draw into and a
private snapshot of the last frame. Each `renderer-render` diffs the two and
then snapshots the back buffer as the new previous frame. When a short
unchanged span between updates costs no more than another cursor movement, the
renderer replays that span to reduce ANSI cursor-control traffic.

```lisp
(let ((renderer (make-renderer 24 4)))
  (with-output-to-string (out)
    ;; Frame 1: no snapshot yet, so this is a full paint.
    (let ((screen (renderer-screen renderer)))
      (screen-clear screen)
      (screen-draw-box screen 0 0 24 4 :border :rounded)
      (screen-write-string screen 2 1 "loading"
                           :style (make-style :bold)))
    (renderer-render renderer :stream out)
    ;; Frame 2: redraw the back buffer, then render — only the changed
    ;; cells are emitted.
    (let ((screen (renderer-screen renderer)))
      (screen-clear screen)
      (screen-draw-box screen 0 0 24 4 :border :rounded)
      (screen-write-string screen 2 1 "ready"
                           :style (make-style :bold)))
    (renderer-render renderer :stream out)))
```

The API:

- `make-renderer` *width height* `&key initial-cell` — fresh back buffer; the
  first render repaints in full.
- `renderer-screen` — the back buffer to draw the next frame into.
- `renderer-width` / `renderer-height` — its dimensions.
- `renderer-render` `&key stream cursor` — emit the diff (returning the ANSI
  string, or writing to `stream` and returning it), then snapshot. Pass
  `:cursor` to also finish in a cursor state, diffed against the previous
  frame's cursor.
- `renderer-clear` `&key cell` — reset the back buffer; the change shows on the
  next render.
- `renderer-resize` *width height* `&key initial-cell` — resize the back buffer
  and **drop the snapshot**, so the next render repaints in full (a resized
  terminal can't be diffed).

`examples/renderer-loop.lisp` is the worked version: it drives a renderer over
two frames — a full first paint of a rounded box with a centered label and a
green progress bar, then a diff-only second update when only the label and bar
change.

!!! note "Renderer resize and terminal SIGWINCH"

    When the terminal reports a new size, call `renderer-resize` before drawing
    the next frame. Dropping the snapshot is deliberate: the previous frame
    describes a differently-sized grid, so a diff against it would be
    meaningless. See [Terminal Session and Raw Mode](terminal-session.md) for
    obtaining the live size with `terminal-size`.

## See also

- [Layout and Rects](layout.md) — `rect` geometry and the `layout-split` solver
  that carve the regions you draw into.
- [Widgets](widgets.md) — progress bars, sparklines, tables, and images to fill
  those regions.
- [Animation](animation.md) — `sprite-blit`'s transparent compositing on top of
  `screen-blit`, plus the tick-loop driver and `entity` helper.
- [Text Layout and Unicode Width](text-layout.md) — `char-width`, wrapping, and
  truncation behind `screen-write-string`.
- [Color](color.md) — building the RGB and indexed colors that feed `style-fg`
  and `style-bg`.
- [ANSI Helpers](ansi-helpers.md) — `ansi-reset-style` and the escape builders
  `style-ansi` complements.
- [API Reference](../reference/api.md) — the complete exported symbol list.
