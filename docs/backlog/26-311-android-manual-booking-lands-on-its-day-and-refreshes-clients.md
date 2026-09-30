# 26-311 · [android] After a manual booking, land on its day in Утверждены and refresh Клиенты

- **Stage**: 26
- **Status**: done — merged as `ago-android#221` (`db94a54`). Both call sites of `ManualBookingSheet`
  (BookingsScreen, ClientDetailScreen) updated; new gated `onFocusConfirmedDate` jumps the confirmed
  strip to the booking's business-local day via `onDatePicked(selectedSlot.localDate)`, and
  `onCreated` now also calls `ContactsViewModel.refresh()`. Gates green (1046 unit tests, 0 failures;
  `ManualBookingViewModelTest` 22) + CI instrumented-tests; APK published on main.
- **Found**: 2026-09-30, by the author, using «Добавить вручную» on his own phone. Two notes about what
  happens right after a booking is created:
  - "надо первое переходить сразу к дню, который покажет созданную запись в утверждённых" — the app
    switches to the Утверждены segment but stays anchored on today, so a booking made for a future day
    is not the selected day and the operator has to find it by hand.
  - "второе – обновить список клиентов. Сейчас он там не появился." — a booking made for a *new* client
    persists the client server-side (it shows in Утверждены), but the Клиенты list is never re-read, so
    the new client is absent until the operator leaves and returns.

## What is true today, confirmed against `origin/main`

`ManualBookingSheet`'s `onCreated` in
`app/src/main/kotlin/ago/chat/android/bookings/BookingsScreen.kt` does exactly three things:

```kotlin
showManualBookingSheet = false
onSegmentSelected(BookingsTab.Confirmed)
onRetryConfirmed()          // == ConfirmedBookingsViewModel.refresh()
```

- `refresh()` re-reads the confirmed range around `anchorDate` (default **today**) and sets
  `selectedDate = range.from`. `confirmedBookingsRange(anchor).from == anchor`, so after a plain
  `refresh()` the selected day is always today — never the created booking's day when that differs.
- `ConfirmedBookingsViewModel.onDatePicked(date)` already does the right thing: `anchorDate = date;
  refresh()`, which re-anchors the window on `date` and selects it (`range.from == date`). It is only
  wired to the month/year date-picker today, not to this flow.
- The Клиенты list is a separate read (`ContactsViewModel.refresh()` → `api.fetchContacts()`) and
  `onCreated` never calls it. That is the whole of the "new client didn't appear" bug — the list is
  stale, not the server.

## The day key must be the booking's business-local date, not a client-side conversion of `startsAt`

Утверждены groups days by `ConfirmedBooking.localDate`, a **server-computed business-local** `YYYY-MM-DD`
(`e.local_date`), not UTC and not the device zone. The reliable, zone-safe key already on hand is
`ManualBookingUiState.Wizard.selectedSlot.localDate` (documented as "a business-local `YYYY-MM-DD`, one
of `WorkerSlot.localDate`") — the same notion the server uses. **Do not** convert `Created.startsAt`
(an ISO instant) to a `LocalDate` on the client: a DST/zone boundary would land on the wrong day.

## Shape of the fix

1. Carry the booking's business-local date to the terminal state: add `val localDate: String` to
   `ManualBookingUiState.Created`, set in `ManualBookingViewModel.submit()` from
   `wizard.selectedSlot.localDate` (the slot is already resolved and non-null at `Review`).
2. `ManualBookingScreen`: change `onCreated: () -> Unit` → `onCreated: (localDate: String) -> Unit`;
   the existing `LaunchedEffect(state) { if (Created) onCreated(state.localDate) }`.
3. `BookingsScreen`'s `onCreated`:
   - keep `showManualBookingSheet = false` + `onSegmentSelected(BookingsTab.Confirmed)`;
   - replace `onRetryConfirmed()` with a new `onFocusConfirmedDate(localDate)` callback wired to
     `ConfirmedBookingsViewModel::onDatePicked` (jumps to + re-reads the booking's day). Mirror the
     `showConfirmedSegment`-gated `{}` no-op pattern `onRetryConfirmed` already uses.
   - add `onRetryContacts()` so Клиенты re-reads and the new client appears. It is already `{}` when
     the operator lacks the clients segment.

## Done when

- [x] Creating a manual booking for a future day switches to Утверждены **and** the selected day is the
      booking's own day, with the booking visible in the list — no manual scrolling.
- [x] Creating a manual booking for a brand-new client leaves that client present in Клиенты without
      leaving and returning to the screen.
- [x] The day passed to the confirmed view is `selectedSlot.localDate` (business-local), not a
      client-side conversion of `startsAt` — asserted in a `ManualBookingViewModel` unit test that the
      `Created` state carries the slot's `localDate`.
- [x] Gates green: `:app:ktlintCheck :app:testDebugUnitTest :app:assembleDebug
      :app:compileDebugAndroidTestKotlin`, plus CI's instrumented-tests.
