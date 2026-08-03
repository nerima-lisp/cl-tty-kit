# Terminal Session and Raw Mode

This page covers the OS-facing layer that puts the terminal into the right state
for a full-screen application and reliably restores it afterward: raw mode, the
window-size query and update, and the `with-terminal-session` lifecycle helper.

!!! warning "SBCL only"
    Raw mode, `terminal-size`, `set-terminal-size`, and `with-terminal-session`'s
    raw-mode path are SBCL-specific — they use `sb-posix` for `termios` control
    and SBCL's `ioctl` wrapper. `cl-tty-kit` requires SBCL throughout, so these
    are available on every build that loads. See
    [Compatibility](../reference/compatibility.md).

## Raw mode

By default a terminal is in *cooked* (canonical) mode: it buffers a line, echoes
keystrokes, and interprets control characters like `C-c` locally. A full-screen
application needs the opposite — every byte delivered immediately, no echo, no
signal interpretation — which is **raw mode**.

`enable-raw-mode` and `disable-raw-mode` toggle it for a file descriptor
(defaulting to standard input, fd 0). `enable-raw-mode` snapshots the current
`termios` settings before changing them, and `disable-raw-mode` restores that
snapshot exactly.

### with-raw-mode

Prefer the scoped macro, which guarantees restoration with `unwind-protect` even
if the body unwinds:

```lisp
(with-raw-mode (0)
  ;; standard input is now byte-transparent; read and decode here
  ...)
;; the terminal is restored to its prior settings on the way out
```

### Reference-counted nesting

Nested `with-raw-mode` scopes, or repeated `enable-raw-mode` calls on the same
fd, are **reference-counted**. Each enable increments a depth counter; the
terminal is only restored when the *outermost* scope exits. This
lets independent components each request raw mode without fighting over who
restores it:

```lisp
(with-raw-mode (0)            ; depth 1 — terminal enters raw mode
  (with-raw-mode (0)          ; depth 2 — no-op, just increments
    ...)
  ...)                        ; inner exit — depth back to 1, still raw
;; outer exit — depth 0, terminal restored
```

### Failure reporting

If a `termios` operation fails, both functions signal
[`raw-mode-operation-failed`](../reference/conditions.md) carrying the `operation`
(`:enable` or `:disable`), the `fd`, and the underlying `reason` condition — so
a caller can report precisely what failed on which descriptor.

!!! note "More raw than cfmakeraw"
    The raw configuration clears a strict *superset* of the classic
    `cfmakeraw` input flags — additionally disabling break handling, input
    marking, stripping, and CR/NL translation. That leaves the input stream
    fully byte-transparent, which is exactly what a terminal multiplexer needs
    when it feeds the bytes verbatim to a child PTY. Every added flag only
    *removes* input processing, so it remains a valid raw mode for ordinary
    callers.

## terminal-size

`terminal-size` queries the current window size with `ioctl(TIOCGWINSZ)` and
returns `(values columns rows)`:

```lisp
(terminal-size)     ; => 80, 24   (on a real terminal)
(terminal-size 0)   ; same, fd given explicitly
```

It returns `(values nil nil)` — rather than signaling — when the fd is not a
terminal, the ioctl fails, the report is zero-sized, or the platform's
`TIOCGWINSZ` constant is unknown. Treat `nil` as "size unavailable" and fall
back to a default (commonly 80×24) or a cursor-position probe:

```lisp
(multiple-value-bind (cols rows) (terminal-size)
  (let ((cols (or cols 80))
        (rows (or rows 24)))
    ...))
```

To react to live resizes, re-query on `SIGWINCH`.

## set-terminal-size

`set-terminal-size` is the write direction of the same ioctl pair — it issues
`ioctl(TIOCSWINSZ)`, which is how a terminal, or a multiplexer owning the master
side of a PTY, tells a child process that its window changed. The child normally
receives `SIGWINCH`. Arguments mirror `terminal-size`: columns first, then rows,
then an optional fd defaulting to 0. It returns `(values columns rows)`, so the
result reads back in the same shape the getter reports:

```lisp
(set-terminal-size 100 30 master-fd)   ; => 100, 30
(terminal-size master-fd)              ; => 100, 30
```

Reach for it when you own the master side of a PTY and are propagating your own
window size down to the child. If you already hold a `pty` object,
[`pty-resize`](pty.md) is the same operation with the fd extraction done for you.

!!! warning "It signals; the getter does not"
    `terminal-size` reports an unknown size as `(values nil nil)` because a
    caller can substitute a default. `set-terminal-size` instead signals
    [`terminal-size-set-failed`](../reference/conditions.md), carrying the `fd`,
    the requested `columns`/`rows`, and a `reason` — because a size that was
    never applied leaves the child believing in a window it does not have, and
    no fallback repairs that. `columns` and `rows` must be positive integers and
    `fd` a non-negative integer; those are rejected before any ioctl is issued.

