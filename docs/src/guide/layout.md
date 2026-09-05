# Layout and Rects

Terminal UIs are built by carving a screen into regions and drawing into each.
`cl-tty-kit` gives you a plain `rect` value type for that geometry plus a
ratatui-style **constraint solver**, `layout-split`, that tiles a rectangle into
sized sub-rectangles. None of it touches a screen — a `rect` is pure geometry
you thread through `screen-draw-box`, `screen-write-*`, and `screen-fill-rect`.

!!! note "Package"

    All symbols are exported from `cl-tty-kit`. See
    [Getting Started](../getting-started.md) for loading the system, and
    [Screen and Rendering](screen-and-rendering.md) for the drawing functions
    these rects feed.

## The rect struct

A `rect` is a 0-based `(x, y, width, height)` value. Build one with `make-rect`;
every field defaults to `0` and must be a non-negative integer.

```lisp
(make-rect :x 2 :y 1 :width 20 :height 6)
(make-rect :width 40 :height 10)   ; a root region at the origin
```

Accessors read the four fields plus two derived edges:

```lisp
(let ((r (make-rect :x 2 :y 1 :width 20 :height 6)))
  (rect-x r)       ; => 2
  (rect-y r)       ; => 1
  (rect-width r)   ; => 20
  (rect-height r)  ; => 6
  (rect-right r)   ; => 22  (rect-x + rect-width, the column past the right edge)
  (rect-bottom r)) ; => 7   (rect-y + rect-height, the row past the bottom edge)
```

`rect-right` and `rect-bottom` are **exclusive** edges — the first column/row
*outside* the rect — which is exactly what you want for half-open range loops and
clipping.

## Predicates and measures

```lisp
(rect-contains-p (make-rect :width 10 :height 4) 3 2)  ; => T
(rect-contains-p (make-rect :width 10 :height 4) 10 0) ; => NIL (right edge is exclusive)
(rect-empty-p (make-rect :width 0 :height 5))          ; => T
(rect-area (make-rect :width 10 :height 4))            ; => 40
```

`rect-contains-p` tests whether a point falls inside; `rect-empty-p` is true when
either extent is zero (the rect encloses no cells); `rect-area` returns
`width * height`.

## Insetting

`rect-inset` shrinks a rect inward by per-side margins, clamped at zero. `:all`
sets a default for every side not given its own margin:

```lisp
(rect-inset (make-rect :width 20 :height 6) :all 1)
;; => #S(RECT :X 1 :Y 1 :WIDTH 18 :HEIGHT 4)

(rect-inset (make-rect :width 20 :height 6) :left 2 :right 2)
;; => #S(RECT :X 2 :Y 0 :WIDTH 16 :HEIGHT 6)
```

The origin moves in by `:left`/`:top`, and the extents shrink by
`:left + :right` / `:top + :bottom`. An over-large inset collapses to a zero-size
rect at the inset origin rather than going negative. This is the idiomatic way to
carve the **interior** out of a bordered box — inset by 1 on every side to skip
the border cells:

```lisp
(let* ((screen (make-screen 24 6))
       (bounds (make-rect :width 24 :height 6)))
  (screen-draw-box screen 0 0 24 6 :border :single)
  (screen-write-aligned screen (rect-inset bounds :all 1)
                        "body" :align :center :vertical :middle))
```

## Simple splits

`rect-split-horizontal` and `rect-split-vertical` divide a rect at a fixed offset,
returning two values. An optional `:gap` leaves cells between the parts.

```lisp
(rect-split-horizontal (make-rect :width 40 :height 8) 20)
;; => (values LEFT[x 0 w 20]  RIGHT[x 20 w 20])

(rect-split-vertical (make-rect :width 40 :height 8) 3)
;; => (values TOP[y 0 h 3]  BOTTOM[y 3 h 5])

(rect-split-horizontal (make-rect :width 40 :height 8) 20 :gap 1)
;; => LEFT gets 20 columns, RIGHT starts at x 21 with 19 columns
```

