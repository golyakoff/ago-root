# 26-282 · Клиенты list surfaces per-client booking state (per-row count, «С предстоящей» filter, no-show pill placement)

- **Stage**: 26. Kind: implementation (Android). The **deferred** list-surface items from the 26-269
  clients-vs-mockup gap analysis (commit `3f43742`) — real mockup features, held because they need the
  list read to carry per-client booking state (unlike the cosmetic/behavioural halves that shipped from
  already-loaded data). Filed 2026-09-29 so nothing from the analysis is untracked.
- **Status**: done 2026-09-29 — merged as ago-calendar#86 (UpcomingBookingCount) + ago-android#211 (per-row count + «Все / С предстоящей / Без записей» filter), delivered together with 26-283/26-284 in the clients iteration-2 pass.
- **Repos touched**: `ago-android` (UI) and likely `ago-calendar` (the `/contacts` read must carry a
  per-client upcoming/total booking count — verify whether it already can before assuming a contract
  change).

## The gaps (from the analysis)

- **A7 — per-row booking count.** The mockup shows «N записей» (or an upcoming indicator) on each list
  row. The detail hub already shows the count (26-269 B5), but the list row does not — and the list read
  (`GET /contacts`) does not currently carry it. Needs the count on the wire, then rendered per row.
- **A8 — «Все / С предстоящей» filter.** The mockup offers a filter chip row to show only clients with an
  upcoming booking. Needs the same per-client upcoming signal A7 needs, then a client-side (or server)
  filter.
- **A3 — no-show pill placement (minor).** In the app the no-show pill sits below the phone; the mockup
  places it to the right of the row. Cosmetic; fold in here since it touches the same row layout.

## The one promise

The Клиенты list shows and can filter by each client's booking state (a per-row count and an
upcoming-only filter), matching the mockup.

## Done-when

- [ ] The `/contacts` read carries a per-client booking count (and/or has-upcoming flag) — or it is
      confirmed it already does. Contract change (if any) is additive.
- [ ] A7: each list row shows the count. A8: a «Все / С предстоящей» filter row narrows the list.
- [ ] A3: no-show pill placement matches the mockup.
- [ ] Strings both languages; `ktlintCheck`/`testDebugUnitTest`/`assembleDebug`/`compileDebugAndroidTestKotlin` green;
      if the calendar contract changed, its own suite green too.
