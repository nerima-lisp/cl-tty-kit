# Color

`cl-tty-kit` ships a small, dependency-free set of color helpers in
`src/color.lisp`. Every function is pure — it takes numbers or strings and
returns fresh values, never touching global state or the terminal. The helpers
exist to bridge two worlds:

- the way humans and design tools describe color — hex strings, `rgb()`
  notation, named colors, and the HSL/HSV wheels; and
- the way a terminal actually accepts color — the xterm **256-color palette**
  index that `style-fg` and `style-bg` take, or the bare **16-color** system
  palette on limited terminals.

Most of the API is about moving cleanly between those two worlds and picking
readable combinations along the way.

## Parsing color input

`parse-color` is the one-stop parser. It accepts a hex string, a functional
`rgb(...)` string, or a color name (a keyword or a string), and always returns
three `(values r g b)` integers in `[0, 255]`.

```lisp
(parse-color "#ff8800")     ; => 255, 136, 0
(parse-color "rgb(1, 2, 3)"); => 1, 2, 3
(parse-color "rgb(1 2 3)")  ; => 1, 2, 3   (spaces work too)
(parse-color :bright-green) ; => 0, 255, 0
(parse-color "red")         ; => 128, 0, 0
```

!!! note "Named colors resolve through the palette"
    A color name is *not* the same as its full-intensity RGB. `parse-color`
    routes names through [`named-color`](screen-and-rendering.md) and the xterm
    palette, so `"red"` is palette index 1 — the dim system red `(128 0 0)` —
    not `(255 0 0)`. If you want vivid red, pass the hex or `rgb()` form.

`parse-hex-color` is the hex-only path. It accepts the full `#rrggbb` /
`rrggbb` form and the short `#rgb` / `rgb` form, where each nibble is doubled:

```lisp
(parse-hex-color "#ff8800") ; => 255, 136, 0
(parse-hex-color "ffffff")  ; => 255, 255, 255  (leading # optional)
(parse-hex-color "#f80")    ; => 255, 136, 0    (short form, nibbles doubled)
```

Any other length, a non-hex digit, or a malformed `rgb()` body signals an
error — these are validating parsers, not lenient ones.

## The xterm 256-color palette

The 256-color palette has three regions: indices 0–15 are the system colors,
16–231 form a 6×6×6 RGB cube, and 232–255 are a 24-step grayscale ramp.
`color-256-to-rgb` expands any index to its RGB triple, and `rgb-to-256` finds
the nearest index back.

```lisp
(color-256-to-rgb 21)   ; => 0, 0, 255    (a blue corner of the cube)
(color-256-to-rgb 232)  ; => 8, 8, 8      (darkest gray ramp step)

(rgb-to-256 0 0 255)    ; => 21
(rgb-to-256 128 128 128); => 244          (near-gray prefers the gray ramp)
```

`rgb-to-256` considers *both* the cube and the grayscale ramp and keeps
whichever is nearer by squared RGB distance. That is why a mid-gray input lands
on the smoother ramp (244) rather than a muddy cube cell — the extra grays are
what make ramps and shadows look clean on a 256-color terminal. A cube color
always round-trips back to itself.

### Downsampling to 16 colors

For terminals that only speak the base palette, `rgb-to-ansi16` returns the
nearest system index in `[0, 15]`:

```lisp
(rgb-to-ansi16 255 0 0) ; => 9   (bright red)
(rgb-to-ansi16 128 0 0) ; => 1   (dim red)
```

## HSL and HSV

The hue/saturation/lightness and hue/saturation/value cylinders are the natural
space for generating harmonious colors and sweeping a hue. All four converters
use degrees `[0, 360)` for hue and percentages `[0, 100]` for the other two
channels, and the pairs are exact inverses of each other.

```lisp
(rgb-to-hsl 255 0 0)   ; => 0, 100, 50
(hsl-to-rgb 240 100 50); => 0, 0, 255

(rgb-to-hsv 0 255 0)   ; => 120, 100, 100
(hsv-to-rgb 0 100 100) ; => 255, 0, 0
```

