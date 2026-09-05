# Input Decoding

`cl-tty-kit` turns the raw byte stream a terminal sends on stdin into a list of
structured `key-event` objects. Decoding is pure logic with no OS calls: callers
pass a string or an octet vector and receive events.

There are two entry points:

- **`decode-input`** — one-shot. Decode a complete buffer in a single call.
- **`make-input-decoder`** + **`decode-input-chunk`** + **`flush-input-decoder`** —
  streaming. Feed arbitrary read-sized chunks and let the decoder buffer partial
  UTF-8 and incomplete escape sequences across read boundaries.

Both share the single-sequence decoder `decode-key-sequence`, and both produce the
same `key-event` values.

## Non-blocking stream polling

For a single terminal input stream, `make-stream-input-poller` returns a
`(lambda (state timeout) ...)` adapter around `read-char-no-hang` that drains
at most `:limit` characters per call and returns the events decoded from them
(or `NIL` when nothing is ready). It retains the supplied incremental decoder
across frames, so an escape sequence split by the terminal or OS boundary is
not lost. Compose it with `tick-loop-run-realtime`'s `:poll` by folding the
returned events into state yourself:

```lisp
(let ((poll-input (make-stream-input-poller *standard-input*
                                            :decoder (make-input-decoder)
                                            :limit 4096)))
  (tick-loop-run-realtime state #'advance #'render #'quit-p
                          :poll (lambda (state)
                                  (reduce #'apply-event
                                          (funcall poll-input state 0)
                                          :initial-value state))))
```

The adapter never waits for input and ignores the timeout argument it is
passed. Its internal character buffer is reused between polls, so idle frames
do not allocate a temporary string stream; `:limit` remains the maximum number
of characters drained per call.
Applications multiplexing several file descriptors should keep their own
`select(2)`/`poll(2)` policy and feed ready bytes to `decode-input-chunk`
instead.

!!! note "Mouse events decode inline"

    `decode-input` and `decode-input-chunk` surface SGR mouse reports as
    `mouse-event` objects interleaved with the `key-event` objects, because the
    mouse decoder shares the CSI decode path. See
    [Mouse Input](mouse-input.md) for the `mouse-event` structure. This page
    covers key events.

## The `key-event` struct

Every decoded key is a `key-event`. It is a plain `defstruct`, so the exported
accessors are ordinary readers:

| Accessor | Meaning |
| --- | --- |
| `key-event-type` | `:character`, `:special`, or `:paste` |
| `key-event-code` | a character (`:character`), a keyword (`:special`), or a string (`:paste`) |
| `key-event-modifiers` | normalized list of `:control` / `:alt` / `:shift` |
| `key-event-kind` | `:press`, `:repeat`, or `:release` (kitty protocol) |
| `key-event-text` | associated text string, or `nil` (kitty protocol) |
| `key-event-shifted-key` | shifted alternate character, or `nil` (kitty protocol) |
| `key-event-base-key` | base-layout alternate character, or `nil` (kitty protocol) |

The `code` slot's type depends on `type`:

- `:character` — `code` is a `character` (a printable key, possibly with modifiers).
- `:special` — `code` is a keyword such as `:up`, `:enter`, `:f5`, `:page-up`.
- `:paste` — `code` is the pasted payload `string` (only when bracketed-paste
  collection is enabled; see below).

Modifiers are always normalized: de-duplicated and sorted by name, so equivalent
sets compare `equal` regardless of the order they arrived in.

```lisp
(cl-tty-kit:decode-input "a")
;; => (#S(KEY-EVENT :TYPE :CHARACTER :CODE #\a :MODIFIERS NIL ...))

(cl-tty-kit:decode-input (string (code-char 3)))  ; Ctrl-C
;; => (#S(KEY-EVENT :TYPE :SPECIAL :CODE :CONTROL-C :MODIFIERS NIL ...))
```

## One-shot: `decode-input`

`decode-input` decodes a whole buffer and returns a list of events. It accepts a
string or an octet vector; octet vectors are decoded as UTF-8, and malformed UTF-8
signals `invalid-utf8-sequence` (see [Conditions](../reference/conditions.md)).

`examples/key-decoding.lisp` decodes a buffer that exercises most of the surface at
once:

