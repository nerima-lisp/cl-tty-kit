# Releasing

`cl-tty-kit` follows a conservative release process. Releases should preserve
the small public API, keep terminal-specific behavior isolated, and avoid
surprising changes in the output format of helpers and renderers.

## Versioning

The project uses semantic versioning:

- patch releases for bug fixes and documentation updates
- minor releases for additive API changes
- major releases for breaking API, event-shape, or output changes

If a change improves the core design but changes rendered terminal output, input
decoding, or public symbol availability, treat it as a deliberate major-release
event and update the public contract aggressively instead of carrying a
compatibility layer.

## Release checklist

Before tagging a release:

1. Read `docs/QUALITY-GATES.md` and confirm the patch still satisfies the
   repository-local release gate.

2. Run the full verification script from the project root:

   ```bash
   sbcl --script scripts/verify.lisp
   ```

   This includes the repository-local tests, example smoke checks, and the
   fresh source-registry packaging smoke.

3. Run the diff hygiene check:

   ```bash
   git diff --check
   ```

4. Review `CHANGELOG.md`: promote the `Unreleased` section to a dated version
   heading (for example `## 0.1.0 - 2026-07-20`) and leave a fresh empty
   `## Unreleased` section on top for the next cycle.
5. Bump `:version` in `cl-tty-kit.asd` to match the release being cut.
6. Confirm that `README.md` still matches the public API and current examples.
7. Smoke-test the examples on a clean SBCL environment if possible.
8. If contrib/vendor submodules changed, confirm they are pinned to the intended
   upstream commits (`git submodule status`) before tagging.

## Cutting the tag

Once the checklist passes and the release commit is merged to `main`:

```bash
git tag -a v0.1.0 -m "cl-tty-kit 0.1.0"
git push origin v0.1.0
```

Then create the corresponding GitHub release from that tag, using the matching
`CHANGELOG.md` section as the release notes.

## Release notes

Release notes should call out:

- public API additions and removals
- changes to terminal rendering or key decoding behavior
- SBCL compatibility changes
- bug fixes that affect screen diffing, raw mode, or PTY behavior

## Contract updates

When a public contract changes, update `README.md`, `CHANGELOG.md`, and the
test suite in the same patch so the new surface is explicit and executable.
