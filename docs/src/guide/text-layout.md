# Text Layout and Unicode Width

Terminal layout is measured in **columns**, not characters. This one idea is the
key that makes the whole layout API make sense, so it is worth stating plainly
before the function reference.

## Why a cell is a column, not a character

A terminal is a fixed grid of cells. Each cell is one column wide, and the
cursor advances by cells as text is written. The trap is assuming one character
equals one cell. It does not:

- A **control character** or a **zero-width combining mark** (like a combining
  acute accent) advances the cursor by **0** columns — it is drawn into the
  previous cell, not a new one.
- A **wide** character — a CJK ideograph, a fullwidth form, or a common emoji —
  occupies **2** columns. The terminal reserves the cell after it as a spacer.
- Everything else is **1** column.

If you measure with `(length string)` you will misalign every table, box, and
truncation the moment CJK text or an emoji appears: the string looks the right
length in characters but overflows or underflows the grid. Every function on
this page measures with `char-width` / `string-width` instead, so text lands
where a real terminal draws it — and a wide glyph is never split across a column
boundary.

## char-width and string-width

`char-width` is the primitive. It accepts a character or a raw Unicode code
point and returns 0, 1, or 2.

```lisp
(char-width #\A)                ; => 1
(char-width (code-char #x65E5)) ; => 2   (日, a CJK ideograph)
(char-width (code-char #x0301)) ; => 0   (a combining acute accent)
(char-width (code-char 7))      ; => 0   (a control character)
```

`string-width` sums `char-width` across a string (with optional `:start` /
`:end` bounds), giving the true rendered column count:

```lisp
(string-width "ab")             ; => 2
(string-width "café")           ; => 4
```

These two functions are the foundation the screen writer, the box drawer, and
every layout helper below rely on.

### East Asian ambiguous width

Some code points — U+00A7 SECTION SIGN, many box-drawing glyphs, parts of Greek
and Cyrillic — are *ambiguous*: they render one column wide on a Western
terminal but two columns wide in a CJK locale. The special variable
`*east-asian-ambiguous-wide*` selects the policy:

```lisp
(char-width (code-char #x00A7))                       ; => 1  (default)

(let ((*east-asian-ambiguous-wide* t))
  (char-width (code-char #x00A7)))                    ; => 2
```

The default `nil` treats ambiguous characters as one column, which is correct
for most terminals and keeps the ASCII fast path cheap — the ambiguous check
only runs when the variable is bound to `t`. Set it when you know your target is
a CJK-locale terminal that renders ambiguous glyphs full-width.

## Grapheme clusters

A code point is not always a whole "character" as a reader perceives it. `é` may
be one code point or a base `e` plus a combining accent; a flag or a
skin-toned emoji is a *sequence* of code points joined into a single visible
glyph. The unit a reader sees is the **grapheme cluster**, and it is the right
unit for cursor movement and grapheme-aware truncation.

- `string-graphemes` splits a string into cluster strings using SB-UNICODE's
  Unicode grapheme-break rules (no data tables are shipped — they are already in
  the SBCL image).
- `grapheme-count` is the number of clusters.
- `grapheme-width` is the display width of one cluster — the width of its widest
  code point, so a base plus combining marks is the base's width, and a wide
  emoji cluster is two columns. It honors `*east-asian-ambiguous-wide*` through
  `char-width`.

```lisp
(string-graphemes "é")  ; => ("é")   one cluster, two code points
(grapheme-count "é")    ; => 1
(grapheme-width "é")    ; => 1
```

An empty string yields an empty list rather than signaling.

## Width-aware truncation, padding, and wrapping

These three functions are the workhorses. Each measures in columns, so they stay
correct across mixed ASCII, CJK, and emoji text.

### truncate-string

Clip a string so its column width does not exceed `width`. A string that already
fits is returned unchanged; otherwise the longest prefix that leaves room for the
`:ellipsis` (also measured in columns) is kept and the ellipsis appended.

```lisp
(truncate-string "hello" 10)                    ; => "hello"    (fits)
(truncate-string "hello" 3)                      ; => "hel"
(truncate-string "hello world" 5 :ellipsis "...")  ; => "he..."
```

