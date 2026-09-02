# The calendar console gets a language

- **Stage**: 11
- **Status**: done — 2026-09-02, `ago-calendar-console#34`
- **Raised by**: the author, 2026-09-02 — *"в аудит по фронту надо добавить ещё что всё переводится
  на русский (кроме страниц доступных ТОЛЬКО platform owner)"*.
- **Builds on**: `11-11`…`11-13` (the string mechanism `ago-console` already has), `15-11` (whose
  screenshots exposed the defect)
- **Split from**: this item was raised as *"the gate checks that everything is translated, and the
  calendar console gets a language at all"*. Only the second half was delivered; the check itself is
  `11-16`. See **What was split off, and why** below.

## The problem this fixed

`ago-calendar-console` had **no localisation at all** — no `i18n` directory, zero references to a
string table, every label written inline in English: `Workers`, `Slots`, `View slots`, *"What this
worker's schedule actually produced"*.

`15-11`'s screenshots showed what that produced: **`Иванова А. П.'s slots`** — a Russian name carrying
an English possessive.

That mattered more than the check that found it. The first tenant is a Russian-speaking single-person
business, and this is the console she opens every day.

## What was built

- The string mechanism `ago-console` already proved, **reused rather than reinvented**: `en`/`ru`
  tables, `StringsContext`, `resolve.ts`, under `src/i18n/`. Same shape next door, same problem.
- All eight screens plus the app shell wired through it.
- **The possessive fixed structurally, not patched.** One string field could never hold both forms —
  English puts its fragment *after* the name, Russian *before* — so the heading is composed from a
  prefix and a suffix at the call site, one of which is empty in each language.

### What decides the locale

A single hardcoded constant, `DEFAULT_CONSOLE_LOCALE = "ru"`, wrapped once at the root. This was the
item's own open question, and the answer is deliberately the smallest one:

- **The per-tenant round trip `ago-console` uses** (`Site.WidgetLocale`) needs a field on
  `Ago.Calendar.Api` — a different repository, and `adr/0027`'s standing warning is precisely about
  two products resolving the same thing two ways without deciding to.
- **Browser-language detection** was rejected by `11-11` for a reason that transfers unchanged: a
  business's language is not the reader's machine setting.
- **A per-operator toggle** is deferred exactly as `ago-console` deferred it. Nobody has asked.

`StringsContext`'s own default stays `en`, mirroring `ago-console` — which is what let 61 pre-existing
tests pass with zero edits, since they render pages directly, outside `<App>`.

## Found while doing it, and not in the item

`WorkerScheduleSection.tsx` held two pieces of **unconditionally hardcoded Russian** — the buffers
checkbox label and the 70-minute worked example. The same bug in reverse: an English console with
Russian in the middle of it. Fixing it required updating two pre-existing test assertions that had
baked that Russian in as the expected default output.

## Done when

- [x] `ago-calendar-console` has a string table and a locale context, and every screen `15-11` gates
      renders from it.
- [x] Switching locale changes the rendered text, proven by a test rather than by the table existing.
- [x] `15-11`'s existing three assertions stay green — 10 failed / 14 passed before and after,
      identical, the ten being the pre-existing `#22`/`#23` overflow and sizing defects.

## What was split off, and why

Two Done-when boxes from the original item are **not** delivered here and moved wholesale to `11-16`:

- the fourth gate assertion — no Latin-script interface text on a Russian screen, in **both** consoles
  at both viewports, proven to fail first;
- fixtures re-seeded in Cyrillic, and the named `/owner` exemption list.

They were split rather than finished because the remaining half needs `ago-console`, which had an
unmerged branch in flight at the time (`10-06`). That is genuine interference, not convenience: two
tasks in one repository is the collision the workflow exists to prevent.

The ordering also turned out to be the right one on its own merits. Adding the assertion before this
repair would have produced a permanently red build in `ago-calendar-console` — the failure mode
`ago-calendar-console#26` already exists to unwind.

## Verified

`typecheck` 0 errors · `lint` 0 errors/warnings · **10 test files, 67/67 passing** (61 pre-existing +
6 new) · `vite build` succeeds at 370.22 kB / 109.03 kB gzip.

Two checks beyond the report, run by the merging session: the built bundle was grepped for the Russian
strings, proving they survive tree-shaking — which a passing suite does not; and the fails-before entry
that matters was re-proved by hand, reverting the heading to the possessive form and watching the
Russian test fail on exactly its own assertion, in both directions.
