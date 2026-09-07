# the rollback guard's own pattern cannot see the two demo shops

- **Stage**: 15
- **Status**: ready
- **Found**: 2026-09-07, while building `15-21`'s drift check, which hit the identical bug in its own
  first draft and fixed it there.
- **Decision**: none needed. This is a character class that is one class short.

## What is actually wrong

`apply-demo.sh` refuses an apply that would move a running workload back to a tag nothing is running —
the guard `22-24` added, and it works. It builds the manifest side of that comparison with:

```
grep -oE "image: ghcr\.io/golyakoff/[a-z-]+:[0-9a-f]{40}"
```

`[a-z-]+` **excludes digits**. Two repositories in this overlay carry one: `ago-demo-shop1` and
`ago-demo-shop2`. So neither ever enters `manifest_imgs`.

The running side has no such restriction — it matches `^ghcr\.io/golyakoff/` and picks both up. The
comparison is `comm -23 manifest running`, so an image missing from the manifest side simply never
appears in the "would introduce" set.

**The two demo shops are therefore unprotected by that guard today**, and have been since it was
written. Nothing fails; the guard just quietly covers five deployments instead of seven.

## Why it is worth a number rather than a one-character fix in passing

The fix is one character. What makes it worth recording is that the same pattern was written twice,
independently, and was wrong both times — `15-21`'s new `check-manifest-drift.sh` had `[a-z-]+` in its
first draft against the same two repositories, and caught it only because its own test used them. A
mistake that reproduces itself is a shape worth naming, not a typo.

## Scope

- Widen the class in `apply-demo.sh` to `[a-z0-9-]+`.
- Show the guard refusing on a demo-shop rollback, which it cannot do today. A test that only shows it
  refusing on `ago-chat-api` proves nothing that was not already true.

## Done when

- [ ] `apply-demo.sh`'s manifest-side pattern matches every repository name this overlay actually uses.
- [ ] The guard is shown refusing a rollback of `ago-demo-shop1` or `ago-demo-shop2` specifically.

## Out of scope

- `check-manifest-drift.sh`, which already has the widened class.