The split point and gap are clamped so both parts always stay inside the rect
(each part may end up zero-sized). The unaffected axis is copied through
unchanged.

### Worked example: two bordered panels

`examples/layout-panels.lisp` splits a 40x8 frame down the middle, boxes each
half, insets the interiors, and drops a sparkline into the left and a columns row
into the right:

```lisp
(let* ((screen (make-screen 40 8))
       (root (make-rect :width 40 :height 8)))
  (multiple-value-bind (left right)
      (rect-split-horizontal root 20)
    (flet ((box (r)
             (screen-draw-box screen (rect-x r) (rect-y r)
                              (rect-width r) (rect-height r)
                              :border :single)))
      (box left)
      (box right)
      (let ((inner-left (rect-inset left :all 1))
            (inner-right (rect-inset right :all 1)))
        (screen-write-string screen (rect-x inner-left) (rect-y inner-left)
                             "load" :style (make-style :bold))
        (screen-write-string screen
                             (rect-x inner-left) (+ 1 (rect-y inner-left))
                             (format-sparkline '(1 3 2 5 4 7 6 8 5 3))
                             :style (make-style
                                     (style-fg (named-color :bright-cyan))))
        (screen-write-string screen (rect-x inner-right) (rect-y inner-right)
                             "tasks" :style (make-style :bold))
        (screen-write-string screen
                             (rect-x inner-right) (+ 1 (rect-y inner-right))
                             (format-columns '("build" "ok") '(10 6)
                                             :aligns '(:left :right))))))
  (render-screen screen))
```

The `box` local function shows the standard bridge from geometry to drawing:
unpack a rect's four fields straight into `screen-draw-box`. The
[Widgets](widgets.md) page covers `format-sparkline` and `format-columns`.

## Set operations

`rect-intersect` returns the overlap of two rects — the **clipping primitive**.
Intersect a draw region with the screen bounds before writing to keep it in
range:

```lisp
(rect-intersect (make-rect :width 10 :height 10)
                (make-rect :x 5 :y 5 :width 10 :height 10))
;; => #S(RECT :X 5 :Y 5 :WIDTH 5 :HEIGHT 5)
```

Non-overlapping rects yield an empty rect (`rect-empty-p` true).

`rect-union` returns the smallest rect containing both — a bounding box. An empty
operand is ignored, so folding `rect-union` over a set of damaged regions
accumulates their bounding box:

```lisp
(rect-union (make-rect :x 0 :y 0 :width 4 :height 4)
            (make-rect :x 6 :y 2 :width 4 :height 4))
;; => #S(RECT :X 0 :Y 0 :WIDTH 10 :HEIGHT 6)
```

## Constraint-based layout: `layout-split`

`rect-split-*` handle a single cut. For laying out a whole panel — a fixed header
and footer with a flexible body between them, say — use `layout-split`, which
tiles a rect into **one sub-rect per constraint** along an axis:

```lisp
(layout-split rect direction constraints &key spacing)
```

- `direction` is `:horizontal` (split into columns) or `:vertical` (into rows).
- `constraints` is a list; each entry sizes the matching sub-rect.
- `:spacing` places that many cells between segments.

It returns the sub-rects as a list, in order, tiled exactly (no gaps, no
overflow) — the constraint primitive TUIs build panels from.

### Constraint kinds

| Constraint         | Size taken                                                   |
|--------------------|--------------------------------------------------------------|
| `(:length n)`      | Exactly `n` cells (fixed).                                    |
| `(:percentage p)`  | `floor(p * available / 100)` cells (fixed).                   |
| `(:ratio num den)` | `floor(num * available / den)` cells (fixed).                |
| `(:min n)`         | At least `n`; also grows to absorb leftover (weight 1).      |
| `(:fill weight)`   | No fixed size; shares leftover in proportion to `weight`.    |

