# Changelog

## Unreleased

## 0.6.0 - 2026-07-25

- add an explicit timeout to `scripts/source-registry-smoke.lisp`, the one
  documented `docs/QUALITY-GATES.md` entrypoint that lacked one --
  `scripts/test.lisp`, `verify.lisp`, `coverage.lisp`, and `examples.lisp`
  all already wrap their work in `SB-EXT:WITH-TIMEOUT` via a `WITH-*-TIMEOUT`
  macro, but this script's `RUN-TESTS` call (the same potentially slow call
  `test.lisp` already guards) had no bound. Added the identical
  `*SMOKE-TIMEOUT-SECONDS*`/`WITH-SMOKE-TIMEOUT` pattern at the same
  120-second budget as `test.lisp`. Verified both directions: the happy
  path still runs the full suite end to end via
  `sbcl --script scripts/source-registry-smoke.lisp`, and a scratch SBCL
  session confirms the wrapper actually re-signals a clear, labeled error
  on a genuinely slow body rather than silently doing nothing
- add a model-based `cl-weave` property test to `t/properties.lisp`:
  `GEN-STATE-MACHINE` drives `SCREEN-COPY`/`SCREEN-PUT-CELL` through random
  mutation sequences on a 4x3 screen and replays the resulting state trace,
  checking that `RENDER-DIFF` between every adjacent (previous, current)
  pair never exceeds a full `RENDER-SCREEN` repaint in length -- the
  invariant `%PREFERRED-DIFF-COMMANDS` (`src/render-diff.lisp`) is
  documented to guarantee (it falls back to a full repaint whenever the
  diff would not be shorter) and which this session separately proved by
  cross-function call-graph analysis when investigating that file's
  coverage gaps. This is `cl-weave` used beyond the pure-function algebraic
  laws already in this file: the existing `t/properties.lisp` blocks are
  single-call properties (`clamp`, `parse-hex-color`, `%split-on-char`,
  etc.); this is the first stateful, sequence-based property in the suite,
  built on a `cl-weave` generator (`gen-state-machine`) none of the
  project's existing property or mutation tests use. Verified the property
  holds across three separate test-suite runs and prototyped it directly in
  a live SBCL session (including confirming `RENDER-DIFF` of an unchanged
  screen returns `""`, not `NIL`) before writing it into the test file
- readability: `src/format.lisp`'s `FORMAT-PROGRESS-BAR` computed
  `(and (plusp remainder) (< complete width))` twice -- once to decide
  whether to write the fractional glyph, again three lines later, inline,
  to decide whether the empty-cell count needs to subtract one for it.
  Bound it once as `PARTIAL-P` and reused it, removing the duplicate
  boolean and the confusing nested `IF` inside a `DOTIMES` count expression
- readability: `src/color.lisp`'s `%PARSE-RGB-FUNCTIONAL` hand-rolled a
  comma-or-space tokenizer with manual index bookkeeping
  (`loop with start = 0 for index = (position-if ...) ...`), duplicating
  what `%SPLIT-ON-CHAR` (`src/text-layout.lisp`, loaded earlier in the same
  system) already does for single-delimiter splitting. Replaced with
  `(substitute #\, #\Space body)` followed by `%SPLIT-ON-CHAR` on comma and
  dropping empty pieces -- verified this produces the identical token list
  for both the comma-separated and space-separated forms before applying,
  and the existing malformed-input test cases (wrong part count, embedded
  non-digit, oversized/negative components) all still pass unchanged
- add `flake.nix`: a `devShell` (SBCL + Git, matching what
  `docs/QUALITY-GATES.md`'s bootstrap/verify gate needs locally) and
  `nix run .#test` / `.#verify` / `.#coverage` apps mirroring
  `.github/workflows/ci.yml`'s steps. The apps run the repository's own
  scripts against the current working directory rather than the flake's
  `self` source copy, deliberately: ASDF loading this system needs
  `vendor/cl-prolog`/`vendor/cl-weave`, which are git submodules that
  `git submodule update --init` populates locally but which Nix's
  git-tracked-files filtering of `self` never includes -- a hermetic build
  isn't this project's architecture, so the flake doesn't pretend otherwise.
  Verified `nix flake check`, `nix develop -c sbcl --version`, `nix run
  .#test`, and `nix run .#verify` all succeed for real, not just evaluate.
  Documented briefly in `README.md`'s Installation section
- extract `%PARSE-ESC-O-PREFIXED` from `src/keys-decode-internals.lisp`'s
  `%PARSE-ESC-PREFIXED`: the `ESC O` (SS3) branch nested `let > when > let >
  let > when` five levels deep inline to extract one byte and look up its
  key code, while its `ESC [` (CSI) sibling one branch up already delegated
  to a flat, separately-named `%PARSE-CSI-PREFIXED`. Extracting the SS3
  branch the same way removes the asymmetry and the extra nesting with no
  behavior change -- confirmed by the full suite, including the SS3
  (F1-F4) decode tests in `t/keys.lisp`/`t/input.lisp`, passing unchanged
- close a real coverage gap in `src/terminal-size.lisp`: `TERMINAL-SIZE`
  and `%SET-TERMINAL-SIZE` each wrap their `SB-UNIX:UNIX-IOCTL` call in a
  `(handler-case (...) (error () ...))`, but every existing test either used
  a valid tty-or-not FD (never erroring) or a value `%ASSERT-TERMINAL-FD`
  itself rejects (`-1`, `"fd"` -- never reaching the ioctl call at all).
  Verified empirically that an FD passing that guard (a non-negative
  integer) but too large for the C `int` `UNIX-IOCTL` marshals it into
  raises a genuine `TYPE-ERROR` at the FFI boundary -- distinct from an
  ordinary ioctl failure (a closed FD), which `UNIX-IOCTL` reports by
  returning `NIL`, not by signaling. Added `(expt 2 40)` FD cases to
  `t/session.lisp`'s `%TEST-TERMINAL-SIZE` for both functions
- close a real coverage gap in `src/sgr-parse.lisp`'s `DECODE-SGR`: a
  color-reset code (39/49/59)'s removal filter checks `(and (consp item)
  (first item))`, since `ITEMS` mixes cons-shaped color entries with bare
  modifier keywords (`:BOLD` etc.) -- but every existing color-reset test
  case reset a color with no modifier already accumulated, so the `CONSP`
  false path (confirming a modifier survives untouched) was never
  exercised. Added `"1;31;39"` (bold, then set and immediately clear the
  foreground) to `t/render-core.lisp`'s SGR grammar table, verified
  empirically to leave `(:BOLD)`
- close a real coverage gap in `src/utf8.lisp`'s `%OCTET-INPUT-P`: this
  predicate had zero direct tests despite a specific documented contract
  ("strings and character vectors do not [count as octet input]"), and
  neither of its two callers ever reaches it with a string -- both
  `%INPUT->STRING` and `%DECODER-DECODE-CHUNK-STRING` check `STRINGP`
  themselves first -- so the string branch of its own `(not (stringp
  input))` conjunct was entirely unverified, indirectly or directly. Added
  a small direct-unit-test block to `t/utf8.lisp` covering the predicate's
  own contract (string, character vector, octet vector) rather than relying
  solely on indirect exercise through its callers
- close a real coverage gap in `src/cell.lisp`'s `%CELL-STYLE-ITEMS`:
  `MAKE-CELL`'s `:STYLE` argument accepts a bare, unwrapped modifier
  keyword (e.g. `:BOLD`) in addition to a style list -- the function's own
  final `(T (LIST STYLE))` clause exists specifically to wrap that case --
  but every existing test always passed a list, even for a single modifier
  (`'(:BOLD)`), so the wrapping branch was never reached. Verified
  empirically in a live SBCL session before writing the assertion. Added
  to `t/render-core.lisp`
