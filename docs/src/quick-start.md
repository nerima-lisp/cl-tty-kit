# Quick Start

This walks through the shortest path from an empty screen to a styled,
diff-rendered one, then a first look at input decoding. It assumes
`cl-tty-kit` is already loaded — see [Installation](installation.md).

```lisp
(load "scripts/bootstrap.lisp")
(cl-tty-kit/bootstrap:load-core-system)
(use-package :cl-tty-kit)
```

## Render a screen

`screen` is a pure grid of `cell` objects — no terminal I/O happens until you
explicitly render it. `make-screen` creates one, `screen-write-string` lays
out text, and `render-screen` turns the grid into an ANSI string:

```lisp
(let ((screen (make-screen 20 4)))
  (screen-write-string screen 0 0 "Hi")
  (format t "~A~%" (render-screen screen)))
```

Nothing here touches a TTY — `render-screen` returns a plain string, so you
can print it, test it, or feed it into any output stream. The full data model
is covered in [Screen and Rendering](screen-and-rendering.md).

## Add style

`make-style` builds a normalized style list from modifier keywords and color
entries. `screen-put-cell` accepts a `:style` argument per cell:

```lisp
(let ((screen (make-screen 12 1)))
  (screen-put-cell screen 0 0 #\H :style (make-style :bold (style-fg 196)))
  (screen-put-cell screen 1 0 #\i :style (make-style (style-fg 33)))
  (format t "~A~%" (render-screen screen)))
```

`style-fg`/`style-bg` accept either an indexed color (`(style-fg 196)`, xterm
256-palette) or RGB bytes (`(style-bg 17 34 51)`). See [Color](color.md) for
the full conversion API.

## Render only what changed

Real terminal apps redraw many times per second. `render-diff` compares two
screens of the same dimensions and emits only the changed cells — this is
what `examples/screen-update.lisp` and `examples/styled-render.lisp`
demonstrate:

```lisp
(let ((previous (make-screen 10 2))
      (current (make-screen 10 2)))
  (screen-put-cell current 0 0 #\H)
  (screen-put-cell current 1 0 #\i)
  (screen-put-cell current 0 1 #\!)
  (format t "~A~%" (render-diff current previous)))
```

For a real render loop across many frames, reach for the double-buffered
`renderer` instead of hand-tracking the previous screen yourself — see
[Screen and Rendering](screen-and-rendering.md#the-double-buffered-renderer).

## Decode input

`decode-input` turns a raw terminal input string — printable characters,
control bytes, escape sequences, kitty-protocol sequences, bracketed paste
markers — into a list of `key-event` structures:

```lisp
(decode-input (concatenate 'string "a" (string (code-char 3)) (string #\Esc) "[A"))
;; => (#S(KEY-EVENT :TYPE :CHARACTER :CODE #\a :MODIFIERS NIL)
;;     #S(KEY-EVENT :TYPE :SPECIAL :CODE :CONTROL-C :MODIFIERS NIL)
;;     #S(KEY-EVENT :TYPE :SPECIAL :CODE :UP :MODIFIERS NIL))
```

For a real terminal reading loop, use the streaming decoder instead of
one-shot `decode-input`, so partial reads at chunk boundaries don't produce
spurious errors — see [Input Decoding](input-decoding.md).

## Where to go next

- Work through more of `examples/` — every file is a small, runnable,
  documented program. See [Examples](examples.md) for the full index.
- Read [Screen and Rendering](screen-and-rendering.md), [Layout](layout.md),
  and [Widgets](widgets.md) for the rest of the display-side API.
- Read [Terminal Session](terminal-session.md) for putting a real terminal
  into raw mode and the alternate screen safely.
- Check [Compatibility](compatibility.md) before deploying — `cl-tty-kit`
  requires SBCL.
