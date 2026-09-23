# 26-73 · «Воронка записи» is not on the phone

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, reading `ago-console/src/pages/BookingFlowConversionPage.tsx`,
  `ago-console/src/api/conversationsApi.ts` and `ago-console/src/realtime/protocol/types.ts` against
  `ago-android` `main` at `b099282`, with the approved mockup Artifact ("AGO Chat для Android",
  `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`)'s own `MyNumbers -- "⋮ · site:configure" --> Funnel`.

## Found

The fourth of the five reports `26-58` decided to port, and **the smallest screen in the whole
batch** — the console's own version is two numbers and a caveat, deliberately. `26-70` builds the
overflow this hangs off.

## What is actually true today, confirmed against real code

- `ago-console/src/App.tsx:392` → `BookingFlowConversionPage`, drawn at `consoleNav.ts:193`, gated
  `site:configure`.
- The read is `GET /api/v1/conversations/module-flow-report` (`conversationsApi.ts:644`), **both
  bounds optional** (`BookingFlowReportParams`, `:517`).
- **The response has no dimension to break down by** (`types.ts:533`): `from`, `to`,
  `flowsStarted`, `flowsClosed`, and the previous window's `previousFrom`/`previousTo`/
  `previousFlowsStarted`/`previousFlowsClosed`. That is the whole body.
- The console renders it as a plain `<dl>` and says why in its own doc comment
  (`BookingFlowConversionPage.tsx:51-54`): a `Table` built for many rows is the wrong tool for two
  numbers.
- **The caveat is an `Alert`, not a footnote** (`:231`, reasoned at `:45-50`): `flowsStarted`/
  `flowsClosed` are deliberately *not* `bookingsStarted`/`bookingsConfirmed` — a closed module task
  is not a confirmed booking, and the report must say so where a reader actually reads.
- **Its invalid-range error code is its own**: `ModuleFlow.InvalidRange`, not `Analytics.InvalidRange`
  (`:100-106`), alongside `bookingFlowForbiddenError` and the generic one. Reusing the other
  reports' code here would swallow the branch.
- **No date presets on this page** — two date fields and an apply button only (`:166-191`), unlike
  the conversion and tag reports.
- The empty state is `flowsStarted === 0` specifically (`:206-207`), not a null check.

### What the mockup does and does not say

The mockup names this destination («Воронка записи») and its gate as a graph node and an overflow
edge, and **draws no frame for the screen itself**. `scope-inventory.md` §5's "date-range chip row,
stacked stat cards, one horizontally-scrollable table per breakdown" is **wrong for this one and
must not be copied literally**: there is no breakdown, so there is no table, and there are no presets
in the console to turn into chips. Two stat cards is the honest shape, and that is a real finding
from the data rather than a compression of a desktop screen.

## Scope

One promise: **«Воронка записи» shows how many conversations started a booking flow and how many of
those flows closed, in a chosen window.**

1. A `BookingFlowReportApi` port in `:core:domain` and a Ktor adapter in `:core:network`, on the
   existing `apiBaseUrl` — the chat API, **not** the calendar one (`26-48` added a second base URL;
   this report is served by `Ago.Chat`, so it does not touch it).
2. A new entry in Аналитика's overflow («Воронка записи»), gated `site:configure`, one level deep
   with the same `BackHandler` contract `26-70` establishes.
3. Default window on first composition; the range displayed is the response's own.
4. **Two stat cards and the caveat**, in that order or with the caveat above them — never a table,
   and never the caveat as a caption under a scroll.
5. The previous-window comparison for both numbers, the way the console renders it (`:225-227`).
6. **`ModuleFlow.InvalidRange` keeps its own message**, distinct from the forbidden and the generic
   one; every other failure is a refusal with a retry (`26-59`).
7. A date-range control with no presets, matching the console — inventing three presets here that
   the console's own screen does not have would be a design change riding along with a port.

## Out of scope

- **The overflow menu itself** — `26-70`.
- **Anything about the bookings themselves.** The pending/confirmed queues are `26-48`/`26-51`, on
  the calendar API; this report counts *chat-side module flows* and is a different fact, which is
  exactly what the caveat exists to keep visible.
- **Renaming the two numbers to anything booking-shaped.** The server's own contract refuses that
  (`types.ts:533`'s remarks); so does this screen.

## Done when

- [ ] An operator holding `site:configure` reaches «Воронка записи» from Аналитика's overflow and
      sees both numbers for the server's default window with no interaction.
- [ ] The caveat that a closed flow is not a confirmed booking is visible beside the numbers.
- [ ] Neither number is labelled as a booking count anywhere on the screen.
- [ ] An invalid range renders the `ModuleFlow.InvalidRange` message specifically, not the message
      the other analytics screens use.
- [ ] A window with `flowsStarted == 0` renders the empty state, not two zeroes.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
- [ ] Checked on a real device, in both light and dark, against a window with flows and one without.