- close a real coverage gap in `src/screen.lisp`'s `%ASSERT-SCREEN-BOUNDS`:
  a negative X or Y reaching `SCREEN-CELL`/`(SETF SCREEN-CELL)`/
  `SCREEN-PUT-CELL` directly was never tested. Every existing bounds-error
  case tested an X or Y *too large*; the negative-coordinate case that
  exists elsewhere in the suite (e.g. `SCREEN-FILL-RECT` with negative X/Y)
  used a zero-area rect, which short-circuits before `%ASSERT-SCREEN-BOUNDS`
  is ever called. Verified empirically in a live SBCL session before
  writing assertions. Added cases to `t/screen.lisp`'s
  `%TEST-SCREEN-BOUNDS-AND-DIMENSION-ERRORS`
- documented, rather than tested, two provably-unreachable branches in
  `src/render-diff.lisp` found spanning a caller/callee pair: (1)
  `%EMIT-DIFF-RUN`'s `(unless (> next-x x) (error ...))` can never fire,
  because its sole caller (`%DIFF-RENDER-COMMANDS`) only invokes it from a
  branch already confirmed `(not (%cell-equal-p current old))` at that same
  `x`, and `%WRITE-DIFF-RUN` re-checks that identical, unmutated comparison
  as its very first loop iteration -- guaranteeing at least one cell is
  written before any early return; (2) `%PREFERRED-DIFF-COMMANDS`'s final
  `(T (%screen-render-commands screen))` clause can never fire, because
  `%DIFF-RENDER-COMMANDS` is only ever called with `:max-length screen-length`,
  and its `emit-counted` helper returns `too-long-p` the instant any partial
  length would reach that bound -- so a normal return guarantees the final
  `diff-length` is already `< screen-length`, satisfying the preceding
  clause first. Both are kept rather than deleted: the first prevents an
  infinite loop in the caller's advancing `DO` loop if the invariant is ever
  violated by a future change, and the second is a low-cost safety net
  whose worst case, if it ever did fire, is an unnecessary full repaint
  rather than incorrect output -- proportionate defense given what each
  guards against, following this session's established practice of
  documenting an invariant's proof in the source rather than force-testing
  an unreachable branch or deleting a guard whose failure mode is severe
- close a real coverage gap in `src/box.lisp`'s `%DRAW-BOX-TITLE`: an empty
  `TITLE` string is truthy (`(and "" ...)` is true), so it still enters the
  title-writing branch, but clips to zero cells and should write nothing --
  a distinct case from the already-tested `NIL` title (skips the branch
  entirely) and the already-tested too-wide title (clips to a *non-empty*
  prefix). Verified empirically in a live SBCL session before writing the
  assertion. Added to `t/box.lisp`'s `%TEST-BOX-TITLE`
- close a real coverage gap in `src/sixel.lisp`'s `ANSI-KITTY-IMAGE`, found
  on a fresh coverage pass over a file already partly fixed this session:
  its zero-area-image special case (an empty base64 payload gets a single
  `m=0` chunk rather than entering the chunking loop) was untested, even
  though the analogous zero-area case was already covered for `FORMAT-SIXEL`
  earlier -- every existing `ANSI-KITTY-IMAGE` success case used a
  non-empty image. Verified empirically in a live SBCL session before
  writing the assertion. Added to `t/format.lisp`'s `%TEST-KITTY-IMAGE`
- close real coverage gaps in `src/pty.lisp`: `MAKE-PTY`'s `ARGS`/`ENVIRONMENT`
  validation only ever saw a list *containing* a bad element, never a bare
  non-list value (`%LIST-OF-STRINGS-P`'s `LISTP` conjunct was consequently
  never false), and `PTY-RESIZE`'s `ROWS` only had its plusp-failure and
  integer-failure-on-`COLUMNS` cases -- a non-integer `ROWS` specifically
  was untested, unlike the matching `COLUMNS` case. Verified empirically in
  a live SBCL session before writing assertions. Added cases to
  `t/pty.lisp`. Left `%TERMINATE-PTY-PROCESS`'s SIGTERM/SIGKILL escalation
  and its "process survived both signals" hard-failure branch untested: no
  spawned test process outlives closing its PTY stream long enough to need
  escalation, and deliberately spawning one that resists `SIGKILL` would be
  unsafe and platform-fragile to construct -- the same class of judgment
  call as the `EINTR` retry path documented earlier in `src/pty-fd.lisp`
- close real coverage gaps in `src/screen-regions.lisp`, on a fresh
  re-check of a file previously reported to have none: `SCREEN-BLIT`'s
  `DEST-X`/`DEST-Y`/`SRC-X`/`SRC-Y` are validated only as integers by
  `%ASSERT-SCREEN-OFFSET` (not non-negative), so a negative offset is a
  legitimate way to clip the top or left edge of a blit -- symmetric to the
  already-tested right/bottom-edge clipping via an oversized `SRC-X`/`WIDTH`
  -- but no test exercised it in any of the four cases. `SCREEN-ROW-STRING`
  also had two untested branches of its bounds check: a negative `START`
  and a `START` greater than `END`, as opposed to the only two error cases
  previously tested (row too large, `END` past the screen width). Verified
  empirically in a live SBCL session before writing assertions. Added cases
  to `t/screen.lisp`'s `%TEST-SCREEN-ROW-STRING` and `%TEST-SCREEN-BLIT`
- close real coverage gaps in `src/char-width.lisp`: this file had only six
  existing test cases across the whole suite (ASCII, newline, one combining
  mark, one CJK ideograph, one emoji, and the East-Asian-Ambiguous section
  sign) for what is otherwise dense, security-adjacent branching logic. Never
  tested: a `:CF`-category zero-width code point other than the one explicit
  exception (`U+00AD` soft hyphen, which stays width 1 while `U+200D` ZWJ is
  width 0 -- confirming the exception fires correctly in both directions),
  the explicit Hangul Jamo zero-width range (`U+1160`-`U+11FF`, decided by
  range rather than general category), the C0/C1 control code points other
  than newline (`DEL` at `#x7F` and a C1 control at `#x80`), and a
  non-integer `STRING-WIDTH` bound. Verified empirically in a live SBCL
  session before writing assertions. Added cases to `t/text-layout.lisp`'s
  `%TEST-AMBIGUOUS-WIDTH`
