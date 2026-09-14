# 25-87 · The console brands itself "AGO Chat" again

- **Stage**: 25
- **Status**: done — independently re-verified by the managing session before merging: `npm run
  typecheck`/`lint` clean, full `npx vitest run` — 1404/1404, matching the worker's own count
  exactly; a fresh `grep -rn "AGO Офис" src/` finds only historical mentions inside the comments
  explaining the reversal, no remaining literal.
- **Depends on**: nothing
- **Decision**: the author's own, 2026-09-14, made knowing it reverses `25-49`'s own reasoning - see
  below.
- **Found**: 2026-09-14, the author's own live walkthrough - the workspace header reads "AGO Офис",
  which read as a step backward from the product's own name.

## What is actually true, and the tension this item knowingly resolves

`AppShell.tsx`'s workspace header currently renders a hardcoded, unlocalized literal - not read from
`strings` at all, in either locale - `"AGO Офис"` (two places: the header itself and a second
matching block, both carrying the identical `23-31`/`25-49` reasoning in their own comments). `25-49`
grew this from a bare "Офис" specifically because, at the time, the console had started serving both
AGO Chat and AGO Calendar tenants, and a single shared console branded "AGO Chat" would misname itself
for a calendar-only tenant.

**The author's own call, made explicitly aware of that reasoning**: AGO Chat is the platform's real
product name. AGO Calendar is a module sold on top of it, not a second product with an equal claim on
the console's own name. The header reverts to "AGO Chat" - both locales, identical text (a brand name
is not translated, the same "never translate AGO" rule the removed comment itself already states for
the glyph beside it).

## Scope

- Both hardcoded `"AGO Офис"` literals (`AppShell.tsx`) become `"AGO Chat"`.
- Read `OperatorShell.tsx`'s own remarks (referenced from the same rename) for anywhere else this
  reasoning was threaded through, and update those too - this item reverts the decision everywhere
  `25-49` applied it, not only the one span the author happened to see.
- Leave `23-31`'s own separate decision (deleting the muted-navigation lock glyph, `adr/0129`) alone -
  unrelated, do not touch it while in this file.

## Where this is likely to go wrong

- **Say so in the code, not just in this item.** Whatever replaces the current comment should name
  this item and state plainly that it reverses `25-49`'s own reasoning on purpose, the same way this
  codebase already handles a superseded decision elsewhere (an ADR's own "Supersedes" line, when one
  exists) - a future reader who finds `25-49`'s own comment should not have to guess whether this was
  an accident.
- **Not an ADR-level reversal** (`25-49` was never its own ADR - checked, `docs/adr/README.md` has no
  entry naming it) - this item's own backlog file and the code comment are where the reasoning belongs,
  not a new ADR invented to hold it.

## Done when

- [x] The workspace header reads "AGO Chat" in both locales, everywhere `25-49`'s own rename touched.
      Both `AppShell.tsx` brand blocks (`AppShell`'s own workspace header and `CenteredShell`'s
      matching block) render the literal `AGO Chat` now. Proven, not asserted: both
      `consoleLocale.test.tsx` assertions pinned to the old wordmark - the Ru-locale test that
      exists specifically to show the brand text does not vary by locale, and the no-Locale-set
      default-to-Russian test - were inverted against the un-reverted code first (both failed,
      `expected 'AGO Офис' to be 'AGO Chat'`), then restored and re-run green. `OperatorShell.tsx`'s
      own remarks (the file `25-49`'s rename is also referenced from) and `shell.css`'s wordmark
      comment were the two other threaded-through spots the item asked to check for - both updated
      too, though neither renders a literal itself. Full suite: 135 test files / 1404 tests passed;
      `npx tsc -b --noEmit` and `npx eslint src ux-gate` both clean; `npm run build` succeeded.
- [x] The code says, plainly, that this reverses `25-49` and why - a future reader finds the reasoning
      without needing this item file.
      All four updated comments (`AppShell.tsx` twice, `OperatorShell.tsx`, `shell.css`) now name
      `25-87` explicitly and state the reversal is on purpose, alongside the `25-49` reasoning they
      replace - the same pattern this item asked for, an ADR's own "Supersedes" line, without
      inventing an ADR (`25-49` was never one).