```lisp
(cl-tty-kit:decode-input
 (concatenate 'string
              "a"                              ; printable character
              (string (code-char 3))           ; Ctrl-C control byte
              (string #\Esc) "[A"              ; Up arrow (CSI)
              (string #\Esc) "[105;6u"         ; Ctrl-Shift-i (kitty CSI u)
              (string #\Esc) "[200~"           ; bracketed paste start marker
              (string #\Esc) "[201~"           ; bracketed paste end marker
              (string #\Esc) "[Z"              ; back-tab
              (string #\Esc) "[57363;3u"       ; Alt-Menu (kitty function key)
              (string #\Esc) "OA"              ; Up arrow (SS3 application mode)
              (string #\Esc) "x"))             ; Alt-x (ESC prefix)
```

The events come back in input order, one per decoded sequence.

## The decoded key surface

The decoder recognizes the full range of terminal input encodings.

### Printable characters and control bytes

A plain printable character decodes to a `:character` event. Control bytes map to
named special keys or `:control-<letter>` events:

| Input | Event |
| --- | --- |
| `#\a` | `:character #\a` |
| `Tab` (9) | `:special :tab` |
| `Enter` (10 or 13) | `:special :enter` |
| `Rubout` / `Backspace` (127 or 8) | `:special :backspace` |
| `NUL` (0) | `:special :null` |
| Ctrl-A .. Ctrl-Z | `:special :control-a` .. `:control-z` |
| Ctrl-\\, Ctrl-], Ctrl-^, Ctrl-_ | `:special :control-backslash`, `:control-right-bracket`, `:control-caret`, `:control-underscore` |

### UTF-8