- close real coverage gaps in `src/keys-decode-internals.lisp`'s kitty
  CSI-u decoder: `%PARSE-CSI-TEXT`'s multi-code-point loop continuation (a
  `:'-separated *second* code point) and its malformed-code-point early
  return were both unreached -- the one existing text-field test used a
  single code point, so `%PARSE-CSI-TEXT` never looped more than once and
  never saw an out-of-range value; an empty text field (`97;1;`, nothing
  between the second `;` and the final byte) was likewise untested; and a
  fourth `;`-separated field or a non-digit character embedded in a field
  were both unreached failure paths of `%PARSE-CSI-BODY`/`%PARSE-CSI-INTEGER`
  -- every existing kitty test used well-formed, at-most-three-field,
  all-digit sequences. Verified empirically in a live SBCL session before
  writing assertions (including correcting an initial wrong assumption
  about which fallback event a malformed sequence decodes to). Added five
  cases to `t/keys.lisp`'s `%TEST-KITTY-AND-F-KEYS`. Also documented, rather
  than tested, why `%CODE-POINT-CHARACTER`'s `(unless char (error ...))`
  branch is unreachable in practice on SBCL: `CHAR-CODE-LIMIT` is
  `#x110000`, one past the `#x10FFFF` ceiling its only caller already
  enforces, so `CODE-CHAR` always succeeds there -- kept as a portability
  guard rather than deleted, same reasoning as the `EAGAIN`/`EWOULDBLOCK`
  case in `src/pty-fd.lisp`
- close real coverage gaps in `src/text-layout.lisp`, the largest batch this
  session: `PAD-STRING`'s `:CENTER` alignment never split an odd deficit
  (every existing case used an even one, so `%REPEAT-CHAR`'s zero-count
  branch on the shorter side was unreached), `%HARD-SPLIT-WORD`'s
  zero-progress guard for a glyph wider than the split WIDTH itself was
  untested, `EXPAND-TABS`'s `TAB-WIDTH` type check only ever failed on
  non-positive integers (never a non-integer), and `%SKIP-ESCAPE-SEQUENCE`
  had three distinct "the sequence never properly terminates" paths --
  bare trailing ESC, unterminated CSI (no final byte before the string
  ends), and unterminated OSC (no BEL/ST before the string ends) -- none
  exercised, since every existing `STRIP-ANSI` case used complete,
  well-formed sequences. Verified all six cases empirically in a live SBCL
  session before writing assertions. Added cases to `t/text-layout.lisp`'s
  `%TEST-PAD-STRING`, `%TEST-EXPAND-TABS`, `%TEST-CHOP-STRING`, and
  `%TEST-STRIP-ANSI`
- close a real coverage gap in `src/rect.lisp`'s `%DISTRIBUTE-REMAINING`: its
  largest-remainder leftover-distribution loop body (`(incf (nth index
  result))`) never ran, because every existing multi-`:FILL`/`:MIN`
  `LAYOUT-SPLIT` test happened to use widths and weights that divide evenly
  -- `LEFTOVER` was always 0. A single-`:FILL` split never reaches the loop
  meaningfully either (its one weighted share always floors to exactly
  `REMAINING`). Verified empirically in a live SBCL session that three equal
  `:FILL` weights splitting a width of 10 -- 10/3 does not divide evenly --
  distributes the one leftover column to the first index. Added this case
  to `t/rect.lisp`'s `%TEST-LAYOUT-SPLIT`. The rest of this file's reported
  gaps (the `DEFSTRUCT`, `SETF DOCUMENTATION`, and the `%DEFINE-RECT-SPLIT`
  macro *definition* itself, as opposed to its two expansions) are the same
  documented sb-cover data/macro-definition artifact as elsewhere
- close a real coverage gap in `src/render-commands.lisp`'s `%CURSOR-EQUAL-P`:
  its 3-way `AND` (X, Y, and visibility all equal) only ever took its
  fully-true path or failed on the third (visibility) conjunct -- every
  existing "cursor changed" test case happened to keep X and Y equal and
  only vary visibility, so the X-differs and Y-differs short-circuit paths,
  reached only when a screen is otherwise unchanged (`%FRAME-DIFF-RENDER-COMMANDS`
  in `src/render-diff.lisp` short-circuits past `%CURSOR-EQUAL-P` entirely
  once the screen diff is non-empty), were never taken. Verified empirically
  in a live SBCL session before writing assertions. Added an X-differs and a
  Y-differs case, each with an unchanged screen, to `t/render-diff.lisp`'s
  `%TEST-RENDER-DIFF-BASIC-OUTPUT-CASES`
- also re-verified `src/cursor.lisp` and `src/renderer.lisp`, both flagged
  at 66.7% branch coverage: every flagged line in both is `DEFSTRUCT`
  slot/`SETF DOCUMENTATION` scaffolding or the `DEFINE-CURSOR-SETTERS`
  macro-expansion machinery, none of it real branching logic -- confirms
  the same sb-cover data-definition artifact documented in
  `docs/QUALITY-GATES.md`, not a gap
- remove a mathematically-redundant special case in `src/keys-decode.lisp`'s
  `%SCALE-HEX-TO-BYTE`: the `(zerop maximum) 0` branch can never fire.
  `MAXIMUM` is `(1- (expt 16 digits))`, and the function's own
  `%BOUNDED-DIGIT-RUN-P` guard already requires `(< START END)`, so `digits`
  (`(- end start)`) is always at least 1 -- making `MAXIMUM` always at least
  15, for every current and possible caller, not just the current one.
  Verified directly (`digits=1` gives 15, `digits=4` -- the field-width cap
  -- gives 65535). Documented the invariant in the docstring instead of
  leaving unreachable code for a future reader to puzzle over
- close real coverage gaps in `src/keys-decode.lisp`: `DECODE-DEVICE-ATTRIBUTES`'s
  ESC/`[` mismatch and its `?`/`>` prefix bounds check, `DECODE-COLOR-REPORT`'s
  "no `rgb:` in the body" failure, and `DECODE-CURSOR-POSITION-REPORT`'s
  "report found but missing its `;` separator" failure were all untested --
  every existing malformed-input case for these three OSC/CSI report
  decoders failed at an earlier check in the same guard chain, never
  reaching these specific ones. Verified empirically in a live SBCL session
  before writing assertions. Added cases to `t/keys.lisp`'s
  `%TEST-DEVICE-ATTRIBUTES`, `%TEST-COLOR-REPORT`, and
  `%TEST-CURSOR-POSITION-REPORT`
