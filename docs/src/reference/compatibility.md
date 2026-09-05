# Compatibility

`cl-tty-kit` currently **requires SBCL**. This is a deliberate scope
decision, not an oversight — see the rationale below.

## Why SBCL-only

The toolkit relies on SBCL-only facilities for the parts of the job a
portable Lisp standard doesn't cover:

- `sb-posix` for terminal control (raw mode)
- `sb-unicode` for character-width classification
- `sb-ext` for UTF-8 transcoding and process/PTY handling

Loading the system on another Common Lisp implementation fails fast with a
clear "requires SBCL" error, rather than a confusing missing-dependency
report partway through a load. `sb-posix` is an SBCL-bundled contrib loaded
directly with `require` by the SBCL-only raw-mode implementation; it is not
an ASDF dependency. This avoids scanning caller source registries merely to
locate an already installed library.

## Portability by concern, not by promise

Internally, the code is still organized by the portability of *concern*, even
though only one implementation is supported today. That separation keeps the
OS-facing surface small and isolated, and keeps the pure logic easy to test
in isolation:

| Layer | Examples | Notes |
|---|---|---|
| Pure logic (no OS calls) | ANSI helpers, key/input decoding, character width, screen and cursor state, rendering, the embedded logic engine | Portable Common Lisp; the majority of the codebase |
| OS-facing, SBCL-specific | raw-mode control, the terminal-session helper, PTY support | Isolated behind `#+sbcl` and the `unsupported-feature` contract below |

Broader multi-implementation support is a possible future direction — see
[Roadmap](../project/roadmap.md) — but is explicitly deferred today: it would require
shipping the Unicode tables the library currently borrows from `sb-unicode`,
which runs against the project's small scope. Today the
supported and tested target is SBCL, on both Linux and macOS (the CI matrix
runs both).

## The `unsupported-feature` contract

Within a supported (SBCL) build, when an OS-facing runtime feature cannot be
provided — for example, a platform lacking a particular ioctl — the library
signals [`unsupported-feature`](conditions.md#unsupported-feature) instead of
silently degrading or returning a sentinel value. This is a repository-wide
policy, not a per-function judgment call: see
[Quality Gates](../project/quality-gates.md) for the full non-functional requirements
this contract is part of.

!!! note "Why fail loudly instead of degrading"

    A terminal app that silently loses mouse tracking, or silently falls
    back to a wrong screen size, is much harder to debug than one that
    raises a condition naming exactly what wasn't available. `cl-tty-kit`
    treats "unsupported here" as a fact the caller should be able to
    branch on, not an implementation detail to paper over.

## What this means for your project

- If your deployment target is SBCL on Linux or macOS, `cl-tty-kit` works as
  documented across the whole public API.
- If you need another implementation (CCL, ECL, ABCL, ...), `cl-tty-kit` is
  not yet a fit — loading it will fail with an explicit error rather than a
  partially-working build.
- If you only need the pure logic (rendering, layout, color conversions, the
  logic engine) without any OS-facing terminal control, that code is already
  written portably; it isn't packaged for or tested against other
  implementations today.

See also [Roadmap](../project/roadmap.md) for the project's explicit list of what stays
out of scope on purpose, and [PTY](../guide/pty.md) for the SBCL-specific process and
file-descriptor layer.
