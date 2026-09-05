# Widgets

`cl-tty-kit`'s widgets are **pure string builders**. Each one produces
fixed-width text measured in terminal columns — a progress bar, a sparkline, a
spinner frame, an aligned column row, an auto-width table — with no screen and no
side effects. Build the string, then hand it to `screen-write-string` (see
[Screen and Rendering](screen-and-rendering.md)) or print it directly. Two
further widgets encode bitmap images as terminal escape sequences.

Widgets are functions returning strings and can be composed by callers.

!!! note "Package"

    All symbols are exported from `cl-tty-kit`. See
    [Getting Started](../getting-started.md) for loading the system.

## Progress bars

`format-progress-bar` renders a `ratio` (clamped to `[0, 1]`) as a bar exactly
`width` columns wide:

```lisp
(format-progress-bar 0.5 10)   ; => "█████     "
(format-progress-bar 1.0 10)   ; => "██████████"
(format-progress-bar 0.0 10)   ; => "          "
```

By default (`:fractional t`) the bar resolves to **one-eighth of a cell** using
Unicode block glyphs (`▏▎▍▌▋▊▉█`), so a partly filled final cell shows real
sub-cell progress instead of jumping a whole column at a time:

```lisp
(format-progress-bar 0.62 24)
;; => "██████████████▉         "  — note the fractional trailing block
```

Pass `:fractional nil` to round the fill to whole cells, and override the glyphs
with `:full` and `:empty`:

```lisp
(format-progress-bar 0.5 10 :fractional nil)          ; => "█████     "
(format-progress-bar 0.5 10 :full #\# :empty #\-)     ; => "#####-----"
```

The result is always exactly `width` columns, which makes bars align in a column
and fit a known slot in a panel. `width` must be a non-negative integer.

## Sparklines

`format-sparkline` renders a sequence of numbers as a one-line bar chart using
the eight block-height glyphs `▁▂▃▄▅▆▇█`:

```lisp
(format-sparkline '(1 3 2 5 4 7 6 8 5 3))
;; => "▁▃▂▅▄▇▆█▅▃"  (one glyph per value)
```

Each value maps to one of eight heights by its position in a range. The range
defaults to the minimum and maximum of the values, but you can pass `:min` and
`:max` to fix a band — values outside it are clamped, so a narrower explicit
range highlights a region of interest:

```lisp
(format-sparkline '(10 20 30 40) :min 0 :max 100)  ; a fixed 0-100 scale
```

A zero-width range (all values equal, or `:min` = `:max`) renders the lowest bar;
an empty sequence yields an empty string. `format-sparkline` accepts any Lisp
`sequence`.

## Spinners

`spinner-frame` returns one glyph of an animation, cycling by an integer index —
feed it a monotonically increasing counter to animate:

```lisp
(spinner-frame 0)               ; => "⠋"  (default :dots braille set)
(spinner-frame 1)               ; => "⠙"
(spinner-frame 0 :frames :line) ; => "|"
(spinner-frame 1 :frames :bar)  ; => "▃"
```

`:frames` names a built-in set (`:dots` braille, `:line`, or `:bar` block
heights) or is a sequence of frame characters/strings you supply directly. The
index is taken modulo the frame count, so the animation loops:

```lisp
(spinner-frame 7 :frames "abc")  ; => "b"  (7 mod 3 = 1)
```

## Aligned columns

`format-columns` pads a list of fields to a matching list of widths and joins
them into one row string:

```lisp
(format-columns '("name" "size") '(10 6))
;; => "name       size  "  ("name" + 6 pad, a separator space, then "size" + 2 pad)

(format-columns '("build" "ok") '(10 6) :aligns '(:left :right))
;; => "build          ok"  ("build" + 5 pad, a separator space, then 4 pad + "ok")
```

`:aligns` is a per-column list of `:left`, `:right`, or `:center` (defaulting to
`:left` where the list runs short). `:separator` (default a single space) sits
between columns, and `:pad` (default space) is the fill character. `fields` and
`widths` must be equal-length lists.

Padding uses `pad-string`, so a field already wider than its column is left
**intact rather than truncated**. Clip it first with `truncate-string` if you
need a hard cap (see [Text Layout and Unicode Width](text-layout.md)).

## Auto-width tables

`format-table` takes a list of rows — each row a list of field strings — and
returns a list of row strings, every column padded to the width of its widest
field so the columns line up down the table:

```lisp
(format-table '(("name" "status")
                ("build" "ok")
                ("deploy" "pending")))
;; => ("name   status "
;;     "build  ok     "
;;     "deploy pending")
```

