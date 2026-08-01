# PTY

`cl-tty-kit` includes a minimal pseudoterminal (PTY) abstraction for spawning a
child process attached to a terminal and exchanging bytes with it. It is the
foundation for things like a shell wrapper, a test harness that drives an
interactive program, or a terminal multiplexer.

Two layers sit side by side:

- a **stream layer** — the `pty` struct plus character-oriented read/write and
  lifecycle helpers, convenient for ordinary use; and
- an **fd layer** — the bare master file descriptor plus byte-transparent octet
  I/O, for multiplexer-style `select(2)` loops over many descriptors.

!!! warning "SBCL only"
    PTY support is part of the OS-facing, SBCL-specific layer and uses
    `sb-ext:run-program`. `cl-tty-kit` requires SBCL throughout, so `make-pty`
    and `close-pty` are available on every build that loads. See
    [Compatibility](../reference/compatibility.md).

!!! danger "make-pty does not sanitize PROGRAM, ARGS, or ENVIRONMENT"
    `make-pty` spawns with `sb-ext:run-program :search t`, so `PROGRAM` is
    resolved against `PATH` and `ARGS` / `ENVIRONMENT` pass **straight through**
    to the spawned process. This is the intended API surface, but it means a
    caller who forwards attacker-influenced strings into `PROGRAM`, `ARGS`, or
    `ENVIRONMENT` is choosing to let that data drive process execution.
    `make-pty` does **not** sanitize them — validate or constrain any untrusted
    input yourself before passing it in. See the org security policy if
    building a service around this.

## The pty struct

`pty` is a small struct with two slots, read via `pty-process` and `pty-stream`:

- `pty-process` — the underlying `sb-ext` process object, or `nil` for a
  stream-only PTY or after `close-pty` has cleared it.
- `pty-stream` — the bidirectional character stream connected to the child.

You normally create one with `make-pty` rather than the raw constructor.

## Spawning and lifecycle

`make-pty` spawns a program under a fresh PTY and returns a `pty`. All arguments
are keywords:

```lisp
(make-pty)                              ; defaults to /bin/sh
(make-pty :program "cat")
(make-pty :program "env" :environment '("TERM=dumb" "LANG=C"))
(make-pty :program "ls" :args '("-la") :directory "/tmp")
```

`:program` is a string resolved against `PATH`, `:args` a list of strings,
`:environment` `nil` or a list of `"NAME=value"` strings, and `:directory` a
string or pathname (or `nil`). Transient "resource temporarily unavailable"
spawn failures are retried a few times internally before giving up.

The lifecycle is: `make-pty` → drive it → observe exit with `pty-alive-p` /
`pty-exit-code` → `close-pty`.

- `pty-alive-p` returns true while the child is running, `nil` once it has
  exited or when the PTY has no process. Use it in a read loop to tell "no data
  yet" from "the child exited".
- `pty-exit-code` returns the child's integer exit code, or `nil` while it is
  still running. Read it *after* `pty-alive-p` turns `nil` and *before*
  `close-pty` clears the process slot: 0 means success, non-zero is the failure
  status.
- `close-pty` shuts the child down (closing the stream, then escalating through
  `SIGTERM`/`SIGKILL` if it does not exit) and returns the `pty`.

!!! note "close-pty is idempotent and always clears its slots"
    `close-pty` clears the stored process and stream **even if shutdown itself
    signals** `pty-operation-failed` — by that point the stream is already
    closed at the OS level, and leaving the slots populated would let a caller
    re-close an already-closed stream or retry a shutdown that already gave up.
    Calling `close-pty` again on an already-closed PTY is a harmless no-op.

## Reading and writing (stream layer)

`pty-write` sends data to the child; `pty-read` pulls available output back.

```lisp
(let ((pty (make-pty :program "cat")))
  (pty-write pty "hello")           ; accepts a string...
  (pty-write pty #(104 105 10))     ; ...or a vector of octets (UTF-8 decoded)
  (pty-read pty)                    ; => "hello\nhi\n" (whatever is ready), or NIL
  (close-pty pty))
```

`pty-write` accepts a string or an octet vector and always flushes, returning the
`pty`. `pty-read` reads up to `limit` characters (default 4096) without blocking
and returns a string when data is available, or `nil` when nothing is ready —
so a poll loop can distinguish "no data yet" (`nil` plus `pty-alive-p` true) from
"child gone" (`nil` plus `pty-alive-p` false).

A common pattern is to read until some marker appears, sleeping briefly between
empty reads:

```lisp
(let ((chunks '()))
  (loop repeat 50
        for chunk = (pty-read pty)
        do (when chunk (push chunk chunks))
           (sleep 0.01))
  (apply #'concatenate 'string (nreverse chunks)))
```

## Resizing

`pty-resize` tells the child its window changed by sending `TIOCSWINSZ` on the
PTY's descriptor — the child normally receives `SIGWINCH` and re-queries its
size. Forward this whenever your own window resizes:

```lisp
(pty-resize pty 120 40)   ; columns, rows
```

It signals `pty-operation-failed` when the size cannot be set — for example on a
platform whose ioctl constant is unknown, or a stream without an accessible
descriptor. `pty-resize` is a thin convenience over
[`set-terminal-size`](terminal-session.md), which does the same thing given a
bare fd; when the ioctl itself fails, the `terminal-size-set-failed` it raises
becomes the `pty-operation-failed-reason`.

## Failure reporting: pty-operation-failed

All the stream operations signal a single structured condition,
[`pty-operation-failed`](../reference/conditions.md), carrying:

- `pty-operation-failed-operation` — `:spawn`, `:read`, `:write`, `:resize`,
  `:close`, or an fd-layer operation;
- `pty-operation-failed-pty` — the `pty` involved, or `nil`;
- `pty-operation-failed-reason` — the underlying condition.

Spawn failures report `:spawn` and use `nil` for the PTY slot, because no PTY
object was created yet:

```lisp
(handler-case
    (make-pty :program "/definitely/missing")
  (pty-operation-failed (c)
    (list (pty-operation-failed-operation c)   ; => :SPAWN
          (pty-operation-failed-pty c))))       ; => NIL
```

Read and write failures report `:read` or `:write`, including closed-stream cases
after shutdown.

## The fd layer: multiplexer-style I/O

For a caller running its own `select(2)`/`poll(2)` loop over many descriptors —
a terminal multiplexer, say — the stream API is the wrong shape. The fd layer
exposes the raw master descriptor and byte-transparent octet I/O that coexist
with, and do not replace, `pty-read`/`pty-write`.

- `pty-fd` returns the integer master-side file descriptor backing the PTY's
  stream. Hand it to your event loop or to the octet functions below. It signals
  `pty-operation-failed` when the stream is closed or exposes no descriptor.
- `pty-pid` returns the child's process id, or `nil` when there is no process.

```lisp
(let* ((pty (make-pty :program "cat"))
       (fd  (pty-fd pty))
       (pid (pty-pid pty)))
  ;; register FD in your own select(2) set, keyed by PID
  ...)
```

### Byte-transparent octet I/O

`fd-read-octets` and `fd-write-octets` do exact-byte I/O on a bare integer fd
using `(simple-array (unsigned-byte 8))` buffers, with **no character decoding** —
the precise octets are preserved.

```lisp
(let ((buffer (make-array 4096 :element-type '(unsigned-byte 8))))
  (let ((n (fd-read-octets fd buffer)))
    (cond
      ((null n)     ...)   ; no data ready on a non-blocking fd — wait for select
      ((zerop n)    ...)   ; EOF — the peer closed the other end
      (t            ...))))  ; n bytes are at the front of BUFFER
```

`fd-read-octets` reads at most `limit` bytes (defaulting to, and capped at,
the buffer length) into the front of the buffer and returns:

- a **positive count** when bytes were read;
- **`0`** at end of file (the peer closed the other end);
- **`nil`** when a non-blocking fd has no data ready (`EAGAIN`/`EWOULDBLOCK`) or
  the call was interrupted by a signal.

It never blocks a non-blocking fd; on a blocking fd it blocks until data, EOF, or
error, so gate it with `select(2)`/`poll(2)`.

`fd-write-octets` writes an octet vector verbatim and returns the integer number
of bytes written:

```lisp
(fd-write-octets fd (coerce #(104 105 10) '(simple-array (unsigned-byte 8) (*))))
; => 3
```

It retries `EINTR` internally and loops over short writes, so on a blocking fd it
writes every byte and returns the full length. On a non-blocking fd it stops when
the kernel buffer fills (`EAGAIN`/`EWOULDBLOCK`) and returns a short count — send
the remaining octets once the fd is writable again.

A hard OS error in either function is wrapped in `pty-operation-failed`.

## See also

- [Terminal Session and Raw Mode](terminal-session.md) — putting your own
  terminal into raw mode before relaying bytes to a child PTY.
- [Conditions](../reference/conditions.md) — the `pty-operation-failed` accessors.
- [Compatibility](../reference/compatibility.md) — the SBCL-only rationale.
- [API Reference](../reference/api.md) — the full exported symbol list.