- close real coverage gaps in `src/mouse.lisp`: `DECODE-MOUSE-SEQUENCE`'s
  `char= ... #\<` check was only ever reached in already-covered form,
  never actually taking its false branch -- the existing "non-mouse CSI"
  case (`ESC[A`) is too short to pass the preceding length guard, so
  execution never reaches the `<' check at all. `%BOUNDED-DIGIT-RUN-P`'s
  `digit-char-p` loop body likewise never saw a non-digit character embedded
  within an otherwise-plausible field -- every existing malformed-field case
  was either empty or overlong, both caught by the surrounding length checks
  before the loop runs. Verified empirically in a live SBCL session before
  writing assertions. Added a long-enough non-mouse-CSI case and an
  embedded-non-digit-field case to `t/mouse.lisp`'s
  `%TEST-MOUSE-PARTIAL-AND-OFFSET`
- close real coverage gaps in `src/screen-text.lisp`: `SCREEN-WRITE-ALIGNED`'s
  zero-width/zero-height-rect no-op and empty-TEXT no-op were never
  exercised (every existing rect and TEXT was non-degenerate), and
  `SCREEN-WRITE-LINES`/`SCREEN-WRITE-WRAPPED` only had off-screen-to-the-
  right and past-the-bottom no-op cases from an earlier round -- a negative
  X, a negative Y, and (for `SCREEN-WRITE-LINES`) an empty line string were
  still untested, each a distinct silent-no-op branch symmetric to the ones
  already covered. Verified empirically in a live SBCL session before
  writing assertions. Added cases to `t/screen.lisp`'s
  `%TEST-SCREEN-WRITE-ALIGNED`, `%TEST-SCREEN-WRITE-LINES`, and
  `%TEST-SCREEN-WRITE-WRAPPED`
- close real coverage gaps in `src/color.lisp`: `RGB-TO-HSL`/`RGB-TO-HSV`'s
  hue formula never took its "blue is the dominant channel" branch (every
  existing case was red- or green-dominant), `RGB-TO-HSL`'s saturation
  formula never took its lightness-above-50%-branch, `HSL-TO-RGB`'s Q
  formula never took its lightness-below-50% branch (every existing case
  used exactly 50%), `HSV-TO-RGB`'s hue-wheel `ECASE` only ever exercised
  sextants 0 and 4, and `%PARSE-RGB-FUNCTIONAL`'s component-count guard
  (`rgb()` with well-formed parens but the wrong number of comma-separated
  values) was never reached -- every existing malformed-input case failed
  earlier, at the paren-matching check. Values verified empirically in a
  live SBCL session before writing assertions. Added cases to `t/color.lisp`'s
  `%TEST-HSL`, `%TEST-HSV`, and `%TEST-PARSE-AND-CONTRAST`
- close real coverage gaps in `src/pty-fd.lisp`: `FD-READ-OCTETS`'s negative-
  `LIMIT` rejection and both `FD-READ-OCTETS`/`FD-WRITE-OCTETS`'s hard-OS-error
  `(t (error ...))` fallback were never exercised. Verified empirically that a
  syntactically valid but never-opened fd (`987654`) reaches the real
  `unix-read`/`unix-write` syscall and returns `EBADF` (errno 9 on macOS),
  distinct from the `EAGAIN`/`EINTR` retry path -- deterministic and
  non-flaky, unlike forcing a genuine `EINTR` via signal delivery. Added
  three cases to `t/pty.lisp`'s `test-pty-fd`. Separately documented, rather
  than tested, why `%FD-WOULD-BLOCK-ERRNO-P`'s and `FD-WRITE-OCTETS`'s
  `EWOULDBLOCK` disjuncts stay uncovered: `EAGAIN` and `EWOULDBLOCK` share
  the same numeric errno (35) on both of this project's CI platforms (macOS
  confirmed directly; Linux/glibc `#define`s `EWOULDBLOCK` as `EAGAIN`), so
  `EAGAIN`'s `eql` always matches first and the `EWOULDBLOCK` arm is
  genuinely unreachable there -- kept in the source as a POSIX-portability
  guard rather than deleted, since unlike this session's earlier dead-code
  removals this isn't provable as unreachable in the abstract, only on the
  platforms actually in CI
- close a real coverage gap in `src/input-decode-internals.lisp`'s
  `%INCOMPLETE-ESCAPE-SEQUENCE-P`: its final `(t nil)` clause -- reached
  when a buffered ESC is immediately followed by a plain character that is
  neither a CSI (`[`) nor an SS3 (`O`) prefix, correctly declaring the
  sequence already decodable rather than still-pending -- was never
  exercised. Every existing streaming ESC case used a `[` or `O` prefix, and
  `%incomplete-escape-sequence-p` is skipped entirely during one-shot
  `DECODE-INPUT` (`EOF` is always true there), so the codebase's only other
  ESC-plus-plain-char case (`examples/key-decoding.lisp`'s Alt+x) never
  reached this function either. Verified empirically in a live SBCL session
  that streaming `ESC` then `"z"` across a chunk boundary decodes as Alt+z
  immediately, matching one-shot decoding of the same input. Added this
  case to `t/input-data.lisp`'s `+STREAMING-INPUT-CASES+`
- close real coverage gaps in `src/sixel.lisp`'s `FORMAT-SIXEL`: three
  encoder branches were never exercised by any test, because every existing
  case used a uniform single-color image at most 2x2 in size. `%SIXEL-EMIT-RUN`'s
  run-length-compressed `"!"N` output (fires only past a 3-column run of one
  color), the inter-band `"-"` separator (fires only when the image is
  taller than one 6-row band), and `%SIXEL-BAND-STATE-ADD-RUN`'s `"?"` gap
  filler together with the inter-color `"$"` separator (both fire only when
  a band holds more than one color) were all silently unreached. Verified
  empirically in a live SBCL session before writing assertions, since these
  are encoder implementation details rather than documented contracts.
  Added a 4-wide single-color case, a 7-tall single-color case, and a
  2-color case to `t/format.lisp`'s `%TEST-SIXEL`
- deduplicate the character-vector coercion fallback shared by
  `src/keys-decode.lisp`'s `%INPUT->STRING` and `src/input-decode.lisp`'s
  `%DECODER-DECODE-CHUNK-STRING`: both functions carried byte-for-byte
  identical `vectorp`/`t` clauses (validate every element is a character,
  coerce, or signal). Extracted to a single `%COERCE-CHARACTER-VECTOR` in
  `src/utf8.lisp` next to `%OCTET-INPUT-P`, which both callers now delegate
  to. This also closed a real coverage gap shared by both original clauses:
  the catch-all "Unsupported input type" branch was never exercised by any
  test -- existing cases only covered a malformed *vector* (an element that
  isn't a character), never a non-vector, non-string input entirely (e.g. an
  integer). Added `(decode-input 42)` and `(decode-input-chunk decoder 42)`
  cases to `t/input.lisp`, which cover the shared branch for both call sites
  at once
- close real coverage gaps in `src/format.lisp`: `FORMAT-COLUMNS`'s
  `(listp fields)`/`(listp widths)` guard and `FORMAT-TABLE`'s `(listp
  rows)` guard were never exercised -- every existing `signals-non-type-error`
  case passed a well-formed list containing a bad element (e.g. `'(:not-a-string)`,
  `'((:bad))`), never a bare non-list atom for `fields`/`widths`/`rows`
  themselves. Added `(format-columns :not-a-list '(3))`,
  `(format-columns '("a") :not-a-list)`, and `(format-table :not-a-list)`
  cases to `t/format.lisp`
- close a real coverage gap in `PTY-RESIZE`: `%validate-pty-size`'s
  non-positive/non-integer COLUMNS and ROWS rejection was never exercised --
  only successful resizes and the separate "no file descriptor" failure were
  tested