Column widths are measured with `string-width`, so CJK and emoji fields align
correctly. Ragged rows are padded with empty trailing fields. `:aligns`,
`:separator`, and `:pad` pass through to `format-columns` per row. An empty
`rows` yields an empty list.

Feed the result straight to `screen-write-lines` to place a table on a screen:

```lisp
(let ((screen (make-screen 30 4)))
  (screen-write-lines screen 0 0
                      (format-table '(("cpu" "62%") ("mem" "30%"))))
  (render-screen screen))
```

## Worked example: a progress dashboard

`examples/progress-dashboard.lisp` combines several widgets inside a rounded,
titled box — two colored fractional progress bars and an aligned header row:

```lisp
(let ((screen (make-screen 34 7)))
  (screen-draw-box screen 0 0 34 7 :border :rounded)
  (screen-write-string screen 2 0 " Build " :style (make-style :bold))
  (screen-write-string screen 2 2 "cpu")
  (screen-write-string screen 6 2 (format-progress-bar 0.62 24)
                       :style (make-style (style-fg (named-color :bright-green))))
  (screen-write-string screen 2 3 "mem")
  (screen-write-string screen 6 3 (format-progress-bar 0.30 24)
                       :style (make-style (style-fg (named-color :bright-yellow))))
  (screen-write-string screen 2 5
                       (format-columns '("task" "status") '(10 12)
                                       :aligns '(:left :right)))
  (render-screen screen))
```

The bar strings carry no color themselves — the color comes from the `:style`
passed to `screen-write-string`, so the same widget output works in any palette.

`examples/text-panel.lisp` is a companion showing the text-layout helpers a
widget-heavy panel leans on: a `truncate-string` title clipped to the border with
a real ellipsis glyph, and `screen-write-wrapped` word-wrapping a paragraph to
the panel's interior width by display columns.

## Bitmap images

Two functions encode a raw RGB(A) pixel buffer as a terminal image escape. They
target different, largely non-overlapping terminal families, so together they
broaden coverage rather than duplicate it.

### Sixel

`format-sixel` turns a flat, row-major buffer of `width * height * 3` octets (R,
G, B per pixel) into a **sixel DCS string**. Colors are quantized to the xterm
256-color palette, and the output is bracketed by the sixel introducer `ESC P q`
and terminator `ESC \`, ready to write to a sixel-capable terminal:

```lisp
(defun gradient-pixels (width height)
  "A flat RGB buffer with a horizontal red-to-blue gradient."
  (let ((pixels (make-array (* width height 3) :element-type '(unsigned-byte 8))))
    (dotimes (y height pixels)
      (dotimes (x width)
        (let ((i (* 3 (+ (* y width) x))))
          (setf (aref pixels i)       (round (* 255 (/ (- width 1 x) (1- width))))
                (aref pixels (+ i 1)) 0
                (aref pixels (+ i 2)) (round (* 255 (/ x (1- width))))))))))

(format-sixel (gradient-pixels 12 6) 12 6)
;; => a sixel DCS string; a sixel terminal renders it as a 12x6 image,
;;    and it is inert elsewhere.
```

This is `examples/sixel-image.lisp`. A zero-area image yields an empty sixel.

### Kitty graphics protocol

`ansi-kitty-image` targets the **kitty graphics protocol** — kitty, WezTerm, and
Konsole render it, and those terminals generally do not speak sixel. It base64-
encodes the pixel buffer and splits it into APC (`ESC _ G ... ESC \`) chunks:

```lisp
(ansi-kitty-image pixels width height)              ; :format 24 (RGB) default
(ansi-kitty-image rgba-pixels width height :format 32) ; RGBA, 4 bytes per pixel
```

`:format` is `24` for packed RGB (`width * height * 3` bytes) or `32` for RGBA
(`width * height * 4`). Like sixel, the escape is inert on terminals that don't
implement the protocol.

!!! tip "Which image function?"

    Neither is universal. Detect the terminal (or let the user configure it) and
    emit `format-sixel` for sixel terminals (xterm with sixel, foot, mlterm) or
    `ansi-kitty-image` for the kitty family. Both validate their inputs and
    signal a plain `error` on a dimension/buffer-length mismatch or a pixel
    limit overflow.

## See also

- [Screen and Rendering](screen-and-rendering.md) — `screen-write-string`,
  `screen-write-lines`, and the style model that colors widget output.
- [Layout and Rects](layout.md) — carve the regions widgets fill.
- [Text Layout and Unicode Width](text-layout.md) — `pad-string`,
  `truncate-string`, and `string-width`, the measurement primitives under
  `format-columns` and `format-table`.
- [Color](color.md) — palette and RGB conversions for coloring widgets.
- [API Reference](../reference/api.md) — the complete exported symbol list.
