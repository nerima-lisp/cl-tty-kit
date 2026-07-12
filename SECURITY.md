# Security Policy

`cl-tty-kit` is a small terminal toolkit, but input decoding, PTY handling, and
raw-mode integration still deserve careful reporting.

## Supported scope

- the current `main` branch
- the latest tagged release, when available

## Reporting a vulnerability

Do not file a public issue for security-sensitive findings.
Instead, contact the maintainer privately and include:

- the affected file or subsystem
- the exact input or runtime condition that triggers the problem
- the observed behavior
- the expected behavior
- any proof-of-concept or reproduction steps

## What to include

Useful reports usually name one of these areas:

- raw mode transitions
- PTY lifecycle handling
- UTF-8 or terminal input decoding
- screen buffer bounds or rendering correctness

## Response expectations

Security reports should be reproducible and specific. If more information is
needed, the maintainer may ask for a smaller reproduction before confirming a
fix.