- remove a mathematically-redundant check in `src/utf8.lisp`'s
  `%utf8-validate-code-point`: the F4-leading-byte-specific overflow guard
  can never fire, because for a 4-byte sequence starting with `#xF4`, any
  second octet above `#x8F` already assembles a code point above `#x10FFFF`
  (verified both by direct calculation and by confirming the boundary case
  `second-octet = #x8F` assembles to exactly `#x10FFFF` with the remaining
  bytes maximized) -- so the general upper-bound check three lines above
  always signals first. Verified safe with extra care as security-sensitive
  code parsing untrusted terminal input: the core suite, and
  `contrib/verify-contrib.lisp`'s cl-weave property-based fuzz suite (which
  specifically stresses this decoder with thousands of arbitrary octet
  sequences) both pass unchanged
- simplify `src/keys.lisp`'s `%key-event-body`, removing three layers of
  unreachable defensive branching: `%assert-key-event-code` (run by every
  `make-key-event` call) already guarantees a `:character` event's code is a
  character, a `:paste` event's code is a string, and (by elimination, since
  `%assert-key-event-type` allows only those three types) a `:special`
  event's code is a keyword -- the function's own `(cond (characterp ...)
  (keywordp ...) (t (princ-to-string ...)))` fallback chain and the `:paste`
  branch's `(if (stringp code) ... 0)` guard could never take their other
  branch. Found while chasing a coverage gap and confirmed by attempting to
  write a test that reached them, which instead surfaced the invariant
  `make-key-event` already enforces
- remove genuinely unreachable dead code: `src/rect.lisp`'s
  `%constraint-weight` re-validated that its argument was a cons, but its
  only caller (`%layout-solve-sizes`) always runs every constraint through
  `%constraint-baseline` first, which performs the identical check and
  errors before `%constraint-weight` is ever reached with a malformed
  constraint -- confirmed by `%constraint-weight` having no other caller in
  either `src/` or `t/`
- close a real coverage gap in `SCREEN-WRITE-LINES`/`SCREEN-WRITE-WRAPPED`:
  an X at or past the screen's right edge (a perfectly valid non-negative
  integer, distinct from the type-validation cases already covered) silently
  no-ops rather than erroring, but no test exercised that path
- close a real decoding gap: `#\Rubout` (DEL, 0x7F -- what a terminal's
  Backspace key actually sends) decoding to `(:special :backspace)` had zero
  test coverage. `#\Rubout` appeared elsewhere in the suite only as a generic
  control-character fixture, never exercised through `decode-key-sequence`
- record this refactor's engineering rationale as a permanent, durable part
  of the repository rather than only in review discussion: `docs/QUALITY-GATES.md`
  (and its mkdocs mirror `docs/src/quality-gates.md`) gain a "Macro usage
  policy" and a "File organization policy" section, codifying when `defmacro`
  is the right tool versus a plain function, when a file is a genuine
  splitting candidate versus already at its natural grain, and why a file
  dominated by top-level data definitions routinely under-reports under
  `sb-cover` -- this was previously implicit in the existing "Coverage
  policy" section's "not vanity percentages" framing and this session's
  commit history, now made explicit for future contributors
- verify, by loading the live system and walking every external symbol of
  `#:cl-tty-kit` with `do-external-symbols` and checking `documentation`,
  that all 249 exported public symbols carry a docstring (0 missing) --
  a comprehensive, tool-verified readability check of the whole public API
  surface, not a sample
- close a real coverage gap in `SCREEN-SCROLL`: the docstring and an existing
  comment already claimed "a zero-width or zero-height screen is a no-op",
  but no test ever called it on one -- only the separate "zero COUNT" case
  was covered. Added both empty-screen cases to `t/screen.lisp`
- deduplicate the bounded-digit-run guard shared by `src/mouse.lisp`'s
  `%parse-mouse-uint` (decimal) and `src/keys-decode.lisp`'s
  `%scale-hex-to-byte` (hex) into one `%bounded-digit-run-p` in `mouse.lisp`,
  parameterized on radix
- readability: extract `src/rect.lisp`'s `%largest-remainder-order` out of
  `%distribute-remaining`'s densest line (an inlined sort-by-fractional-
  remainder for the layout constraint solver's largest-remainder method),
  giving that step a name and a docstring instead of a one-line
  `mapcar`/`sort`/`loop` nested three deep
- add the `%define-osc-color-query` macro to `src/ansi-osc.lisp` (matching the
  existing `define-ansi-function` declarative-generation idiom) and rewrite
  `ansi-request-foreground-color`/`ansi-request-background-color` on top of
  it, removing the duplicated OSC-framing `format` call between the two
  functions
- add a `cl-weave:gen-tuple`-composed custom generator to `t/properties.lisp`
  for a new `blend-colors` invariant (blending a color with itself returns
  that color at any ratio), going beyond the existing single-primitive
  (`gen-integer`/`gen-string`) generators to a genuinely composite one
- deduplicate `src/ansi-osc.lisp`'s `%osc-control-character-p` and
  `src/render-style.lisp`'s `%terminal-control-character-p` -- identical C0/C1
  control-character predicates under different names -- into one shared
  `%terminal-control-character-p` in `src/ansi-osc.lisp` (loaded before
  `render-style.lisp`)
- adopt `cl-weave:with-soft-assertions` (new in v0.11.0) in
  `contrib/weave-mutation-tests.lisp`'s three "case battery matches the live
  function" checks: previously the first mismatched case aborted the check
  immediately, hiding any other broken cases in the same battery; now every
  case is checked and every failure reported together
- close real branch-coverage gaps in `src/terminal-size.lisp` (81.3% -> 89.6%
  expression, 77.3% -> 95.5% branch): the unrecognized-platform fallback (no
  known `TIOCGWINSZ`/`TIOCSWINSZ` constant) was never exercised even though
  `+tiocgwinsz+`/`+tiocswinsz+` are ordinary special variables a test can
  rebind directly, and `%stream-fd`'s `two-way-stream`/`synonym-stream`
  unwrapping branches had no direct test
- extend the cl-weave mutation-test suite
  (`contrib/weave-mutation-tests.lisp`) with a fourth target,
  `%proper-list-p`, bringing it to 4 mutation-tested functions across 8
  assertions (was 3 functions / 6 assertions)
- deduplicate `src/cell.lisp`'s `%proper-style-list-p` and
  `src/screen-text.lisp`'s `%proper-screen-text-list-p` -- identical
  proper-list-p bodies under different domain-specific names -- into one
  shared `%proper-list-p` in `src/clamp.lisp`
- add a property-based round-trip law for `%split-on-char` to
  `t/properties.lisp` (splitting a delimiter-joined triple recovers the
  original pieces for arbitrary generated strings) and close a real branch
  gap in `src/box.lisp`'s `%draw-box-title`: no test previously exercised a
  box drawn with a `:title` and a `:style` but no `:title-style`