A wide glyph straddling the limit is dropped whole, never half-included. When
the ellipsis alone would not fit, it is omitted and the plain prefix is
returned. A negative `width` is treated as zero.

### pad-string

Pad a string to *exactly* `width` columns. `:align` is `:left` (pad on the
right), `:right` (pad on the left), or `:center` (split the padding, odd column
on the right). `:pad` must be a single-column character.

```lisp
(pad-string "hi" 5)                       ; => "hi   "
(pad-string "hi" 5 :align :right)         ; => "   hi"
(pad-string "hi" 5 :align :center)        ; => " hi  "
(pad-string "hi" 6 :align :center :pad #\.) ; => "..hi.."
```

`pad-string` never truncates — a string already at least `width` columns wide is
returned unchanged. Because it measures in columns, padding a two-column CJK
character to width 4 adds two spaces, not three.

### wrap-string

Wrap a string into a list of lines each at most `width` columns. Words — runs
between spaces — are kept whole and greedily packed; a single word wider than
`width` is hard-split at a column boundary.

```lisp
(wrap-string "the quick brown fox" 9)
; => ("the quick" "brown fox")

(wrap-string "a   b" 5)          ; => ("a b")   runs of spaces collapse
(wrap-string "abcdefghijk" 5)    ; => ("abcde" "fghij" "k")
```

Embedded newlines are honored as forced breaks, so a blank line in the input
yields an empty string in the output. `width` must be positive.

## expand-tabs, chop-string, and strip-ansi

`expand-tabs` replaces each tab with spaces up to the next `:tab-width` stop
(default 8). The column is tracked by display width and reset by newlines, so the
stops line up the way a terminal renders them:

```lisp
(expand-tabs (format nil "a~Cbc~Cd" #\Tab #\Tab) :tab-width 4)
; => "a   bc  d"
```

`chop-string` is a *hard* chop into pieces each at most `width` columns, with no
word breaking — unlike `wrap-string`, it does not try to keep words whole. An
empty string yields an empty list, and a glyph wider than `width` becomes a lone
over-width piece.

```lisp
(chop-string "abcdefg" 3)   ; => ("abc" "def" "g")
(chop-string "abcdefg" 100) ; => ("abcdefg")
(chop-string "" 3)          ; => ()
```

`strip-ansi` removes ANSI escape sequences — CSI (`ESC [ ... final`), OSC
(`ESC ] ... BEL/ST`), and simple two-byte `ESC X` forms — leaving the printable
text. This is how you measure or store styled text: strip first, then
`string-width` for the visible column count.

```lisp
(strip-ansi (concatenate 'string (ansi-bold) "hi" (ansi-reset-style)))
; => "hi"

(string-width (strip-ansi (ansi-hyperlink "http://x" "txt")))
; => 3
```

## Example: grapheme clusters and width

`examples/graphemes.lisp` builds a mixed string — a base plus combining accent,
two CJK ideographs, and plain ASCII — then reports each cluster's code-point
count and display width. It makes the code-point/column distinction concrete: a
base plus a combining mark is *one* cluster of *two* code points spanning *one*
column, while a CJK ideograph is *one* code point spanning *two* columns.

```lisp
(let* ((text (concatenate 'string
                          "e" (string (code-char #x0301))  ; e + acute = é
                          " " (string (code-char #x4E00))  ; CJK 一
                          (string (code-char #x4E8C))      ; CJK 二
                          " ab"))
       (clusters (string-graphemes text)))
  (format t "~D clusters, ~D display columns:~%"
          (grapheme-count text) (string-width text))
  (dolist (cluster clusters)
    (format t "  cluster ~S : ~D code point(s), width ~D~%"
            cluster (length cluster) (grapheme-width cluster))))
```

## See also

- [Screen and Rendering](screen-and-rendering.md) — `screen-write-string`
  advances by `char-width`, so wide glyphs claim their spacer cell on the grid.
- [Widgets](widgets.md) — aligned columns and tables built on width-aware
  padding.
- [Color](color.md) — coloring the text you have laid out.
- [API Reference](../reference/api.md) — the full exported symbol list.
