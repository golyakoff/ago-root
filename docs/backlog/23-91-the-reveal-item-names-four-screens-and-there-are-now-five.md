# the reveal item names four screens and there are now five

- **Stage**: 23
- **Status**: done — `ago-console#192`
- **Depends on**: `23-30`, whose scope this corrects. `23-34` is the screen it missed.
- **Found**: 2026-09-07, while settling `23-34`'s Done-when.

## The gap, in one sentence

`23-30` — *the calendar console reveals a masked number on demand* — enumerates **four** screens:
queue, contacts, worker slots, recut preview. **`23-34` shipped a fifth**, the confirmed-bookings list,
which renders a masked phone and has no reveal control.

`23-34` did not exist when `23-30` was written, so this is a scope that went stale rather than a scope
that was wrong.

## Why it needs a number rather than an edit

Because of what happens if it does not get one. `23-30` ships as currently scoped, four screens gain a
reveal, everyone treats reveal as delivered — and `23-34`'s second Done-when is **still false**, on a
screen nobody is looking at any more. A masked number with no way to reveal it is not a security
property; it is a screen an operator cannot do their job from, and the reason will be invisible.

An enumerated scope is a promise that the enumeration is complete. When it stops being complete, saying
so out loud is cheaper than discovering it from a support call.

## Scope

- **Either widen `23-30` to five screens before it is built, or make this the fifth.** Widening is
  probably right — one reveal control, five callers, one audit record — but that is a judgement about
  `23-30`'s size and belongs to whoever picks it up.
- **Whichever way, `23-34`'s second box closes with it**, and this item names that explicitly so the
  link is not lost again.

## Where this is likely to go wrong

- **The audit record is the point, not the reveal.** `23-34`'s box says *revealing it writes the same
  record* — the same one, not a similar one. A fifth screen with its own reveal path that writes a
  differently-shaped record satisfies the sentence and defeats it.
- **There may be a sixth.** The lesson generalises: check the screens that render a masked number at
  the time `23-30` is built, rather than trusting either enumeration.

## Done when

- [x] Every console screen that renders a masked calendar phone can reveal it, or is listed with a
      reason why not.
      All five - queue, contacts, worker slots, recut preview (`23-30`), and now confirmed bookings
      (`ago-console` `CalendarBookingsPage.tsx`, this item) - render a masked phone through the same
      `renderPhone`/`RevealControl` pair, each with a working Reveal button. No sixth screen renders a
      masked calendar phone today (checked: `CalendarQueuePage`, `CalendarContactsPage`,
      `CalendarWorkerSlotsPage`, `CalendarWorkerRecutPage`, `CalendarBookingsPage` are the only callers
      of `ConfirmedBooking`/`Contact`/`WorkerSlot`'s own `phone`/`masked` fields in `ago-console`).
- [x] The reveal writes one record shape, wherever it is triggered from.
      `CalendarBookingsPage.handleReveal` calls the exact existing `revealCustomerPhone(token,
      customerId, surface)` client function against the exact existing
      `POST /api/v1/console/contacts/{customerId}/reveal-phone` endpoint (`23-12`,
      `RevealCustomerPhoneHandler` in `ago-calendar`) with `surface: "ConsoleBookings"` - the same
      handler, the same `IContactPhoneRevealRepository.RecordAsync` write, the same
      `ContactPhoneRevealToWrite` shape every other screen's reveal already produces. No new or
      changed backend endpoint, and `Surface` was already a plain string
      (`RevealCustomerPhone.cs`'s own doc comment: "not a closed enum"), so adding a fifth surface
      value needed no contract change either.
- [x] `23-34`'s second Done-when is true.
      See Outcome below and `23-34`'s own file (updated separately, in the same change, by the
      managing session).

## Outcome

`ago-console` branch `feat/23-91-confirmed-bookings-phone-reveal`: `CalendarBookingsPage.tsx` gained
a `revealingCustomerId` state, a `handleReveal` function, and a `RevealControl` built from it - the
identical shape `CalendarContactsPage`/`CalendarQueuePage`/`CalendarWorkerSlotsPage` already carry -
and its `phone` table column now calls `renderPhone(row, strings, reveal)` instead of rendering
`row.phone` verbatim. `ConfirmedBooking` already carried `customerId` on every row, so no new prop
had to be threaded through. This was a pure frontend change confirmed by reading
`RevealCustomerPhoneHandler`/`RevealCustomerPhone.cs` in `ago-calendar`: the endpoint is gated on
`Permission.CustomerRead`, the exact permission `CalendarBookingsPage` already client-side gates the
whole screen on, and takes a customer id plus a free-text `surface` string - nothing about the
existing contract assumed a fixed set of callers.

Grouping (`groupByDayThenWorker`, day → worker → rows) turned out not to complicate the reveal
mechanics: `handleReveal` updates the flat `rows` array by `customerId` match, and the grouped view
re-derives from `rows` on every render, so a customer's phone reveals in every day/worker group it
appears in from the one state update - the same "match by customerId over the flat array" rule
`CalendarQueuePage.handleReveal` already uses for the queue.

Three new tests in `CalendarBookingsPage.test.tsx` (`describe("revealing a masked phone (23-91)")`)
mirror `CalendarQueuePage.test.tsx`'s own reveal tests: masked value + Reveal button before reveal,
server's own unmasked response replacing the row and the exact `revealCustomerPhone(token, customerId,
"ConsoleBookings")` call asserted, and the masked value staying put with an error shown on failure.
Fails-before: reverting the `phone` column to `render: (row) => row.phone` (removing the `renderPhone`
call) failed all three new tests - no Reveal button rendered, `revealCustomerPhone` never called, and
the error-path assertion failed because the row had no Reveal button to click in the first place.

Verification in the `ago-console` worktree: `npm run typecheck` clean, `npm run lint` clean (0
warnings), `npm test` - 110 files, 1159 tests passed (was 1156 before this item's 3 new tests).
