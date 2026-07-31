# Summary

<!-- What does this change do, and why? -->

# Contract impact

<!-- Note any change to exported symbols, rendered ANSI output, or input event
     shape. These are contract changes and must update README.md and the docs.
     There is no CHANGELOG.md: release history lives in the GitHub Release
     description, written when the release is cut. -->

- [ ] No public contract change
- [ ] Public contract change (README.md and docs updated)

# Verification

Run from the project root:

```bash
nix run .#verify
git diff --check
```

- [ ] `scripts/verify.lisp` passes
- [ ] `git diff --check` is clean
- [ ] New public behavior has regression tests
- [ ] Docs (`README.md`, `docs/src/`) updated where the contract changed
