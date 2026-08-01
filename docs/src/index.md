# cl-tty-kit

`cl-tty-kit` is a small, low-dependency Common Lisp toolkit for terminal and
TTY work. The goal is a tight, reusable core for building terminal
applications — raw mode, ANSI escape helpers, key/mouse decoding,
Unicode-aware text layout, a pure screen/diff renderer, and PTY support —
without turning into a UI framework or a shell.

!!! tip "New to cl-tty-kit?"

    Put the repository somewhere ASDF can see it, load the bootstrap, and
    render your first screen in a few lines:

    ```lisp
    (load "scripts/bootstrap.lisp")
    (cl-tty-kit/bootstrap:load-core-system)
    (use-package :cl-tty-kit)

    (let ((screen (make-screen 20 4)))
      (screen-write-string screen 0 0 "Hi")
      (format t "~A~%" (render-screen screen)))
    ```

    Continue with [Getting Started](getting-started.md) →
    [Compatibility](reference/compatibility.md).

## Explore the docs

<div class="grid cards" markdown>

-   :material-rocket-launch:{ .lg .middle } &nbsp; **Getting Started**

    ---

    How to add `cl-tty-kit` to an ASDF project, your first rendered screen,
    and the SBCL-only compatibility contract.

    [:octicons-arrow-right-24: Getting Started](getting-started.md) ·
    [Compatibility](reference/compatibility.md)

-   :material-monitor-dashboard:{ .lg .middle } &nbsp; **Screens and Layout**

    ---

    The pure `screen`/`cell` grid, box drawing, diff rendering, the
    double-buffered renderer, `rect` geometry, and text/progress/table
    widgets.

    [:octicons-arrow-right-24: Screen and Rendering](guide/screen-and-rendering.md) ·
    [Layout](guide/layout.md) ·
    [Widgets](guide/widgets.md)

-   :material-keyboard-outline:{ .lg .middle } &nbsp; **Input and ANSI**

    ---

    Streaming key/mouse decoding, kitty keyboard protocol support,
    bracketed paste, and the full ANSI escape-sequence helper surface.

    [:octicons-arrow-right-24: Input Decoding](guide/input-decoding.md) ·
    [Mouse Input](guide/mouse-input.md) ·
    [ANSI Helpers](guide/ansi-helpers.md)

-   :material-palette-outline:{ .lg .middle } &nbsp; **Color and Text**

    ---

    Color space conversions and gradients, plus display-width-aware text
    layout for terminals where a cell is a column, not a character.

    [:octicons-arrow-right-24: Color](guide/color.md) ·
    [Text Layout](guide/text-layout.md)

-   :material-console:{ .lg .middle } &nbsp; **Sessions, PTY, and Logic**

    ---

    Raw mode and terminal-session lifecycle, a minimal PTY abstraction for
    SBCL, and the embedded Prolog-style logic engine behind the toolkit's
    classification rules.

    [:octicons-arrow-right-24: Terminal Session](guide/terminal-session.md) ·
    [PTY](guide/pty.md) ·
    [Logic Engine](guide/logic-engine.md)

-   :material-book-open-variant:{ .lg .middle } &nbsp; **Reference**

    ---

    A scannable API index grouped by subsystem, the condition hierarchy,
    every runnable example, and the feature-coverage audit against
    established terminal libraries.

    [:octicons-arrow-right-24: API Reference](reference/api.md) ·
    [Conditions](reference/conditions.md) ·
    [Examples](guide/examples.md) ·
    [feature audit note](https://github.com/nerima-lisp/cl-tty-kit/blob/main/docs/notes/feature-audit.md)

</div>

## Status

- **stable**: the public API is covered by the semantic-versioning guarantee below
- requires SBCL (see [Compatibility](reference/compatibility.md)) and is intentionally small
- test-backed public API, with runnable examples in `examples/`
- PTY support is limited to SBCL
- maintainer-grade local quality gates are documented in [Quality Gates](project/quality-gates.md)
- build, test and coverage commands live in [Development](project/development.md); the
  internal split is described in [Architecture](reference/architecture.md)
- contribution, conduct and security policy are org-wide and live in
  [nerima-lisp/.github](https://github.com/nerima-lisp/.github)

### API stability

From 1.0.0 onward `cl-tty-kit` follows [semantic versioning](https://semver.org).
The stable surface is precisely the symbols exported from the `cl-tty-kit`
package — every one is listed in the [API Reference](reference/api.md) and
asserted against the live package by `t/package-introspection-test.lisp`, so that
list cannot silently drift from the code.

Within the 1.x series exported symbols will not be removed or renamed and
existing arguments will not change meaning; new functionality arrives as added
symbols or added `&key` arguments. The shape of decoded input events and the
condition hierarchy rooted at `tty-kit-error` (see [Conditions](reference/conditions.md))
are part of that contract. Not covered: `%`-prefixed internals, the opt-in
integrations under [Contrib](guide/contrib.md), and the repository's own build and CI
plumbing. See [Release Process](project/release-process.md) for what would require a
2.0.

## Non-goals

`cl-tty-kit` stops deliberately short of an application framework:

- no shell implementation
- no full terminal emulator
- no widget toolkit
- no opinionated application framework

See [Roadmap](project/roadmap.md) for what is intentionally deferred, and why.

## License

MIT