Octet input is decoded as UTF-8, so multi-byte code points become single
`:character` events. A truncated trailing sequence is handled differently by the
one-shot and streaming paths (see [Streaming](#streaming-decode-input-chunk)).

### Arrows, SS3, and modified CSI

Arrow and navigation keys arrive as CSI sequences (`ESC [ ...`) or, in application
cursor mode, as SS3 sequences (`ESC O ...`). Both decode to the same keywords:

- `ESC [ A` and `ESC O A` → `:special :up`
- `ESC [ B` / `C` / `D` → `:down` / `:right` / `:left`
- `ESC [ H` / `F` → `:home` / `:end`
- `ESC [ Z` → `:backtab`
- `ESC O P` .. `ESC O S` → `:f1` .. `:f4`

A numeric modifier parameter attaches modifiers. `ESC [ 1 ; 5 C` is Ctrl-Right:

```lisp
(cl-tty-kit:decode-input (concatenate 'string (string #\Esc) "[1;5C"))
;; => (#S(KEY-EVENT :TYPE :SPECIAL :CODE :RIGHT :MODIFIERS (:CONTROL) ...))
```

The modifier field is the standard `xterm` encoding: subtract one to get a bitmask
where bit 1 is shift, bit 2 is alt, bit 4 is control. So a field of `5` means mask
`4`, i.e. control alone.

### Alt prefixes

An `ESC` immediately followed by an ordinary character is an Alt-modified key:

```lisp
(cl-tty-kit:decode-input (concatenate 'string (string #\Esc) "x"))
;; => (#S(KEY-EVENT :TYPE :CHARACTER :CODE #\x :MODIFIERS (:ALT) ...))
```

### CSI `~` keys

The `ESC [ N ~` family covers editing and function keys: `2` insert, `3` delete,
`5` page-up, `6` page-down, `1`/`7` home, `4`/`8` end, and `11`-`34` for F1-F20
(legacy encoding). With a modifier field, `ESC [ 3 ; 5 ~` is Ctrl-Delete.

### Kitty CSI `u` keys

The kitty / fixterms progressive-enhancement protocol encodes keys as
`ESC [ code ; modifiers u`. This carries Unicode code points directly and a large
set of extended special keys — F13-F35, keypad navigation and editing keys, media
transport keys, lock keys, and left/right modifier keys:

```lisp
(cl-tty-kit:decode-input (concatenate 'string (string #\Esc) "[105;6u"))
;; => (#S(KEY-EVENT :TYPE :CHARACTER :CODE #\i :MODIFIERS (:CONTROL :SHIFT) ...))

(cl-tty-kit:decode-input (concatenate 'string (string #\Esc) "[57363;3u"))
;; => (#S(KEY-EVENT :TYPE :SPECIAL :CODE :MENU :MODIFIERS (:ALT) ...))
```

Some of the many special codes: `:caps-lock`, `:num-lock`, `:print-screen`,
`:pause`, `:menu`, `:f13`..`:f35`, `:kp-0`..`:kp-9`, `:kp-enter`, `:kp-home`,
`:kp-delete`, `:media-play-pause`, `:media-track-next`, `:lower-volume`,
`:left-meta`, `:right-control`, and more (see `src/key-tables.lisp` for the full
table).

### Press / repeat / release and associated text

Under the kitty keyboard protocol, an event can be a key-down, an auto-repeat, or a
key-up. `key-event-kind` reports `:press`, `:repeat`, or `:release`. Without the
protocol enabled every event is `:press`.

The protocol also reports the text a key would insert (useful for IME and
international input where it differs from the key code) and the shifted / base-layout
alternates:

- `key-event-text` — the insertable text string.
- `key-event-shifted-key` — e.g. `a` shifted is `A`.
- `key-event-base-key` — the key at that physical position on the base layout
  (for layout-independent keybindings).

Enable the protocol with `ansi-set-keyboard-enhancements` (see
[ANSI Helpers](ansi-helpers.md)).

## `key-event->string`

For logging and debugging, `key-event->string` returns a compact human-readable
label. Modifiers become a `C-`/`M-`/`S-` prefix in Ctrl-Alt-Shift order; a
`:special` keyword is capitalized (`:control-x` shows as `C-x`); a `:paste` event
reports its payload length.

```lisp
(cl-tty-kit:key-event->string
 (cl-tty-kit:make-key-event :type :special :code :up :modifiers '(:shift)))
;; => "S-Up"

(cl-tty-kit:key-event->string (cl-tty-kit:make-key-event :code #\x))
;; => "x"
```

## The incomplete-sequence contract

The decoder never partially reinterprets a malformed or truncated escape sequence
as a synthetic special key. If a sequence cannot be fully decoded, it falls back to
a literal `ESC` event followed by the remaining characters, each decoded on its own:

```lisp
;; A malformed CSI parameter list, decoded one-shot, is not invented into a key.
(cl-tty-kit:decode-input (concatenate 'string (string #\Esc) "[1;aC"))
;; => (#S(... :CODE :ESCAPE) #S(... :CODE #\[) #S(... :CODE #\1) ...)
```

This keeps decoding total: any byte sequence decodes to *some* deterministic list of
events, and the only signaled error is `invalid-utf8-sequence` for malformed octets.

## Streaming: `decode-input-chunk`

Real terminal reads do not respect sequence boundaries — a single arrow key can
straddle two `read()` calls. The streaming decoder handles this by buffering the
undecodable tail of each chunk until a later chunk completes it.

Create a decoder with `make-input-decoder`, feed chunks with `decode-input-chunk`,
and (at EOF or transport close) drain the buffer with `flush-input-decoder`:

```lisp
(let ((decoder (cl-tty-kit:make-input-decoder)))
  (cl-tty-kit:decode-input-chunk decoder (string #\Esc))  ; => NIL, ESC held back
  (cl-tty-kit:decode-input-chunk decoder "[A"))           ; sequence completes
;; => (#S(KEY-EVENT :TYPE :SPECIAL :CODE :UP :MODIFIERS NIL ...))
```

What gets buffered across a boundary:

- **Trailing partial UTF-8** — the incomplete code units are held as octets until the
  rest of the byte arrives.
- **Incomplete escape sequences** — an `ESC`, a CSI without its final byte, or an SS3
  without its final byte is held rather than emitted as a spurious `:escape`.

Because the tail is buffered, split reads never emit spurious `:escape` events or
premature `invalid-utf8-sequence` errors. `flush-input-decoder` forces whatever is
still buffered through the one-shot fallback rules — useful at EOF or when a
transport closes. A buffered partial UTF-8 sequence flushed at EOF *does* then signal
`invalid-utf8-sequence` with reason `:truncated-sequence`.

!!! tip "Bounded buffering for untrusted input"

    `make-input-decoder` takes a `:max-pending` bound (default 4 MiB) on the
    still-undecoded tail it will retain. An unterminated sequence from a hostile
    source that would otherwise grow without limit instead signals a
    `tty-kit-error` once the bound is exceeded.

### Bracketed paste

By default, a bracketed paste block is surfaced as two marker events — a
`:special :paste-start` and a `:special :paste-end` — with the pasted characters as
ordinary events between them. This is what `decode-input` always does.

A streaming reader that wants the paste as a single payload can build the decoder
with `:collect-bracketed-paste t`. Completed paste blocks then arrive as one
`:paste` event whose `code` is the payload string, and the surrounding markers are
suppressed:

```lisp
(let ((decoder (cl-tty-kit:make-input-decoder :collect-bracketed-paste t)))
  (cl-tty-kit:decode-input-chunk
   decoder (concatenate 'string (string #\Esc) "[200~"))
  (cl-tty-kit:decode-input-chunk decoder "hello")
  (cl-tty-kit:decode-input-chunk
   decoder (concatenate 'string (string #\Esc) "[201~")))
;; => (#S(KEY-EVENT :TYPE :PASTE :CODE "hello" :MODIFIERS NIL ...))
```

The payload accumulates across as many chunks as it takes. `examples/streaming-paste.lisp`
shows a paste split across three chunks (`ESC[200~he`, `llo`, `ESC[201~`) collapsing
to a single `:paste "hello"` event.

If EOF arrives before the closing `ESC [ 201 ~`, flushing falls back to the raw
marker-plus-characters stream, so no input is discarded or invented.

Some terminals send CR-terminated (or CRLF-terminated) lines inside a bracketed
paste rather than bare LF. Building the decoder with
`:normalize-paste-line-endings t` converts a collected `:paste` event's payload
to LF-only before it is emitted, so callers that insert paste text into an
LF-delimited buffer do not need to re-implement that scan:

```lisp
(let ((decoder (cl-tty-kit:make-input-decoder :collect-bracketed-paste t
                                              :normalize-paste-line-endings t)))
  (cl-tty-kit:decode-input-chunk
   decoder
   (concatenate 'string
                (string #\Esc) "[200~"
                "one" (string #\Return) (string #\Newline) "two"
                (string #\Esc) "[201~")
   :eof t))
;; => (#S(KEY-EVENT :TYPE :PASTE :CODE "one
;; two" :MODIFIERS NIL ...))
```

This has no effect unless `:collect-bracketed-paste` is also true, since only
that mode produces a `:paste` event with an associated string to normalize.

## A full event loop

`examples/event-loop.lisp` composes the streaming decoder with the diff renderer
into a complete, deterministic terminal event loop. The shape is:

1. Create a decoder with `make-input-decoder :collect-bracketed-paste t`.
2. For each input chunk, `decode-input-chunk` and fold the events into application
   state (here: a counter that `j` and Up increment, `q` stops, and a paste adds its
   payload length).
3. Render each state transition as an incremental frame with `render-frame-diff`.
4. `flush-input-decoder` at the end to drain any tail.

```lisp
(defun %event-loop-apply-event (count event)
  (case (cl-tty-kit:key-event-type event)
    (:character
     (case (cl-tty-kit:key-event-code event)
       (#\j (values (1+ count) nil))
       (#\q (values count t))
       (otherwise (values count nil))))
    (:paste
     (values (+ count (length (cl-tty-kit:key-event-code event))) nil))
    (:special
     (case (cl-tty-kit:key-event-code event)
       (:up (values (1+ count) nil))
       (otherwise (values count nil))))
    (t (values count nil))))
```

This is the throughline from a one-shot `decode-input` all the way to a real
streaming app loop that reads, updates, and renders. See
[Screen and Rendering](screen-and-rendering.md) for the rendering half and
[Terminal Session and Raw Mode](terminal-session.md) for scoping the terminal
modes a live loop needs.

## See also

- [Mouse Input](mouse-input.md) — the `mouse-event` objects that decode inline
- [ANSI Helpers](ansi-helpers.md) — enabling bracketed paste, kitty keyboard
  enhancements, and focus reporting
- [Screen and Rendering](screen-and-rendering.md) — rendering state transitions
- [Terminal Session and Raw Mode](terminal-session.md) — scoping input modes
- [Conditions](../reference/conditions.md) — `invalid-utf8-sequence` and other signaled errors
- [API Reference](../reference/api.md) — the complete exported symbol list
