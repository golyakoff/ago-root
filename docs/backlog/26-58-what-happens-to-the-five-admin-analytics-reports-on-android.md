# 26-58 · What happens to the five administrator analytics reports on Android

- **Stage**: 26
- **Status**: done — decided, remainder carried out as `26-70`..`26-74`
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

## Open questions, answered

1. **Do the four `site:configure` reports port to Android at all?** **Yes — the author's own answer,
   2026-09-23**: `scope-inventory.md` §2's exclusion is for the five *platform-owner* screens (AGO's
   own operators, managing the platform itself); these four are *tenant-owner* screens — the shop
   owner's own numbers about their own business, the party who is actually paying for the product. The
   analogy this item originally drew to the platform-owner exclusion was the wrong one: "desk work with
   no time pressure" describes AGO's own back office, not a tenant checking how their site is doing.
   All four port.
2. **One screen with a picker, or four destinations behind an overflow?** **Four, behind an overflow**
   — the mockup itself already answers this, not a fresh design call: its own graph draws
   `MyNumbers -- "⋮ · site:configure" --> SiteStats` and three siblings, i.e. four separate destinations
   reached from one overflow menu, matching the console's own four routes exactly rather than
   collapsing them into a single screen with a breakdown picker.
3. **Does `/calendar/phone-reveals` port, and does it come with `26-53` or separately?** Porting it
   follows from the same reasoning as (1) — it is the tenant's own audit trail of who looked up a
   customer's phone, gated on `calendar:configure`, not a platform-owner concern. It is a different
   *promise* from `26-53` (26-53 performs a reveal; this reads back a history of reveals already
   performed) — rule 15's own test — so it is its own item, not folded into 26-53.

## The remainder, carried out to its own numbers

- `26-70` — the Аналитика overflow menu itself, plus «Аналитика сайта» (`/analytics/site`), its first
  real destination. Filed together because an overflow with nothing behind it is the dead-menu shape
  `26-40` already rejected — the menu and its first item are one promise.
- `26-71` — «Отчёт по конверсии» (`/analytics/conversion`).
- `26-72` — «Разбивка по тегам» (`/analytics/tags`).
- `26-73` — «Воронка записи» (`/analytics/booking-flow`).
- `26-74` — «Показы телефонов» (`/calendar/phone-reveals`), the audit read-back.

## Done when

- [x] Each of the three questions above has an answer recorded in this file.
- [x] Every report the answers say to build has its own numbered item (`26-70`..`26-74`).
- [x] Every report the answers say **not** to build has its exclusion recorded here with the reason —
      none; all five port.
- [x] `scope-inventory.md` §5 is corrected in `ago-android` to reflect that all five now have a real
      item rather than "redesign"/"as-is" with no owner — `ago-android@5f2d474`, landed 2026-09-23.
