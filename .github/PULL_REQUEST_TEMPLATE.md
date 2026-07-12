# Summary

<!-- What does this change do, and why? -->

# Contract impact

<!-- Note any change to exported symbols, rendered ANSI output, or input event
     shape. These are contract changes and must update README.md + CHANGELOG.md. -->

- [ ] No public contract change
- [ ] Public contract change (README.md and CHANGELOG.md updated)

# Verification

Run from the project root:

```bash
sbcl --script scripts/verify.lisp
git diff --check
```

- [ ] `scripts/verify.lisp` passes
- [ ] `git diff --check` is clean
- [ ] New public behavior has regression tests
- [ ] Docs (`README.md`, `CHANGELOG.md`) updated where the contract changed