!!! note "Why SBCL's ioctl wrapper, not a hand-declared alien routine"
    Both directions go through `sb-unix:unix-ioctl` rather than a
    `define-alien-routine` (or an equivalent generic FFI `foreign-funcall`)
    declaration of `ioctl`. `ioctl` is variadic, and on the arm64 ABI variadic
    arguments are passed on the stack while a fixed-prototype alien call passes
    them in registers — so the kernel reads the `winsize` pointer from the wrong
    place and the call fails with `EFAULT`. SBCL's own wrapper marshals it
    correctly. This is why the operation lives here rather than being
    reimplemented by each caller.

## with-terminal-session

`with-terminal-session` is a thin composition helper that wraps a body in the
common full-screen lifecycle: enter the alternate screen, hide the cursor, flush
output, run the body, and then **guarantee** teardown with `unwind-protect` — in
reverse order — no matter how the body exits.

The macro binds a stream variable and takes keyword options:

```lisp
(with-terminal-session (session :stream *standard-output*)
  (write-string (render-screen screen) session))
;; on exit: cursor shown, alternate screen exited, output flushed
```

### Options

| Option | Default | Effect |
| --- | --- | --- |
| `:stream` | `*standard-output*` | Where session escapes and body output are written. |
| `:alternate-screen` | `t` | Enter/leave the alternate screen buffer. |
| `:hide-cursor` | `t` | Hide the cursor for the session, restore on exit. |
| `:bracketed-paste` | `nil` | Enable bracketed-paste markers, scoped to the session. |
| `:keyboard-enhancements` | `nil` | Push kitty keyboard enhancement `<flags>`; auto-popped on cleanup. |
| `:mouse` | `nil` | Enable mouse tracking (`:normal`, `:button`, or `:any`) for the session. |
| `:focus-reporting` | `nil` | Report terminal focus-in/focus-out events. |
| `:disable-line-wrap` | `nil` | Disable automatic line wrapping until teardown. |
| `:raw-mode` | `nil` | Wrap the whole session in `with-raw-mode`. |
| `:fd` | `0` | The fd used when `:raw-mode t`. |

Setup steps are attempted defensively: if one step fails, it is left un-done so
its matching teardown is skipped and the body still runs. Teardown always emits
the reverse sequence for whatever setup actually succeeded and flushes the
stream.

### Bracketed paste and keyboard enhancements

`:bracketed-paste t` turns on the DEC private-mode paste markers for the duration
of the body and disables them on exit, so paste input arrives bracketed only
while your session owns the terminal. `:keyboard-enhancements <flags>` pushes a
kitty keyboard progressive-enhancement scope with `ansi-push-keyboard-enhancements`
on entry and pops it with `ansi-pop-keyboard-enhancements` on exit — a clean
push/pop pair so you never leak enhancement state to the shell.

### Composing with raw mode

Pass `:raw-mode t` (and, if not fd 0, `:fd n`) to wrap the entire session in
`with-raw-mode`. This is the usual full-screen setup — raw input plus alternate
screen plus hidden cursor — in one form:

```lisp
(with-terminal-session (session :raw-mode t :fd 0
                                :bracketed-paste t
                                :keyboard-enhancements 1)
  ;; input is raw here; drive your event loop and render frames
  (write-string (render-screen screen) session))
```

## Example: a scoped session

`examples/terminal-session.lisp` renders a small screen inside a session with
bracketed paste and keyboard enhancements enabled. Note that everything —
alternate screen, cursor hide, paste markers, and enhancement flags — is scoped
to the body and torn down automatically:

```lisp
(let ((screen (make-screen 18 3)))
  (screen-write-string screen 0 0 "TTY" :style '(:bold))
  (screen-write-string screen 4 0 "demo")
  (screen-write-string screen 0 1 "Press")
  (screen-write-string screen 6 1 "q to")
  (screen-write-string screen 11 1 "exit")
  (with-terminal-session (session :stream *standard-output*
                                  :bracketed-paste t
                                  :keyboard-enhancements 1)
    (write-string (render-screen screen) session)))
```

The companion macro `with-terminal-session-output` captures the emitted escape
sequences into a returned string instead of writing to a live terminal, which is
handy in tests and examples. It is exported from the `cl-tty-kit` package, so
callers can use `cl-tty-kit:with-terminal-session-output` directly.

## See also

- [PTY](pty.md) — spawning and driving a child process under a PTY.
- [Screen and Rendering](screen-and-rendering.md) — the `render-screen` /
  `render-diff` output you emit inside a session.
- [ANSI Helpers](ansi-helpers.md) — the individual escape builders
  `with-terminal-session` composes.
- [Conditions](../reference/conditions.md) — `raw-mode-operation-failed`,
  `terminal-size-set-failed`, and the condition hierarchy.
- [Compatibility](../reference/compatibility.md) — the SBCL-only rationale.
