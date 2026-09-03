# Make `ago-calendar-console`'s UX gate blocking

- **Stage**: 15
- **Status**: done — 2026-09-03, `ago-calendar-console#35`
- **Split from**: `15-11`, whose Done-when asked for the three assertions to **fail the build** in all
  three frontend repositories. They do in `ago-console` and `ago-widget`. In `ago-calendar-console` the
  CI step is `continue-on-error: true`, and `15-11` was rewritten to *"in two of the three, which is
  this item's scope as landed"* rather than shipped with a half-ticked box.
- **Raised as an item**: 2026-09-02. It had been tracked only as `ago-calendar-console#26`, which kept
  `15-11`'s number in its title — so the work claimed to belong to an item that was already done, and
  had no `ago-root` twin at all. Found by the mirror-aware `tools/queue-audit.sh` (`#329`) on its first
  real run, which is the whole reason that check exists.

## Why it is not blocking today

The gate's first run in this repository found real, **pre-existing** defects — `ago-calendar-console#22`
(all eight screens overflow horizontally at 375px) and `#23` (some controls are 20–22px against WCAG
2.2 §2.5.8's 24px minimum). Neither was introduced by the gate; it is the first thing that ever looked.

Making the step blocking with those open would redden **every** pull request in the repository for a
defect it did not introduce. That is how people learn to ignore a red build, which is the opposite of
what a gate is for — and unwinding that habit is more expensive than the defects themselves.

## Why this is an item and not a comment in CI

A step that always warns is its own hazard: it becomes wallpaper, and the warning stops being read.
The compromise was recorded in the CI step's own comment, but **a note is not a date.** This item is
the date.

It also has a second consumer now: `11-16` (the gate asserting nothing is left untranslated) names
this as a **prerequisite** rather than a neighbour, because a failing assertion in a gate whose exit
code nothing reads changes nothing. So this is not tidy-up — it is what makes one of the launch-path
quality checks mean anything in this repository.

## Scope

- Fix or explicitly quarantine `#22` and `#23`.
- Delete `continue-on-error: true` from the `Rendered UX gate` step in `.github/workflows/ci.yml`.
- Prove the result green on `main` **by a run**, not by reasoning about it.

## Out of scope

- The translation assertion — that is `11-16`, and it depends on this rather than the other way round.
- The other two repositories' gates. They are already blocking and this item does not touch them.

## Done when

- [x] `ago-calendar-console#22` and `#23` are closed — fixed, or quarantined by a named, auditable
      exemption rather than by loosening the assertion for everything.
- [x] `continue-on-error: true` is gone from the `Rendered UX gate` step.
- [x] A run on `main` is green with the flag gone, linked from the issue.
- [x] The gate is proven to still **fail** when it should: the repository's own `fails-before.spec.ts`
      still bites, so "green" means "no violations", not "no longer checking".

## Open question

- **Is fixing `#22` cheap, or does it want `11-14` first?** All eight screens overflowing at 375px is
  a layout problem, and `11-14`'s drawer changes the navigation that overflows on every one of them.
  Doing this first may mean doing part of it twice. Worth ten minutes of looking before starting.
