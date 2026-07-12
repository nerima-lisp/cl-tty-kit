# Changelog

## Unreleased

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