- **replace the hand-rolled embedded logic engine with `nerima-lisp/cl-prolog`
  itself.** `src/prolog-package.lisp`, `prolog-bindings.lisp`, `prolog-db.lisp`,
  `prolog-engine.lisp`, and `prolog-primitives.lisp` (the compact `cl-tty-kit/prolog`
  unification/CPS-prover/clause-db/primitives implementation) are deleted; the
  core system now depends on `#:cl-prolog` directly (vendored as a git
  submodule at `vendor/cl-prolog`, source-registry-registered by
  `cl-tty-kit.asd` itself so a plain `(asdf:load-system :cl-tty-kit)` resolves
  it standalone). Every consumer — `t/prolog-*.lisp`, `t/sgr-prolog-oracle.lisp`
  — is rewritten against cl-prolog's real API (`prolog`/`define-rulebase`,
  `extend-rulebase`, `query-prolog`/`prolog-succeeds-p`/`solution-binding`,
  `unify`/`logic-substitute`) instead of a `tty-prolog:` façade, verified
  empirically against the live library rather than assumed from the retired
  engine's contract:
  - `unify` returns `(values extended-env ok)`, not a bindings-or-`+fail+`
    sentinel; occurs-check violations and even a directly circular host cons
    fail cleanly with no error (cl-prolog compares cyclic structure
    coinductively) — cl-prolog does *not*, however, guard a circular goal term
    at the query level the way the retired engine's `%assert-prolog-term-safe`
    did, so that case is no longer exercised
  - `:max-depth` (bounding user-rule resolution; exhaustion signals
    `prolog-depth-limit-exceeded`) replaces the old step-budget, and `:limit`
    is a benign cap (no error on truncation) unlike the old hard result-limit
    error
  - `and`/`or`/`not`/`=` are ordinary `#:CL` symbols and dispatch to
    cl-prolog's builtins unqualified from any package; `call`/`findall`/`true`/`fail`
    have no `#:CL` equivalent and must be written `cl-prolog:call` etc. — an
    unqualified symbol of the same name is a different symbol and the engine
    reports the goal as an undefined procedure
  - a wrong-arity builtin call, an unbound goal passed to `call`/`findall`, and
    a totally undefined relation all signal catchable ISO conditions
    (`prolog-existence-error`, `prolog-instantiation-error`) instead of the
    retired engine's ad hoc "expects N arguments" errors
  - `and`/`or`/`not`/`call`/`findall`/`true`/`fail`/`=` are all native
    cl-prolog builtins, so `src/prolog-primitives.lisp`'s hand-written
    primitives have no replacement to write — they simply no longer exist
  - `t/prolog-db.lisp` is redesigned around cl-prolog's real (immutable by
    default) rulebase model: `extend-rulebase` leaves its base rulebase
    unchanged rather than the retired engine's mutable clause-db invariants
  - `contrib/prolog-bridge.lisp` and its `.asd` are deleted: its premise —
    bridging the retired compact engine to an external ISO Prolog via
    `cl-prolog2` for missing built-ins — no longer holds once the embedded
    engine already has findall/cut/arithmetic/DCG/assoc/format natively;
    `contrib/verify-contrib.lisp`, `contrib/README.md`, and the literate
    `contrib/literate/tty-relations.clw` module are updated accordingly
  - `README.md`, `docs/src/logic-engine.md`, `docs/src/api-reference.md`,
    `docs/src/installation.md`, `docs/src/contrib.md`, and the feature audits
    are updated to describe the engine as `nerima-lisp/cl-prolog` directly
  - full test suite, `scripts/verify.lisp`, `contrib/verify-contrib.lisp`, and
    the cl-weave mutation suite all pass against the migrated engine
- decompose `t/screen.lisp`'s ~370-line unnamed `test-screen` body into nine
  named functions grouped by what they verify (mutation-sequence state
  threading, initial-cell/write-string/cell copy-on-write, wide-glyph
  placement, render-diff style-order independence, cell/style normalization,
  bounds/dimension errors), so `test-screen` is now a flat, readable list of
  20 named calls instead of one undifferentiated block of assertions
- hoist `src/keys.lisp`'s `%modifier-prefix` modifier-label table out of the
  function body into a top-level `+modifier-prefixes+` parameter, separating
  the data from the traversal logic that reads it
- close real branch-coverage gaps found via SB-COVER: the `fail/0` primitive
  was entirely untested, and the failure paths of `not/1`, `=/2`, and
  `findall/3` plus the success path of `true/0` were never exercised in
  `src/prolog-primitives.lisp` (branch coverage 64.3% -> 92.9%); `move-cursor`
  gained a case exercising the un-clamped path (no `:width`/`:height`
  supplied). The remaining branch gaps in files like `renderer.lisp` and
  `input-state.lisp` are SB-COVER artifacts of `DEFSTRUCT` slot type
  declarations and `DEFPARAMETER` initforms, not real logic gaps -- both
  execute exactly once at load time and SB-COVER does not mark that as
  "entered" the way it does an `IF`/`WHEN` branch
- deduplicate near-identical logic found via `paredit inspect similarity`:
  `src/sgr-parse.lisp` and `src/text-layout.lisp` each hand-rolled a
  99%-identical string splitter (differing only in the delimiter character) --
  generalized into a single `%split-on-char` in `text-layout.lisp`;
  `src/box.lisp`'s `screen-draw-horizontal-line`/`screen-draw-vertical-line`
  now share a `%screen-draw-line` helper driven by a per-cell coordinate
  callback instead of duplicating the bounds-check/loop/put shape twice; a
  repo-wide `paredit inspect unused-definitions` sweep of `src/` and `t/`
  turned up no genuine dead code -- every flagged candidate was either public
  API (consumed outside the files being scanned) or an internal helper with a
  confirmed call site
- add the `%define-rect-split` macro (matching the existing
  `define-ansi-function` declarative-generation idiom) and rewrite
  `rect-split-horizontal`/`rect-split-vertical` on top of it, removing the
  duplicated clamp/offset arithmetic between the two axis-symmetric functions
- set `:author`/`:maintainer` to `nerima-lisp` across `cl-tty-kit.asd` and the
  `contrib/*.asd` systems, completing the org migration alongside the
  repository-URL change
- bump vendored `nerima-lisp/cl-prolog` from v0.7.0 to v0.8.0 (association
  maps, pairs, a SWI-compatible string type, `char_type`/`code_type`,
  `term_to_atom`, `sort/4`, `predsort/3`, `aggregate_all/3`, and a core
  unification/prover performance pass) and `nerima-lisp/cl-weave` from
  v0.10.0 to v0.11.0 (time-travel debugging, soft assertions, journal
  tooling, and a runner hot-path performance pass); the full test suite,
  `contrib/verify-contrib.lisp`, and the cl-weave mutation suite all pass
  unchanged against both upgrades
- add a full MkDocs (Material) documentation site under `docs/` — a landing
  page, Getting Started (installation, quick start, compatibility), an
  11-page subsystem guide (screen/rendering, layout, widgets, input, mouse,
  ANSI, color, text layout, terminal session, PTY, the embedded logic
  engine), a grouped API reference, a condition-hierarchy reference, an
  examples index, the feature audit, the contrib integrations, and the
  project's governance docs — published to GitHub Pages by a new
  `.github/workflows/docs.yml` on every push to `docs/**`

## 0.5.0 - 2026-07-24

- add `rect-right` and `rect-bottom` accessors returning a rectangle's exclusive
  right and bottom edges (`rect-x + rect-width` and `rect-y + rect-height`), and
  use them internally in `rect-contains-p`, `rect-intersection`, and
  `rect-union`