Fixed constraints (`:length`, `:percentage`, `:ratio`) claim their size from the
axis extent first. Whatever remains is distributed among the flexible ones —
`:fill` by weight and `:min` (weight 1, never dropping below its floor) — using
the **largest-remainder method**, so the integer sizes still sum exactly to the
available space with no rounding drift.

```lisp
;; A fixed 3-row header and footer with a filling body between them.
(layout-split (make-rect :width 40 :height 10) :vertical
              '((:length 3) (:fill 1) (:length 3)))
;; => (HEADER[y 0 h 3]  BODY[y 3 h 4]  FOOTER[y 7 h 3])

;; Two fill regions splitting the leftover 2:1.
(layout-split (make-rect :width 30 :height 4) :horizontal
              '((:fill 2) (:fill 1)))
;; => (LEFT[x 0 w 20]  RIGHT[x 20 w 10])
```

`:spacing` reserves gaps between segments before solving, so the sub-rects never
overlap the spacing:

```lisp
(layout-split (make-rect :width 12 :height 1) :horizontal
              '((:length 4) (:fill 1)) :spacing 1)
;; => (A[x 0 w 4]  B[x 5 w 7])  — a one-cell gap sits at column 4
```

An empty `constraints` list yields an empty result.

### Worked example: a header / sidebar / main / footer dashboard

`examples/layout-dashboard.lisp` nests two `layout-split` calls — first rows, then
columns within the body — and draws a titled panel into each region:

```lisp
(defun dashboard-panel (screen rect title)
  "Draw a titled single-border box over RECT and return its inset interior."
  (screen-draw-box screen (rect-x rect) (rect-y rect)
                   (rect-width rect) (rect-height rect)
                   :border :single :title title)
  (rect-inset rect :all 1))

(let* ((screen (make-screen 40 10))
       (root (make-rect :width 40 :height 10)))
  ;; Rows: fixed 3-tall header and footer, the body fills the middle.
  (destructuring-bind (header body footer)
      (layout-split root :vertical '((:length 3) (:fill 1) (:length 3)))
    ;; Columns: a fixed 12-wide sidebar and a filling main pane, one cell apart.
    (destructuring-bind (sidebar main)
        (layout-split body :horizontal '((:length 12) (:fill 1)) :spacing 1)
      (screen-write-aligned screen (dashboard-panel screen header " header ")
                            "cl-tty-kit" :align :center)
      (screen-write-aligned screen (dashboard-panel screen sidebar " nav ")
                            "menu" :align :center)
      (screen-write-aligned screen (dashboard-panel screen main " main ")
                            "content" :align :center :vertical :middle)
      (screen-write-aligned screen (dashboard-panel screen footer " foot ")
                            "status" :align :center)))
  (render-screen screen))
```

This is the standard layout shape: split the root into rows, split a body row
into columns, draw a bordered panel per region, and place each region's content
inside the panel's inset interior. Swapping `(:length 3)` for `(:percentage 20)`
or `(:min 5)` reflows the whole dashboard without touching any drawing code.

!!! tip "Layout is resolution-independent"

    Because constraints resolve against whatever extent you pass, the same
    `layout-split` call adapts to a resized terminal. Recompute the root rect
    from the live [`terminal-size`](terminal-session.md) each frame and re-solve;
    the fixed panels stay fixed and the `:fill` regions absorb the difference.

## See also

- [Screen and Rendering](screen-and-rendering.md) — the drawing functions
  (`screen-draw-box`, `screen-write-aligned`, `screen-fill-rect`) that consume
  these rects.
- [Widgets](widgets.md) — sparklines, tables, and progress bars to fill the
  regions you lay out.
- [Text Layout and Unicode Width](text-layout.md) — the display-width model
  behind alignment inside a rect.
- [API Reference](../reference/api.md) — the complete exported symbol list.
