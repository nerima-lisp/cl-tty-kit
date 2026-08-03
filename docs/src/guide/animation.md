# Animation

Three small, independent additions support building an animated terminal
app on top of the screen/renderer model: a **tick-loop driver**, a
**transparent sprite blitter**, and a **minimal moving entity**. None of them
introduce a new abstraction over what the rest of `cl-tty-kit` already
gives you — they are thin helpers a caller composes with ordinary Lisp
(lists, loops) rather than a framework to opt into.

!!! note "Package"

    All symbols are exported from `cl-tty-kit`. See
    [Getting Started](../getting-started.md) for loading the system.

!!! warning "Deliberately out of scope"

    There is no z-order/layer/compositing-order concept here. Painting order
    is controlled at the call site by the order `sprite-blit` and
    `screen-blit` calls run in (back to front) — see
    [Screen and Rendering](screen-and-rendering.md). There is likewise no
    entity-component-system or particle system; `entity` is a plain struct,
    and a collection of them is just a Lisp list your own code loops over.

## The pure/impure split

`examples/renderer-loop.lisp` and `examples/event-loop.lisp` already
establish this repository's idiom for a loop: a **pure state-advance
function** (old state in, new state out, no I/O, no wall clock) kept
separate from a **thin real-IO loop** that paces ticks, reads input, and
writes frames. `tick-loop-run` and `tick-loop-run-realtime` are that split
made reusable, so a downstream app does not have to hand-write both a
deterministic test harness and a real loop around the same state machine.

## Bounded mode: deterministic ticks

`tick-loop-run` calls a caller-supplied `advance` function exactly `ticks`
times, threading each result into the next call, and returns the final
state:

```lisp
(tick-loop-run 0 #'1+ 5)
;; => (values 5 nil)
```

Pass `:render` (a function of one state, returning a frame — typically a
string from `render-screen` or `render-diff`) to also collect the sequence
of frames, one per tick, in tick order:

```lisp
(tick-loop-run 0 #'1+ 3 :render (lambda (n) (format nil "tick ~D" n)))
;; => (values 3 ("tick 1" "tick 2" "tick 3"))
```

No real TTY, no wall clock, and no sleeping happen in this mode — it is the
mode a downstream app's own test suite should drive its game/animation loop
through, asserting on an exact final state or frame sequence the way
`renderer-loop-example` in `examples/renderer-loop.lisp` asserts on exact
rendered output.

## Real-time mode: paced output

`tick-loop-run-realtime` repeatedly calls the same kind of `advance`
function, but paces ticks to a target frame `:interval` (seconds, default
`1/30`), writes each tick's rendered frame to a real `:stream`, and keeps
going until a caller-supplied `stop` predicate returns true. An optional
`:poll` function runs before each tick and returns the state to pass to
`advance`; use it for bounded input waits and resize checks:

```lisp
(tick-loop-run-realtime
 initial-state
 #'advance-game-state
 #'render-game-frame
 (lambda (state) (game-state-quit-p state))
 :stream *standard-output*
 :interval 1/20)
```

For a real resident application, `:poll` should wait no longer than the frame
interval. On SBCL, `stream-fd` gives the descriptor, `fd-wait` avoids blocking
the redraw loop indefinitely, and `fd-read-octets` preserves terminal bytes for
`decode-input-chunk`:

```lisp
(let ((fd (stream-fd input)))
  (when (fd-wait fd :input (/ 1.0 30))
    (let ((count (fd-read-octets fd buffer)))
      (dolist (event (decode-input-chunk decoder buffer))
        (handle-event state event)))))
```

Poll `terminal-size` from the same function. When the dimensions change, call
`renderer-resize`; it drops the old diff snapshot so the next frame is a full
repaint. If code outside the renderer writes terminal output, call
`renderer-invalidate` before the next render for the same reason. A complete
bounded example is `interactive-dashboard.lisp` (see [Examples](examples.md)):
load it for a non-interactive frame, or call `run-interactive-dashboard` from a
TTY and press `q` to exit.

`stop` is checked *after* a tick has been advanced and rendered, so the loop
always emits the frame that caused it to stop rather than swallowing it.
Pacing uses a monotonic internal-time deadline for each frame rather than
sleeping a fresh interval after every render. Scheduler overshoot therefore
does not accumulate as drift; if a frame overruns its deadline, the loop
resynchronizes to the current time instead of issuing a burst of catch-up
frames.

The compatibility string-frame driver accepts either a string or `NIL` from
`render`; `NIL` suppresses output for that tick without allocating an empty
string. Other return values signal an error. Use the direct-stream variant
when the renderer already writes to the stream and can return a boolean output
flag.

