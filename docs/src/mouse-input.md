# Mouse Input

`cl-tty-kit` decodes terminal mouse reports into structured `mouse-event` objects.
Like key decoding, this is pure logic with no OS calls, so it is fully deterministic
and testable.

The toolkit decodes the **SGR (1006) mouse protocol** exclusively. That extended
encoding is unambiguous at any terminal size, whereas the legacy X10 encoding caps
coordinates at 223 columns/rows — so SGR is the only encoding worth targeting.

## The `mouse-event` struct

A decoded mouse report is a `mouse-event` with these accessors:

| Accessor | Meaning |
| --- | --- |
| `mouse-event-button` | which button (see below), or `:none` |
| `mouse-event-action` | `:press`, `:release`, `:drag`, `:move`, or `:scroll` |
| `mouse-event-x` | 0-based column |
| `mouse-event-y` | 0-based row |
| `mouse-event-modifiers` | normalized `:control` / `:alt` / `:shift` list |

Buttons: `:left`, `:middle`, `:right`, `:wheel-up`, `:wheel-down`, `:wheel-left`,
`:wheel-right`, or `:none`.

!!! note "Coordinates are 0-based"

    The terminal reports 1-based column/row; `decode-mouse-sequence` converts to
    0-based `x`/`y` so mouse positions line up directly with the `screen` and
    `cursor` coordinate systems used elsewhere in the toolkit. See
    [Screen and Rendering](screen-and-rendering.md).

## The SGR mouse protocol

An SGR mouse report is `ESC [ < Cb ; Cx ; Cy M` for a press or motion, or the same
report with a trailing `m` for a release. `Cb` is a button byte that packs the
button number together with held-modifier bits, a motion flag, and a wheel flag;
`Cx`/`Cy` are the 1-based coordinates.

The button byte decodes as follows:

- **Low two bits** select the base button: `0` left, `1` middle, `2` right.
- **Bit 4 (`+4`)** shift, **bit 8 (`+8`)** alt, **bit 16 (`+16`)** control.
- **Bit 32 (`+32`)** marks motion: with a button held it is a `:drag`, with no
  button (low bits `3`) it is a `:move`.
- **Bit 64 (`+64`)** marks the wheel: low bits select `:wheel-up` / `:wheel-down` /
  `:wheel-left` / `:wheel-right`, with action `:scroll`.
- Otherwise the trailing byte decides the action: `M` is `:press`, `m` is
  `:release`.

## `decode-mouse-sequence`

`decode-mouse-sequence` decodes one report and returns two values: the
`mouse-event` and the number of characters consumed.

```lisp
(cl-tty-kit:decode-mouse-sequence
 (format nil "~C[<0;5;2M" #\Esc))          ; left press at terminal (5,2)
;; => #S(MOUSE-EVENT :BUTTON :LEFT :ACTION :PRESS :X 4 :Y 1 :MODIFIERS NIL), 9
```

When the input at `start` is not a complete report — a different sequence, or a
fragment still missing its `M`/`m` terminator — it declines by returning `nil` and
`0`, so a caller can fall back to ordinary key decoding. This is exactly how the
input decoder integrates mouse reports: `decode-input` and `decode-input-chunk`
route an `ESC [ <` prefix to the mouse decoder, and a fragment split across chunks
is buffered rather than mis-decoded as a bare `ESC`.

```lisp
;; A report missing its terminator does not decode.
(cl-tty-kit:decode-mouse-sequence (format nil "~C[<0;1;1" #\Esc))
;; => NIL, 0
```

Decoding can also start partway through a buffer via `:start`, which is what the
inline integration relies on.

## Actions: press, release, drag, move, wheel

`examples/mouse-decoding.lisp` decodes a spread of reports covering each action.
Given a small report builder:

```lisp
(defun %mouse-report (cb cx cy final)
  (format nil "~C[<~D;~D;~D~C" #\Esc cb cx cy final))
```

the reports and their decoded events are:

| Report | Button | Action |
| --- | --- | --- |
| `(%mouse-report 0 5 2 #\M)` | `:left` | `:press` |
| `(%mouse-report 0 5 2 #\m)` | `:left` | `:release` |
| `(%mouse-report 2 10 4 #\M)` | `:right` | `:press` |
| `(%mouse-report 64 7 7 #\M)` | `:wheel-up` | `:scroll` |
| `(%mouse-report 32 3 3 #\M)` | `:left` | `:drag` |

A few more from the test suite fill in the rest of the surface:

- `Cb = 1` → `:middle :press`
- `Cb = 65` → `:wheel-down :scroll`; `66`/`67` → `:wheel-left`/`:wheel-right`
- `Cb = 35` (`32 + 3`) → `:none :move` — motion with no button held
- `Cb = 3` → `:none :press` — low bits `3` is not a real button

Held modifiers combine additively with the button byte. A left press with shift and
control held is `Cb = 0 + 4 + 16 = 20`:

```lisp
(cl-tty-kit:mouse-event-modifiers
 (cl-tty-kit:decode-mouse-sequence (format nil "~C[<20;1;1M" #\Esc)))
;; => (:CONTROL :SHIFT)     ; normalized and sorted
```

## Enabling and disabling mouse reporting

A terminal only sends mouse reports after you ask it to. `ansi-enable-mouse` returns
the escape string that turns reporting on in a given tracking mode, and
`ansi-disable-mouse` returns the string that turns it back off. Like all the ANSI
helpers, these return plain strings for you to write to the terminal (see
[ANSI Helpers](ansi-helpers.md)).

```lisp
(cl-tty-kit:ansi-enable-mouse :button)   ; enable button-motion tracking + SGR
(cl-tty-kit:ansi-disable-mouse :button)  ; disable it again
```

The tracking mode selects how much the terminal reports:

| Mode | DEC mode | Reports |
| --- | --- | --- |
| `:normal` | 1000 | press and release only |
| `:button` (default) | 1002 | press/release plus motion while a button is held |
| `:any` | 1003 | all motion, button held or not |

`ansi-enable-mouse` always also enables SGR extended coordinates (DEC mode 1006), so
`decode-mouse-sequence` can parse the reports regardless of terminal size.
`ansi-disable-mouse` resets both, in reverse order.

!!! tip "Scope reporting to your app's lifetime"

    Enable mouse reporting when your app starts and disable it on exit, so the
    terminal is left clean. The [Terminal Session](terminal-session.md) helper is
    the natural place to bracket that lifecycle alongside the alternate screen and
    cursor visibility.

## See also

- [Input Decoding](input-decoding.md) — key events, and how mouse reports decode
  inline with them
- [ANSI Helpers](ansi-helpers.md) — `ansi-enable-mouse` / `ansi-disable-mouse` and
  the rest of the escape builders
- [Screen and Rendering](screen-and-rendering.md) — the 0-based coordinate system
  mouse events share
- [Terminal Session and Raw Mode](terminal-session.md) — scoping mouse modes
- [API Reference](api-reference.md) — the complete exported symbol list
