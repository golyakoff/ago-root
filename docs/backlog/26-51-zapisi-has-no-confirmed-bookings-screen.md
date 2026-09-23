# 26-51 · Записи has no Утверждены tab — nowhere to see what is actually on for Thursday

- **Stage**: 26
- **Status**: done — merged as [ago-android#53](https://github.com/golyakoff/ago-android/pull/53)
- **Depends on**: `26-48` (the calendar API client and the Записи segmented control)
- **Found**: 2026-09-23, reading `ago-console/src/pages/CalendarBookingsPage.tsx` against the approved
  mockup Artifact ("AGO Chat для Android", `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`) §04's second frame,
  and `ago-android` `main` at `b099282`.

## Found

The pending queue answers "is anything about to auto-confirm". It does not answer the question a shop
actually asks a dozen times a day — "what is on for Thursday" — and today nothing in the app does.

This is the one console layout that is fundamentally wide: a week × master grid. The mockup's answer
is not a shrunk grid, and that is the whole design content of this item: **swap the axes.** A
horizontal date strip picks the day; below it, that day's bookings grouped by master, each group
headed by the master's name and its own count («Ирина Соколова · 4 записи»). The question is
unchanged; only the order the two axes are consumed in is.

## What is actually true today, confirmed against real code

- `app/src/main/kotlin/ago/chat/android/shell/PlaceholderScreens.kt:50-55` — the destination is one
  sentence, and `26-48` gives it only its first segment.
- The console screen: `ago-console/src/pages/CalendarBookingsPage.tsx`.
  - Its gate is `customer:read` (`:156`, `:182`) — **not** `calendar:configure`, and not the pending
    queue's own wider gate. An operator holding only `booking:reject` sees Ожидают and must not see
    this tab at all; the segmented control has to be built from permissions, not drawn fixed.
  - Its read is `getConfirmedBookings(token, from, to)` (`calendarApi.ts:645`), a **date range**, not
    a day — `defaultRange()` (`:29-34`) is today plus a horizon. The date strip needs a range to
    populate its own dots, so the range read is what the phone wants too; only the *rendering* is
    per-day.
  - `groupByDayThenWorker` (`:55`) already produces exactly the shape the mockup draws, day then
    worker. Port the grouping rule, do not re-derive it.
  - `ConfirmedBooking` (`calendarApi.ts:216-233`) already carries `workerDisplayName`, `serviceName`
    and `customerDisplayName` — this screen needs no wire change of any kind, unlike `26-48`'s
    (`26-50`).
- Identifier rendering is already settled in this app: a customer with no `customerDisplayName`
  renders through `IdentifierText` (`ui/components/IdentifierText.kt:26-36`), never a full GUID and
  never «Клиент #4790».

## Scope

One promise: **Утверждены shows one chosen day's confirmed bookings, grouped by master.**

1. The segment appears only for an operator holding `customer:read`, matching
   `CalendarBookingsPage.tsx:156`. An operator without it sees Записи with one segment and no empty
   tab — the same "a destination with nothing inside it is not drawn" rule
   `visibleBottomDestinations` already applies one level up (`BottomDestination.kt:49-56`).
2. A horizontal date strip across the top: weekday, day number, and a dot on a day that has anything
   on it. Today is selected on arrival. The strip's own span comes from the same range read the list
   uses.
3. Below it, that day's rows, grouped by master, each group headed by the master's name and its own
   count. A row is time, service, customer, duration — the mockup's own `.rtime` / `.rname` /
   `.rsnip` shape, which `ConversationRow` already established metrics for.
4. Times are the business's own zone and digits-only, exactly as the console renders them
   (`scope-inventory.md` §4) — **not** the device's zone. This is the one place in this app where
   that differs from what `ThreadScreen.clockTimeOrNull` does, and it differs on purpose: a booking is
   an appointment at the shop, not an event in the reader's day.

## Out of scope

- **Tapping a row.** The mockup's graph has `Confirmed -- "тап" --> BookingCard`; the booking card is
  its own screen with its own audited phone reveal and is not this promise.
- **Changing the range.** The console has two date inputs (`CalendarBookingsPage.tsx:283,294`); the
  strip replaces them for the ordinary case. Reaching a date outside the default horizon is a real
  gap and worth its own item once somebody misses it — do not grow this one to cover it.
- The masked phone and its Показать — `26-53`.
- Ожидают (`26-48`, `26-49`) and Клиенты (`26-52`).

## Done when

- [x] An operator holding `customer:read` sees the Утверждены segment and can move between days with
      the strip — proven by `ConfirmedBookingsViewModelTest`, not by live rendering (see below).
- [x] A day with nothing booked renders a stated empty state, not a blank area — unit tested.
- [x] Bookings are grouped by master, with the master's own count in the group header —
      `ConfirmedBookingGroupingTest` proves the ported `groupByDayThenWorker` rule directly.
- [x] Times render in the business's zone, and a test proves a device set to a different zone still
      shows the booking's own local time — `BusinessLocalTimeTest`.
- [x] An operator holding only a booking-action permission does not see this segment at all — unit
      tested against the widened `bookingsTab: (Boolean) -> Unit` slot.
- [x] `./gradlew ktlintCheck lint test assembleDebug` green — 249 tests, 0 failures, independently
      re-verified after rebase.
- [~] Checked on a real device against a tenant with confirmed bookings on at least two days and two
      masters — **not done**. The session's existing SSO on the test device expired mid-session; the
      app was confirmed to install, launch and reach the real Keycloak login cleanly, but the
      authenticated screen itself (real date strip, grouping, day-master rendering) was not checked
      live. Recorded honestly rather than overclaimed.