The [HSL rainbow example](#example-hsl-hue-sweep) below uses `hsl-to-rgb` to
walk the hue circle at fixed saturation and lightness, which is the standard way
to lay out a spectrum bar.

## Luminance and contrast

`color-luminance` returns the *perceived* brightness of an RGB triple as an
integer in `[0, 255]`, using the Rec. 601 weighting
(0.299 R + 0.587 G + 0.114 B). Green contributes far more than blue, matching
how the eye works:

```lisp
(color-luminance 255 255 255) ; => 255
(color-luminance 255 0 0)     ; => 76
(color-luminance 0 255 0)     ; => 150  (green reads much brighter than red)
```

`contrast-color` builds on that: it returns black `(0 0 0)` or white
`(255 255 255)` — whichever is more readable as a foreground over the given
background. It picks black on light backgrounds and white on dark ones.

```lisp
(contrast-color 240 240 240) ; => (0 0 0)      black text on a light panel
(contrast-color 10 10 10)    ; => (255 255 255) white text on a dark panel
```

This is exactly what you want when a background color is data-driven (a status
tile, a heatmap cell) and you need a legible label on top of it without knowing
the color in advance.

## Blending and gradients

`blend-colors` interpolates between two `(r g b)` lists by a `ratio` clamped to
`[0, 1]`, rounding each channel:

```lisp
(blend-colors '(0 0 0) '(255 255 255) 1/2) ; => (128 128 128)
(blend-colors '(0 0 0) '(255 255 255) 2)   ; => (255 255 255)  (ratio clamped)
```

`color-gradient` layers on top of `blend-colors` to produce a list of `steps`
evenly spaced triples, inclusive of both endpoints:

```lisp
(color-gradient '(0 0 0) '(255 255 255) 3)
; => ((0 0 0) (128 128 128) (255 255 255))

(color-gradient '(0 0 0) '(255 255 255) 1)
; => ((0 0 0))   (a single step is just the start color)
```

`steps` must be a positive integer. Gradients feed naturally into
`style-fg`/`style-bg` via `rgb-to-256`, which is the backbone of heatmaps,
progress ramps, and status bars.

## Example: a color report panel

`examples/color-report.lisp` renders a small boxed panel with two things: a
blue-to-red gradient bar and a table of named colors with their palette index
and perceived luminance. The gradient is the core idiom — build a ramp with
`color-gradient`, map each triple through `rgb-to-256`, and paint a full block
cell per step:

```lisp
(defun %color-report-gradient (screen)
  "Paint a blue-to-red gradient bar across the panel's second interior row."
  (loop for rgb in (color-gradient '(0 0 255) '(255 0 0) 36)
        for x from 2
        do (screen-put-cell
            screen x 2 (code-char #x2588)   ; U+2588 FULL BLOCK
            :style (make-style
                    (style-fg (apply #'rgb-to-256 rgb))))))
```

The table pairs each name with `(named-color name)` and the luminance of its
palette RGB, so you can see at a glance which entries are light or dark:

```lisp
(loop for name in '(:red :green :blue :yellow :cyan :magenta)
      for index = (named-color name)
      for rgb = (multiple-value-list (color-256-to-rgb index))
      collect (list (string-downcase (symbol-name name))
                    (princ-to-string index)
                    (princ-to-string (apply #'color-luminance rgb))))
```

## Example: HSL hue sweep

`examples/hsl-rainbow.lisp` sweeps the hue circle across a one-row panel. Each
interior column maps to a hue in `[0, 360)` at full saturation and mid
lightness, and `hsl-to-rgb` turns that into an RGB triple for `rgb-to-256`:

```lisp
(loop for x from 1 below 39
      for hue = (round (* 360 (/ (- x 1) 37)))
      do (multiple-value-bind (r g b) (hsl-to-rgb hue 100 50)
           (screen-put-cell
            screen x 1 (code-char #x2588)
            :style (make-style (style-fg (rgb-to-256 r g b))))))
```

Because `hsl-to-rgb` keeps saturation and lightness fixed, the result is an even
spectrum — the readable, evenly-lit rainbow you cannot get by interpolating RGB
directly.

## See also

- [Screen and Rendering](screen-and-rendering.md) — `make-style`, `style-fg`,
  `style-bg`, and `named-color`, which consume palette indices and RGB.
- [Widgets](widgets.md) — progress bars and sparklines that pair naturally with
  gradients.
- [Text Layout and Unicode Width](text-layout.md) — measuring the styled text
  you color.
- [API Reference](api-reference.md) — the full exported symbol list.
