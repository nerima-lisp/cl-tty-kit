# Changelog

## Unreleased

## 0.1.0 - 2026-07-20

- correct the README "Compatibility" section: the library requires SBCL and no
  longer claims that its pure subsystems run on other Common Lisp
  implementations (they use `sb-unicode`/`sb-ext`); the pure/OS-facing split is
  documented as an internal architecture property, not a portability guarantee
- gate the `sb-posix` dependency on `#+sbcl` and fail fast with a clear
  "requires SBCL" error on other implementations, instead of ASDF reporting a
  confusing missing `sb-posix` system
- widen the `cursor` coordinate slots to `(integer 0)` and tighten
  `%assert-screen-dimensions` (non-negative fixnum sides whose product fits
  `array-total-size-limit`) so out-of-range coordinates/dimensions signal the
  documented `cursor-parameter-invalid` / `screen-dimensions-invalid` instead of
  a raw `type-error` or `make-array` failure
- fix the README embedded-logic-engine example, which stated an output of
  `((ISAAC JACOB JOSEPH))` without defining the `(parent jacob joseph)` clause
- stop `%preferred-diff-commands` fully rendering both the full-screen and diff command lists into throwaway strings just to compare their byte lengths; it now sums each command's part lengths directly, cutting a screen-sized render pass (or two) out of every diff frame that shares its previous frame's dimensions
- add a memoization cache for a cell's SGR escape sequence (`%cell-style-sequence`), so the same style's escape string is built once and reused across the length-comparison and real-render passes and across every cell sharing that style, instead of being rebuilt from scratch each time
- make `%cell-equal-p` compare cells' already-normalized raw style lists first and only fall back to rebuilding their SGR code lists when the raw styles actually differ, avoiding per-cell SGR recomputation for the common case (matching cells) on every diff frame
- add an ASCII/Latin fast path to `char-width`'s code-point classification (code points below U+0300, verified to contain no zero-width or wide code point) so writing plain ASCII/Latin text no longer pays a `sb-unicode:general-category` table lookup per character; verified to agree with the prior classification across every Unicode code point (0 through U+10FFFF)
- serialize raw-mode enable/disable (`*raw-mode-states*` plus the accompanying `TCGETATTR`/`TCSETATTR` calls) behind a mutex on threaded SBCL builds, closing a check-then-act race that could corrupt the depth refcount or drop a saved termios snapshot when two threads share a raw-mode fd, potentially leaving the real terminal stuck in raw mode after exit
- reset a `pty`'s `process`/`stream` slots in `close-pty` even when shutdown signals `pty-operation-failed`, since the underlying stream is already closed by that point; previously a failed close left the slots pointing at an already-closed stream and a give-up process, so a caller could reuse a dead stream or double-close on retry
- cap the digit run `%parse-csi-integer` (CSI parameter parsing) will parse at 18 digits, so an attacker-controlled multi-megabyte all-digit CSI body can no longer force an unbounded bignum parse; over-long runs fall back to ordinary character-by-character decoding like other malformed escapes
- fix `screen-write-string` ignoring `char-width`: it used to advance one column per character, so a double-width character (CJK/emoji) misaligned every following cell on the row and a run that didn't actually fit in the requested display width was silently accepted; it now advances by each character's `char-width` and fills the trailing column of a double-width character with a blank spacer cell, so the bounds check reflects real display width
- vendor `takeokunn/cl-prolog` and `takeokunn/cl-weave` as git submodules under `vendor/`, pinned to their latest upstream HEAD (both are ahead of their newest tagged release and are not distributed by Quicklisp), and add two opt-in contrib integrations on top of them: `cl-tty-kit-cl-prolog-csi-grammar`, a DCG recognizer for the ECMA-48 CSI byte-class grammar, and `cl-tty-kit-weave-tests`, a property-based fuzz suite that generates thousands of arbitrary octet sequences against `src/utf8.lisp`'s decoder and the public `decode-input` entry point and asserts they only ever fail with a documented `tty-kit-error`, never an undocumented Lisp error; see `contrib/README.md`
- restore compilation on modern SBCL by fixing the condition `:report` macro expansion
- implement the documented public API that was missing: `make-screen`, `screen-resize`, `screen-clear`, `screen-fill-rect`, `screen-write-string`, `make-cursor`, `cursor-visible-p`, `move-cursor`, `string-width`, `decode-input`, `decode-input-chunk`, and `flush-input-decoder`
- restore and extend the embedded logic engine's public API: `make-clause-db`, `define-clauses`, and the advanced relational predicates `or/*`, `true/0`, `fail/0`, `call/1`, and `findall/3`
- append clauses in O(1) amortized time so large rule sets load in linear time
- resolve East Asian / emoji wide-character width by binary search over the sorted range table instead of a linear scan, speeding up `string-width` on wide text (verified equivalent across every Unicode code point)
- keep full runtime safety when decoding untrusted terminal input (drop `(optimize (safety 0))`)
- bound the streaming input decoder's buffered tail (`make-input-decoder :max-pending`, 4 MiB default) so an unterminated escape or bracketed paste from an untrusted source cannot exhaust memory
- fix input decoding bugs: control-byte and Alt-prefixed key mapping, CSI final-byte detection, streaming UTF-8 boundary buffering, and bracketed-paste event ordering
- stop `decode-input` crashing with an uncaught TYPE-ERROR on an empty CSI-u body such as `ESC [ u`; it now falls back to ordinary decoding like other malformed escapes
- make the logic engine's `call/1`, `findall/3`, and variable goals in `and`/`or` fail gracefully on a non-compound goal term instead of crashing, and give `findall/3` fresh variables for template positions the goal leaves unbound (ISO behavior)
- fix diff rendering emitting only the last changed run and make terminal-session setup resilient to a failed setup step
- add opt-in `contrib/` integrations with the latest external libraries, isolated from the core build and CI: a `cl-prolog2` bridge that runs the embedded clause database on an external ISO Prolog, and a `clweb` (literate "weave") module; see `contrib/README.md` and `contrib/verify-contrib.lisp`
- make the test harness robust to ASDF output translations so `scripts/test.lisp` runs regardless of fasl cache configuration
- define a repository-local quality gate for release readiness and contract discipline
- document project governance and security reporting
- add a runnable streaming bracketed-paste collector example
- add tests for public package exports and error-report text
- expand key decoding coverage for control bytes and SS3 sequences
- cover bracketed paste markers and BackTab in key decoding tests and example output
- add examples for rendering, key decoding, and screen update flows
- add a styled rendering example and deduplicate example loading lists
- split examples into pure return-value functions plus explicit runners
- remove recursive ASDF reload warnings from example-backed tests
- add a regression test for style-only render-diff updates
- document and test `render-diff` fallback/full-redraw behavior and multi-row updates
- enforce README example and verification command coverage in package tests
- make `scripts/verify.lisp` run the fresh source-registry packaging smoke as part of the main gate
- lock the README Quick Start rendering example to an executable test
- enforce that runnable `examples/*.lisp` files stay registered in `scripts/example-files.lisp`
- broaden regression coverage for extended kitty/fixterms CSI `u` special keys
- normalize style modifiers so equivalent style sets compare consistently
- add indexed and truecolor cell styling for foreground and background render paths
- add public `make-style`, `style-fg`, and `style-bg` helpers for validated color style construction
- add a deterministic event-loop example that composes streaming input decode with frame diffs
- align PTY unsupported behavior across implementations
- document compatibility boundaries and unsupported-feature contracts
- keep the public API focused on terminal primitives and TTY handling
- publish ASDF homepage, issue tracker, source-control, maintainer, and version metadata
- add explicit SBCL timeouts to repository verification, examples, and coverage scripts
