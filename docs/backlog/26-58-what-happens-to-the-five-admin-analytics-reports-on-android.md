# 26-58 · What happens to the five administrator analytics reports on Android

- **Stage**: 26
- **Status**: blocked
- **Depends on**: `26-57` (Аналитика's first real screen — this item decides what, if anything, sits
  behind it)
- **Found**: 2026-09-23, reading `ago-console/src/shell/consoleNav.ts:187-199` and
  `ago-android/docs/scope-inventory.md` §5 against `ago-android` `main` at `b099282`.

## Why this is a question rather than a slice

`26-57` builds «Мои показатели» because it is ungated, personal, and read between conversations. The
other five reports under Аналитика are the opposite of all three, and the honest answer to "do they
port" is **not obvious, and not this session's to decide**. `scope-inventory.md` marks four of them
"redesign — same shape as above" without saying whether that shape is worth building, and the fifth
is an audit trail. Filing five implementation items would be deciding by dispatch.

`CLAUDE.md` rule 14: the managing session files a found defect itself, but files it *as the question*
when the honest item would decide something. This is that.

## What is actually true today, confirmed against real code

The five, with their real gates, from `ago-console/src/shell/consoleNav.ts:187-199`:

| Route | Gate | Console shape | `scope-inventory.md` §5 |
|---|---|---|---|
| `/analytics/site` | `site:configure` | Date-range form + several tables of three numbers | redesign |
| `/analytics/conversion` | `site:configure` | Same shape | redesign |
| `/analytics/tags` | `site:configure` | Same shape | redesign |
| `/analytics/booking-flow` | `site:configure` | Same shape | redesign |
| `/calendar/phone-reveals` | `calendar:configure` | One row per reveal, keyset paged | as-is |

Two facts that bear on the answer:

- **`/calendar/phone-reveals` is not like the other four.** It keeps its `/calendar/` address and its
  own `calendar:configure` gate while living under Аналитика in the nav — `25-17` moved the nav entry
  deliberately and left the route alone (`consoleNav.ts:174-186`). It is also the only one of the five
  that is a *record of what people did* rather than a *count of what happened*, and it is the read-back
  side of `26-53`, which this batch adds to the phone. If any of the five earns a place, this is the
  strongest candidate, and it is the one `scope-inventory.md` already calls "as-is".
- **The mockup draws all five behind an overflow, not as tabs** (`MyNumbers -- "⋮ · site:configure"
  --> SiteStats` and three siblings; `MyNumbers -- "⋮ · calendar:configure" --> Reveals`). So the
  design question is not only "which of them", but "does an overflow menu on Аналитика exist at all"
  — and an overflow that opens an empty menu is the shape `26-40` already rejected for the thread's
  own `⋮`.

## Open questions

1. **Do the four `site:configure` reports port to Android at all, or does the app link out to the
   console for them the way `/account/billing` links out for checkout (`scope-inventory.md` §9)?**
   They are desk work with no time pressure, which is the exact test `scope-inventory.md` §2 used to
   exclude the five platform-owner screens. Excluding them is a defensible answer; so is porting them
   as "date-range chips, stat cards, one horizontally-scrollable table per breakdown". What is not
   defensible is building them by default because they exist.
2. **If they port, is it one screen with a breakdown picker, or four destinations behind an
   overflow?** The four share a shape; the console keeps them as four routes because a rail has room
   for four labels. A phone may not want four.
3. **Does `/calendar/phone-reveals` come to Android with `26-53`, or separately?** It is the audit
   read-back for the reveal this batch adds. Landing the reveal without the read-back is a real,
   if small, asymmetry worth deciding on purpose.

## Scope, once the questions are answered

Nothing here is implementation. This item's whole output is: the answers above recorded, and **a new
numbered item per report that is actually going to be built** — a remainder gets a number, not a link
(`CLAUDE.md` rule 14). If the answer to (1) is "link out", that is a small item of its own and this
one closes as decided, not as done-nothing.

## Done when

- [ ] Each of the three questions above has an answer recorded in this file.
- [ ] Every report the answers say to build has its own numbered item.
- [ ] Every report the answers say **not** to build has its exclusion recorded here with the reason,
      the way `scope-inventory.md` §2 records each owner screen's.
- [ ] `scope-inventory.md` §5 is corrected in `ago-android` if any row's disposition changed.
