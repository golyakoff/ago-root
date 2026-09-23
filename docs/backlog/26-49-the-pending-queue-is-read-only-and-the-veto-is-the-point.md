# 26-49 · The pending queue is read-only, and the veto is the whole point of it

- **Stage**: 26
- **Status**: ready
- **Depends on**: `26-48` (the calendar API client and the Ожидают screen itself)
- **Found**: 2026-09-23, reading `ago-console/src/pages/CalendarQueuePage.tsx` and
  `ago-console/src/api/calendarApi.ts` against the approved mockup Artifact ("AGO Chat для Android",
  `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`) §04, and `ago-android` `main` at `b099282`.

## Found

`26-48` puts the real queue on the phone and stops there. That leaves the app able to tell an operator
that a booking will auto-confirm in three hours and unable to do anything about it — which is the one
thing this destination exists for (`scope-inventory.md` §4: "everything auto-confirms unless somebody
vetoes it before the deadline, so acting away from a desk has real value").

**The mockup and the product disagree about one button, and the product is right.** The mockup's card
draws «Подтвердить» beside «Отклонить». There is no confirm endpoint:
`ago-console/src/api/calendarApi.ts` exports `rejectBooking` (`:659`), `cancelBooking` (`:663`) and
`markNoShow` (`:667`) for this row, and nothing else — because confirmation is what the server's own
sweep does by default. `CalendarQueuePage.tsx:48` states it in one line: "Reject, not approve."
Drawing a «Подтвердить» that either does nothing or fakes a no-op is the exact shape `26-15` rejected
for the visitor chip. This item draws the actions that exist.

## What is actually true today, confirmed against real code

- The console's three actions, and their shared busy-state discipline:
  `CalendarQueuePage.tsx:166-186` (`act`) sets `busyId`, calls, **re-reads the queue first and only
  then sets the error message** — its own comment says why: losing a race with the sweep is an
  ordinary outcome, and a successful reload clears the error, so the other order would wipe the one
  sentence the operator needed. That ordering is a real, hard-won behaviour and must port, not be
  re-derived.
- Each button is disabled per row while that row is busy
  (`CalendarQueuePage.tsx:258-266`, `disabled={busyId === row.bookingId}`) — not globally.
- The gate is already settled and is wider than `calendar:configure`:
  `CalendarQueuePage.tsx:70` — `calendar:configure` **or** any of the three booking-action
  permissions. Android's own `Permission.kt:26-28` already names all three.
- Android has no equivalent of any of this: `PlaceholderScreens.kt:50-55`.

## Scope

One promise: **an operator can veto a pending booking from the phone.**

1. `rejectBooking`, `cancelBooking` and `markNoShow` on the `BookingsApi` port `26-48` introduces,
   each a `204`-or-refusal write, with the refusal carrying the server's own RFC 7807 `detail` the way
   `KtorConversationsApi.claim` already does (`KtorConversationsApi.kt:61-85`).
2. The card's actions, drawn per row, each disabled while that row's own write is in flight — never
   the whole list. A second tap while in flight does nothing; no write is ever sent twice from one
   deliberate tap (`CLAUDE.md` rule 5 read from the client side).
3. The console's error ordering, ported verbatim: re-read the queue, *then* show the failure. A
   booking the sweep confirmed a second before the tap disappears from the list and the operator is
   told why, rather than being left looking at a row that no longer exists.
4. **No «Подтвердить».** Say so on the screen if anything needs saying — the mockup's own caption
   already does («Всё подтверждается автоматически») — but draw no control for it.

## Out of scope

- **Adding a confirm endpoint to `ago-calendar`.** That is a product decision about the booking
  lifecycle, not an Android item, and nothing about this app is a reason to make it.
- A confirmation dialog in front of each action. The console has none
  (`CalendarQueuePage.tsx:253-269`), and the actions are logged and recoverable at the tenant level;
  adding one on the phone alone would make the two clients disagree about how dangerous the same act
  is.
- The names on the card — `26-50`.
- Утверждены and Клиенты — `26-51`, `26-52`.

## Done when

- [ ] An operator holding `booking:reject` can reject a pending booking from the phone and sees it
      leave the queue.
- [ ] A refusal from the server renders the server's own `detail`, and the list is re-read before that
      message is shown.
- [ ] Rapidly tapping one row's action twice produces exactly one server call.
- [ ] No «Подтвердить» control exists anywhere on the screen.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
- [ ] Checked on a real device against a real pending booking, rejected, and confirmed gone from the
      console's own `/calendar/waiting` as well.