Both modes call the same internal per-tick step, so behavior exercised under
bounded-mode tests carries over unchanged to the real-time driver — the
bounded/real-time distinction is only in pacing and where output goes, never
in what one tick does.

!!! note "Signals remain application policy"

    This repository polls `terminal-size` rather than trapping SIGWINCH (see
    [Terminal Session and Raw Mode](terminal-session.md)), so the caller owns
    resize policy. The same applies to signals and shutdown: translate them to
    the state consumed by the `stop` predicate.

## Transparent sprite blitting

`sprite-blit` composites a block of multi-line ASCII art onto a `screen`,
treating a marker character (a blank space by default) as **pass-through**:
a transparent source cell leaves the destination cell beneath it untouched
instead of overwriting it.

```lisp
(let ((screen (make-screen 6 4 :initial-cell #\.)))
  (sprite-blit screen (format nil "AB~%CD") 1 1)
  (screen-to-string screen))
;; => "......
;;     .AB...
;;     .CD...
;;     ......"
```

This is the piece `screen-blit` (see
[Screen and Rendering](screen-and-rendering.md#region-operations)) does not
offer: `screen-blit` always copies every cell of its source region,
including its blanks, so it cannot by itself composite an irregular sprite
over existing content. `sprite-blit` is clipped to the screen the same way
`screen-blit` clips a region — a sprite placed partly or fully off-screen
draws only its visible overlap, on any of the four edges, rather than
signaling:

```lisp
(let ((screen (make-screen 3 1 :initial-cell #\.)))
  (sprite-blit screen "ABCDE" 1 0)   ; runs past the right edge
  (screen-row-string screen 0))
;; => ".AB"
```

`:transparent` overrides the marker character, and `:style` applies to every
non-transparent cell written:

```lisp
(sprite-blit screen sprite-text x y :transparent #\- :style (make-style :bold))
```

A ragged line — shorter than the sprite's own widest line — is transparent
past its own end, so a non-rectangular sprite does not need trailing
padding.

## Minimal moving entities

`entity` is a position `(x, y)` plus a velocity `(dx, dy)` and an optional
`on-exit` callback — nothing else. `entity-tick` is the only operation:

```lisp
(let ((entity (make-entity :x 5 :y 5 :dx 1 :dy 0)))
  (entity-tick entity 80 24)
  (values (entity-x entity) (entity-y entity)))
;; => (values 6 5)
```

`entity-tick` adds the velocity to the position and, when the new position
falls outside the given `width` by `height` bounds, calls `on-exit` once per
violated edge — in order `:left`, `:right`, `:top`, `:bottom` — as
`(funcall on-exit entity edge)`:

```lisp
(let* ((respawned nil)
       (entity (make-entity :x 0 :y 5 :dx -1 :dy 0
                            :on-exit (lambda (entity edge)
                                       (declare (ignore edge))
                                       (setf (entity-x entity) 79)
                                       (setf respawned t)))))
  (entity-tick entity 80 24)
  (values (entity-x entity) respawned))
;; => (values 79 t)
```

An entity that exits through a corner (both an x and a y bound violated in
the same tick) fires `on-exit` twice, once per edge. `width` and `height`
are passed to each `entity-tick` call rather than stored on the entity, so a
caller can check against a freshly polled `terminal-size` every tick.

Managing more than one entity is ordinary Lisp: a list of `entity` structs,
`mapc`'d over with `entity-tick` once per game tick, is the whole pattern —
`cl-tty-kit` does not add a container type for this.

## Putting it together

A caller's `advance` function for `tick-loop-run`/`tick-loop-run-realtime`
typically: calls `entity-tick` on each live entity (with an `on-exit` that
removes or repositions it), clears and redraws a `screen` with `screen-fill`
and one `sprite-blit` per entity in back-to-front order, and returns the new
state. The `render` function then hands that screen to `render-diff` or a
`renderer` (see [Screen and Rendering](screen-and-rendering.md)) to produce
the frame `tick-loop-run`/`tick-loop-run-realtime` collects or streams.

## See also

- [Screen and Rendering](screen-and-rendering.md) — `screen-blit`, the
  double-buffered `renderer`, and the render/diff functions that turn a
  screen into ANSI.
- [Examples](examples.md) — `examples/renderer-loop.lisp` and
  `examples/event-loop.lisp`, the pure/impure split this file's tick loop
  generalizes.
- [Terminal Session and Raw Mode](terminal-session.md) — `terminal-size`,
  polled by a caller's own loop rather than by `tick-loop-run-realtime`.
- [API Reference](../reference/api.md) — the complete exported symbol list.
