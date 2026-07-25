# Release Process

`cl-tty-kit` follows a conservative release process. Releases should
preserve the small public API, keep terminal-specific behavior isolated, and
avoid surprising changes in the output format of helpers and renderers.

## Versioning

The project uses semantic versioning:

- patch releases for bug fixes and documentation updates
- minor releases for additive API changes
- major releases for breaking API, event-shape, or output changes

### What the version guarantees

From 1.0.0 onward, the *stable surface* is exactly the set of symbols exported
from the `cl-tty-kit` package. That set is listed in the
[API Reference](api-reference.md) and asserted against the live package by
`t/package-introspection.lisp`, so the documented list and the code cannot
drift apart silently. Alongside the symbol names themselves, the contract
covers the shape of decoded input events (a `key-event`'s type, code, and
modifiers — see [Input Decoding](input-decoding.md)) and the condition
hierarchy rooted at `tty-kit-error` (see [Conditions](conditions.md)).

Outside the stable surface, and freely changeable in a minor or patch release:
`%`-prefixed internals, the opt-in integrations under [Contrib](contrib.md),
this repository's build and CI plumbing (including `flake.nix`'s inputs and
outputs), and the exact byte sequence `render-diff` emits — that one is bounded
only by the property `t/properties.lisp` asserts, namely that its visible
result matches `render-screen` and it is never longer than a full repaint.

### What requires a 2.0

Removing or renaming an exported symbol, changing what an existing argument
means, changing the shape of a decoded input event, or changing an escape
sequence in a way that alters correct rendered output. If a change improves the
core design but does any of these, treat it as a deliberate major-release event
and update the public contract aggressively instead of carrying a compatibility
layer — [Quality Gates](quality-gates.md) rejects compatibility shims by
policy.

## Release checklist

Before tagging a release:

1. Read [Quality Gates](quality-gates.md) and confirm the patch still
   satisfies the repository-local release gate.

2. Run the full verification script from the project root:

   ```bash
   nix run .#verify
   ```

   This includes the repository-local tests, example smoke checks, and the
   fresh source-registry packaging smoke.

3. Run the diff hygiene check:

   ```bash
   git diff --check
   ```

4. Review `CHANGELOG.md`: promote the `[Unreleased]` section to a dated
   version heading in the Keep a Changelog form `## [0.5.0] - 2026-07-24`,
   and leave a fresh empty `## [Unreleased]` section on top for the next
   cycle. The bracketed form is not cosmetic — `release.yml` extracts the
   section matching the pushed tag as the GitHub Release body, and fails the
   release outright if no section matches.
5. Bump `:version` in `cl-tty-kit.asd` to match the release being cut.
6. Confirm that the [API Reference](api-reference.md) still matches the
   exported symbols and that [Examples](examples.md) still lists every file
   under `examples/` — `t/package-readme.lisp` checks both mechanically, but
   review them by hand too.
7. Smoke-test the examples on a clean SBCL environment if possible.
8. If `flake.lock` moved (the `cl-prolog`/`cl-weave`/`paredit-cli`/`nixpkgs`
   inputs), confirm `nix flake check --all-systems` still passes against the
   new pins before tagging — see [Contrib](contrib.md). `--all-systems` is not
   optional here: without it Nix only evaluates outputs for the machine you are
   on, so a `nixpkgs` bump that drops a platform `flake.nix` still advertises
   passes silently.

## Cutting the tag

Once the checklist passes and the release commit is merged to `main`:

```bash
git tag -a v0.5.0 -m "cl-tty-kit 0.5.0"
git push origin v0.5.0
```

Pushing the tag is the whole release. `.github/workflows/release.yml` takes
over from there: it refuses to proceed if the tag disagrees with
`cl-tty-kit.asd`'s `:version`, re-runs `nix flake check --all-systems`
against the tagged tree, extracts the matching `CHANGELOG.md` section, and
publishes the GitHub Release with that section as the body. Creating the
release by hand is no longer part of the process.

## Release notes

Release notes should call out:

- public API additions and removals
- changes to terminal rendering or key decoding behavior
- SBCL compatibility changes
- bug fixes that affect screen diffing, raw mode, or PTY behavior

## Contract updates

When a public contract changes, update the [API Reference](api-reference.md),
`CHANGELOG.md`, and the test suite in the same patch so the new surface is
explicit and executable.

## Publishing documentation

This documentation site is rebuilt and deployed to GitHub Pages by
`.github/workflows/docs.yml` whenever `docs/**`, `flake.nix`, or `flake.lock`
changes on `main` (or on manual dispatch). The workflow builds the hermetic
`nix build .#docs` package (`--strict`, so a broken internal link or an
unlisted nav page fails the build instead of publishing a silent gap) and
publishes the result through `actions/deploy-pages`. A documentation change
does not require a version bump or a tag — it publishes independently of the
release checklist above.
