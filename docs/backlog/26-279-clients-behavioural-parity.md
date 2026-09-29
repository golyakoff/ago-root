# 26-279 · Клиенты behavioural parity with the mockup (nameless identity, call button, booking-detail card before reschedule)

- **Stage**: 26. Kind: implementation (Android). The behavioural half of the 26-269 clients-vs-mockup gap
  analysis (git commit `3f43742`), author-approved 2026-09-29. The cosmetic half (A1/A2/A5/A6/B2/B5/B6/B7)
  and the past-booking read-only card (B9) landed under 26-269 (ago-android#209); this item is the three
  **behavioural** gaps that were deferred, not dropped.
- **Status**: done 2026-09-29 — merged as ago-android#210.
- **Repos touched**: `ago-android` only.

## The three behavioural gaps (from the gap analysis, cited)

- **A9 — nameless client identity.** A client with no chat name currently renders the **raw person-id**
  (e.g. `01a0c554…`) as its title in the list (`ContactsScreen.VisitorIdentityText`) and the detail
  header. The mockup shows a real identity: the stored **emoji pair** (creature + food — *read* it off
  the row, never hash-derive it; `reference_visitor_emoji_pair_is_stored`), and when there is no chat
  identity at all, the **phone as the title** plus a «Без имени» label. Never a bare id.
- **B3 — «Позвонить».** The client-detail card reveals the phone but offers no way to call it. Add a
  «Позвонить» action that fires `Intent.ACTION_DIAL` with the revealed number (dial, not call — no
  CALL_PHONE permission), beside the existing reveal.
- **B8 — booking-detail card before reschedule (upcoming).** Tapping an **upcoming** booking row jumps
  straight into `RescheduleBookingSheet`, skipping the mockup's booking-detail card. It should open the
  booking-detail card first (service / master / date-time / phone / source) — reusing the
  `ConfirmedBookingDetailBody` that 26-269 (B9) already made `internal` with a `readOnly` param — with
  «Перенести» **and** «Отменить» reachable from the card (`readOnly = false`). The read-only past-booking
  card (B9) is unchanged.

## The one promise

The Клиенты surfaces behave like the mockup: a nameless client shows a real identity, its phone can be
dialled, and an upcoming booking opens its detail card (reschedule/cancel from there) instead of jumping
straight to reschedule.

## Done-when

- [x] A9: nameless client shows the stored emoji pair, else phone-as-title + «Без имени», in the list and
      the detail header — never a raw person-id. New pure resolver `resolveVisitorIdentityFallback` + 5 unit tests.
- [x] B3: «Позвонить» fires `ACTION_DIAL` with the revealed number (with `ActivityNotFoundException` catch).
- [x] B8: an upcoming booking row opens the booking-detail card (reusing `ConfirmedBookingDetailBody`,
      `readOnly = false`); «Перенести» and «Отменить» are reached from the card. Past rows (B9) unchanged.
- [x] New strings as resources both languages. `compileDebugAndroidTestKotlin` green (no androidTest
      callers of the changed composables).
- [x] `ktlintCheck`, `testDebugUnitTest` (964, 0 fail), `assembleDebug`, `compileDebugAndroidTestKotlin` all green.

## Outcome

Merged as ago-android#210, 2026-09-29 (build-test + instrumented-tests both green). The deferred
list-surface items (A7 per-row count, A8 filter, A3 pill placement) and B4 «Записать» deep-link are
tracked as 26-282 and 26-283.