- split the largest source files along their internal seams into focused
  modules with no change to the public API: `ansi-control` (cursor/scroll/mode
  control) and `ansi-osc` (title/hyperlink) alongside the core `ansi` builders,
  `screen-regions` (copy/blit/scroll/crop) alongside `screen`, `pty-fd` (bare-fd
  octet I/O) alongside `pty`, and a dedicated `prolog-package` for the embedded
  logic engine's package
- introduce a shared `%assert` argument-validation macro in `conditions.lisp`
  and adopt it across the color, cursor, format, keys, mouse, box, screen-text,
  text-layout, and rect validators, removing dozens of duplicated
  `unless`/`error` bodies while preserving every error message and condition
- remove the unused `output-utils` helper and dead render-command string/length
  helpers that no longer had callers
- add a Prolog-based SGR oracle test that cross-checks `decode-sgr` against an
  independent model of the SGR color grammar, and property-based tests for
  `clamp`, hex-color round-tripping, the rect edge accessors, and pad/truncate
  width contracts; consolidate the per-file non-type-error test helper into a
  single shared macro
- add an opt-in `cl-tty-kit-weave-mutation-tests` contrib system that measures
  test effectiveness by mutation
- bump the vendored `cl-prolog` (v0.7.0) and `cl-weave` (v0.10.0) submodules
- migrate repository URLs from the `takeokunn` user to the `nerima-lisp`
  organization

## 0.4.0 - 2026-07-23

- add an fd-centric PTY layer for fd-multiplexing callers: `pty-fd` and `pty-pid`
  expose the master-side file descriptor and child pid, and `fd-read-octets` /
  `fd-write-octets` do byte-transparent octet I/O on a bare integer fd (no
  character decoding, exact bytes preserved). `fd-write-octets` loops over short
  writes on a blocking fd and stops at EAGAIN with a resumable short count on a
  non-blocking fd. These coexist with, and do not replace, the stream-based
  `pty-read` / `pty-write`
- widen raw mode to clear a strict superset of `cfmakeraw`'s input flags, also
  clearing `IGNBRK PARMRK ISTRIP INLCR IGNCR ECHONL` so the stream is
  byte-transparent enough for a multiplexer feeding it verbatim to a child PTY.
  This is a behavior change for existing `enable-raw-mode` consumers, so it lands
  as a minor version bump rather than a patch

## 0.3.0 - 2026-07-20

- harden terminal escape, input, color, mouse, PTY, and image parsing against
  malformed or adversarial data, including bounded numeric parsing, OSC/control
  sanitization, vector element validation, and bracketed-paste preflight limits
- make screen and layout operations fail atomically for invalid bounds, display
  widths, ratios, and source slices while preserving existing successful output
- improve render diff, sixel, kitty image, and text-layout hot paths by avoiding
  redundant string work, streaming output builders, and precomputing color state
- validate public cell and terminal FD boundaries explicitly, and stream render
  command output without per-command intermediate strings
- harden the embedded Prolog engine against malformed and adversarial programs:
  bound term nesting depth, detect circular terms and variable chains, add an
  occurs check, validate clause databases, goals, bindings, and primitive
  arities, and prove negation goals by existence instead of materializing every
  binding
- make coverage verification fail when SB-COVER produces an empty source report
  instead of silently accepting a non-instrumented run

## 0.2.0 - 2026-07-20

- greatly expand the ANSI helper set: cursor motion (`ansi-cursor-up`/`-down`/
  `-forward`/`-back`/`-column`), `ansi-save-cursor`/`ansi-restore-cursor`,
  `ansi-scroll-up`/`ansi-scroll-down`/`ansi-set-scroll-region`,
  `ansi-set-window-title`, `ansi-set-cursor-style`,
  `ansi-enable-mouse`/`ansi-disable-mouse`, a general `ansi-sgr` builder, and the
  remaining SGR text attributes (`ansi-dim`, `ansi-italic`, `ansi-underline`,
  `ansi-blink`, `ansi-reverse`, `ansi-hidden`, `ansi-strikethrough`)
- enrich the style model: recognize the `:blink`, `:hidden`, and `:strikethrough`
  modifiers, add `style-ansi` to emit an SGR string for text rendered outside the
  screen grid, and add `named-color` mapping the sixteen ANSI color names (plus
  `:gray`/`:grey`) to palette indices for use with `style-fg`/`style-bg`
- add a display-width-aware text layout module: `truncate-string` (with optional
  ellipsis), `pad-string` (`:left`/`:right`/`:center`), and `wrap-string`
  (greedy word wrap with hard-splitting of over-long words); all measure in
  terminal columns via `char-width`, so wide CJK glyphs are never split
- add screen operations: `screen-copy` (deep snapshot), `screen-blit` (clipped
  region compositing), `screen-row-string` (row inspection), `screen-scroll`
  (vertical scroll with fill), and `screen-fill` (whole-grid fill)
- add a box-drawing module: `screen-draw-box`, `screen-draw-horizontal-line`, and
  `screen-draw-vertical-line`, with `:single`, `:rounded`, `:double`, `:heavy`,
  and `:ascii` border styles
- add SGR (1006) mouse decoding: a `mouse-event` struct with button, action,
  0-based coordinates, and modifiers; a standalone `decode-mouse-sequence`; and
  integration into the CSI decode path so `decode-input`/`decode-input-chunk`
  surface mouse events inline with key events (including across chunk boundaries)
- add `examples/boxed-panel.lisp` and `examples/mouse-decoding.lisp` showcasing
  the new box, layout, color, and mouse APIs
- add a color-conversion module: `parse-hex-color` (`#rrggbb`/`#rgb`),
  `color-256-to-rgb` and `rgb-to-256` (xterm 256-palette round-tripping, with
  near-gray inputs mapping to the smoother grayscale ramp), and `blend-colors`
- add higher-level screen text placement: `screen-write-lines` (multi-line,
  clipped), `screen-write-wrapped` (wrap-and-place, returning the on-screen line
  count), and `screen-to-string` (plain-text snapshot of the grid)
- add textual widgets: `format-progress-bar` (sub-cell-accurate Unicode block bar)
  and `format-columns` (padded, aligned columns joined by a separator)
- add focus reporting: `ansi-enable-focus-reporting`/`ansi-disable-focus-reporting`
  plus `ESC[I`/`ESC[O` decoding into :FOCUS-IN/:FOCUS-OUT special key events
- add `key-event->string` for human-readable key labels (`C-a`, `S-Up`, `Enter`,
  `<paste N bytes>`)
- add `examples/progress-dashboard.lisp` showcasing box, progress bars, columns,
  and color together
