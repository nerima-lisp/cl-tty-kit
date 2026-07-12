# Roadmap

`cl-tty-kit` is intentionally scoped to terminal primitives. This file records
what is intentionally deferred so the repository stays honest about its
boundaries.

## Deferred on purpose

- full terminal emulation
- window manager or multiplexer behavior
- editor UI
- shell application logic
- CLI framework behavior
- event bus or general application runtime
- broad utility helpers unrelated to TTY work

## Possible future improvements

- broader PTY coverage beyond SBCL
- richer diff rendering strategies for large screens
- additional key-sequence coverage if practical and well-tested
- more examples for embedding the library in real terminal tools

## Principle

Every new feature should stay small, testable, and aligned with terminal
primitives rather than application framework behavior.

