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

    Continue with [Installation](installation.md) → [Quick Start](quick-start.md)
    → [Compatibility](compatibility.md).

## Explore the docs

<div class="grid cards" markdown>

-   :material-rocket-launch:{ .lg .middle } &nbsp; **Getting Started**

    ---

    How to add `cl-tty-kit` to an ASDF project, your first rendered screen,
    and the SBCL-only compatibility contract.

    [:octicons-arrow-right-24: Installation](installation.md) ·
    [Quick Start](quick-start.md) ·
    [Compatibility](compatibility.md)

-   :material-monitor-dashboard:{ .lg .middle } &nbsp; **Screens and Layout**

    ---

    The pure `screen`/`cell` grid, box drawing, diff rendering, the
    double-buffered renderer, `rect` geometry, and text/progress/table
    widgets.

    [:octicons-arrow-right-24: Screen and Rendering](screen-and-rendering.md) ·
    [Layout](layout.md) ·
    [Widgets](widgets.md)

-   :material-keyboard-outline:{ .lg .middle } &nbsp; **Input and ANSI**

    ---

    Streaming key/mouse decoding, kitty keyboard protocol support,
    bracketed paste, and the full ANSI escape-sequence helper surface.

    [:octicons-arrow-right-24: Input Decoding](input-decoding.md) ·
    [Mouse Input](mouse-input.md) ·
    [ANSI Helpers](ansi-helpers.md)

-   :material-palette-outline:{ .lg .middle } &nbsp; **Color and Text**

    ---

    Color space conversions and gradients, plus display-width-aware text
    layout for terminals where a cell is a column, not a character.

    [:octicons-arrow-right-24: Color](color.md) ·
    [Text Layout](text-layout.md)

-   :material-console:{ .lg .middle } &nbsp; **Sessions, PTY, and Logic**

    ---

    Raw mode and terminal-session lifecycle, a minimal PTY abstraction for
    SBCL, and the embedded Prolog-style logic engine behind the toolkit's
    classification rules.

    [:octicons-arrow-right-24: Terminal Session](terminal-session.md) ·
    [PTY](pty.md) ·
    [Logic Engine](logic-engine.md)

-   :material-book-open-variant:{ .lg .middle } &nbsp; **Reference**

    ---

    A scannable API index grouped by subsystem, the condition hierarchy,
    every runnable example, and the feature-coverage audit against
    established terminal libraries.

    [:octicons-arrow-right-24: API Reference](api-reference.md) ·
    [Conditions](conditions.md) ·
    [Examples](examples.md) ·
    [Feature Audit](feature-audit.md)

</div>

## Status

- requires SBCL (see [Compatibility](compatibility.md)) and is intentionally small
- test-backed public API, with runnable examples in `examples/`
- PTY support is limited to SBCL
- maintainer-grade local quality gates are documented in [Quality Gates](quality-gates.md)
- project governance lives in [Contributing](contributing.md), `CODE_OF_CONDUCT.md`, and `SECURITY.md`

## Non-goals

`cl-tty-kit` stops deliberately short of an application framework:

- no shell implementation
- no full terminal emulator
- no widget toolkit
- no opinionated application framework

See [Roadmap](roadmap.md) for what is intentionally deferred, and why.

## License

MIT