- add a `rect` layout-geometry module: `make-rect` with accessors, `rect-inset`
  (carve a bordered box's interior), `rect-split-horizontal`/`rect-split-vertical`
  (with an optional gap), and `rect-contains-p`
- add `format-sparkline` (an eight-level Unicode block sparkline), `style-merge`
  (union modifiers, override colors win), and `cell-blank-p` (the emptiness test
  RENDER-DIFF uses, exposed)
- add `ansi-request-cursor-position` and a standalone `decode-cursor-position-report`
  returning 0-based (VALUES ROW COL CONSUMED); kept out of DECODE-INPUT because a
  bare `ESC[r;cR` is ambiguous with a modified F3 key
- add a double-buffered `renderer` (`make-renderer`, `renderer-screen`,
  `renderer-width`/`-height`, `renderer-render`, `renderer-clear`,
  `renderer-resize`) that wraps the draw-then-diff loop: draw into the back
  buffer, `renderer-render` emits only the changes and snapshots the frame (the
  first render, and any render after a resize, repaints in full)
- add `screen-write-aligned` for horizontally and vertically aligned text within
  a `rect` (label centering), `ansi-hyperlink` (OSC 8), and `color-gradient`
- add `examples/renderer-loop.lisp` showing a full paint followed by a diff-only
  update
- add `docs/FEATURE-AUDIT.md`, a systematic enumeration of the terminal-toolkit
  capability space (cross-referenced against notcurses/crossterm/tcell/rich)
  marking each item DONE/GAP/DEFERRED, and close every GAP it found:
  - rect geometry: `rect-empty-p`, `rect-area`, `rect-intersect` (clipping),
    `rect-union` (damage bounds)
  - ANSI: `ansi-bell`, `ansi-reset-terminal`, `ansi-begin-synchronized-update`/
    `ansi-end-synchronized-update` (tear-free repaints), `ansi-default-foreground`/
    `ansi-default-background`
  - `screen-draw-box` gains `:title`/`:title-align`/`:title-style`
  - widgets: `format-table` (auto-width multi-row) and `spinner-frame`
  - color: `rgb-to-ansi16` (16-color downsample) and `color-luminance` (Rec. 601)
  - `terminal-size` (ioctl TIOCGWINSZ on Linux/Darwin; NIL off a tty)
  Deferred items (PTY resize, grapheme clustering, flex/grid solver, DA decode,
  sixel, non-SBCL portability) are recorded with rationale in `ROADMAP.md`.
- extend `docs/FEATURE-AUDIT.md` with a second, research-backed enumeration pass
  that diffed the public API against the actual capability surfaces of crossterm/
  ratatui, notcurses, tcell/termbox2, and rich/prompt_toolkit/blessed, and close
  every additional gap it found:
  - style: `:double-underline`/`:curly-underline`/`:dotted-underline`/
    `:dashed-underline` (SGR 4:2..4:5), `:overline` (SGR 53), and
    `style-underline-color` (SGR 58)
  - color: `rgb-to-hsl`/`hsl-to-rgb`, `rgb-to-hsv`/`hsv-to-rgb`, `parse-color`
    (hex/`rgb()`/name), and `contrast-color`
  - ANSI/OSC: `ansi-set-clipboard` (OSC 52), `ansi-set-palette-color` (OSC 4)/
    `ansi-reset-palette` (OSC 104), `ansi-request-foreground-color`/
    `ansi-request-background-color` (OSC 10/11) with `decode-color-report`,
    `ansi-enable-line-wrap`/`ansi-disable-line-wrap`, and
    `ansi-cursor-next-line`/`ansi-cursor-previous-line`
  - text: `*east-asian-ambiguous-wide*` width policy, `expand-tabs`,
    `chop-string`, and `strip-ansi`
  - screen: `screen-crop`; input: `:wheel-left`/`:wheel-right` mouse decoding
- close the feasible items previously deferred in `docs/FEATURE-AUDIT.md`:
  - `key-event-kind` (:PRESS/:REPEAT/:RELEASE) decoded from the kitty CSI-u
    `MODIFIER:EVENT` sub-parameter, plus legacy CSI-tilde F13-F20 keys
  - `decode-sgr` (SGR escape → normalized style, inverse of `style-ansi`) and
    `parse-styled-string` (styled string → (text . style) segments)
  - `ansi-request-device-attributes` (DA1) and `decode-device-attributes`
  - `pty-resize` (ioctl TIOCSWINSZ); this also fixed a latent `terminal-size`
    bug where a hand-declared variadic `ioctl` alien routine failed with EFAULT
    on the arm64 ABI (silently returning NIL) -- both now use
    `sb-unix:unix-ioctl`, so `terminal-size` actually reports the size
- re-examine two more audit deferrals and implement them:
  - grapheme clusters via the in-image `sb-unicode:graphemes` (no shipped
    tables): `string-graphemes`, `grapheme-count`, `grapheme-width` (empty-string
    edge guarded)
  - `layout-split`, a ratatui-style constraint layout dividing a rect by
    `(:length N)`/`(:percentage P)`/`(:ratio A B)`/`(:min N)`/`(:fill WEIGHT)`
    constraints with spacing, sharing leftover space by weight
- close the last feasible audit deferrals:
  - kitty associated text: `key-event-text` (decoded from the CSI-u field-3 code
    points; the shifted-key subfield of field 1 is skipped to the primary key)
  - CSI in-place editing escapes: `ansi-insert-line`/`ansi-delete-line` (IL/DL),
    `ansi-insert-char`/`ansi-delete-char`/`ansi-erase-char` (ICH/DCH/ECH),
    `ansi-cursor-row` (VPA), `ansi-repeat` (REP)
  - `format-sixel`: encode a raw RGB pixel buffer into a sixel DCS string
    (xterm-256 quantization, 6-row bands, run-length compression)
  - kitty shifted / base-layout key alternates: `key-event-shifted-key` and
    `key-event-base-key` (decoded from the CSI-u first field's sub-fields),
    completing the kitty input surface
  - generic `ansi-set-mode`/`ansi-reset-mode` (DECSET/DECRST/SM/RM by number, the
    base primitive the specific ANSI-ENABLE-* toggles specialize -- covers the
    long tail of private modes) and `ansi-reset-scroll-region`
  - `pty-alive-p`, so a read loop can tell "no data yet" from "the child exited",
    and `pty-exit-code` for the child's status -- completing the PTY lifecycle
    (`make-pty` -> `pty-alive-p` -> `pty-exit-code` -> `close-pty`)
- add `examples/color-report.lisp` demonstrating the color subsystem
  (`color-gradient`, `rgb-to-256`, `named-color`, `color-luminance`) and
  `format-table` together, which previously had no runnable example
- add `examples/layout-dashboard.lisp` demonstrating `layout-split` constraint
  layout (a header/sidebar/main/footer dashboard) with `rect-inset` and
  `screen-write-aligned`
- add `examples/text-panel.lisp` demonstrating display-width text layout:
  `screen-write-wrapped` word-wrap and `truncate-string` with an ellipsis
- add `examples/hsl-rainbow.lisp` demonstrating `hsl-to-rgb` by sweeping the hue
  circle into a colored panel
- add `examples/styled-parse.lisp` demonstrating reverse ANSI parsing:
  `parse-styled-string` recovers (text . style) segments from a styled string
- add `examples/graphemes.lisp` demonstrating grapheme-cluster segmentation:
  `string-graphemes` and `grapheme-width` on a mix of combining marks and CJK
- add `examples/sixel-image.lisp` demonstrating `format-sixel` on a small
  red-to-blue gradient; with this every major subsystem has a runnable example

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
