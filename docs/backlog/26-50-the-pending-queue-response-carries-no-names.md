# 26-50 · The pending-queue response carries no names at all

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, reading `ago-calendar/src/Ago.Calendar.Contracts/ConsoleContracts.cs` against
  `ago-console/src/api/calendarApi.ts` — the gap the approved mockup Artifact ("AGO Chat для Android",
  `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`) §04 named while it was being drawn, and which
  `ago-android/docs/scope-inventory.md:82` recorded as owing its own item.

## Found

The screen where a human has seconds to decide has no words on it, and the screen where there is
nothing left to decide has all of them.

`PendingBookingResponse` carries `WorkerId`, `ServiceId` and `CalendarId` — three GUIDs and not one
name. `ConfirmedBookingResponse`, its own sibling in the same file, carries `WorkerDisplayName`,
`ServiceName` **and** `CustomerDisplayName`. So the console's `/calendar/waiting` renders a table whose
"what" and "who" columns are eight hex characters, while `/calendar/bookings` — the already-settled
list — reads in plain Russian. An operator deciding whether to veto «Окрашивание · 180 мин» in the
next twenty-six hours is shown `cal a0f3c952` instead.

This is not an Android item wearing a backend hat. It is wrong in the console today, for the same
reason, on the same screen; Android is simply where it became impossible to keep ignoring, because a
card has room for words and a table column trains you not to expect any.

## What is actually true today, confirmed against real code

- `ago-calendar/src/Ago.Calendar.Contracts/ConsoleContracts.cs:134-146`:

  ```csharp
  public sealed record PendingBookingResponse(
      Guid BookingId, Guid CalendarId, Guid WorkerId, Guid ServiceId, Guid CustomerId,
      DateTimeOffset StartsAt, DateTimeOffset EndsAt, DateOnly LocalDate,
      DateTimeOffset ConfirmationDeadline, bool IsOverdue, string? Phone, bool Masked);
  ```

- The sibling that already has them is in the same file, and its own XML remarks state the gating rule
  this item has to respect, unprompted (`ConsoleContracts.cs:186-194`): **`WorkerDisplayName` is
  "never gated — a worker's own name is the shop's own roster, not personal data about a customer",
  and `ServiceName` likewise. `CustomerDisplayName` is different**, and that file says so: the
  confirmed-bookings response may carry it only because "every row on this screen already passed
  `customer:read`".
- The pending queue deliberately does **not** require `customer:read`. `Phone` is `string?` for
  exactly that reason (`calendarApi.ts:189-196`: `null` means "this operator does not hold
  `customer:read`", never "no phone recorded"), and `CalendarQueuePage.tsx:70` admits an operator
  holding only a booking-action permission.
- The console's mirror: `calendarApi.ts:175-202` (`PendingBooking`) against `:216-233`
  (`ConfirmedBooking`).

## Scope

One promise: **a pending booking says what it is and who it is with.**

1. `PendingBookingResponse` grows `WorkerDisplayName` and `ServiceName`, both **ungated** — the same
   reasoning `ConfirmedBookingResponse`'s own remarks already state for those two fields, restated on
   this record rather than left to be inferred from the other one.
2. It grows `CustomerDisplayName` **gated exactly the way `Phone` already is** — populated only for a
   caller holding `customer:read`, `null` otherwise, and `null` for a customer who has never had a
   name recorded. The read store is where that decision is made, once, beside the existing `Phone`
   decision; never a second gate invented in the endpoint or the handler.
3. The read store's query grows the joins, and the existing "contact-free row" path keeps working —
   an operator with no `customer:read` still sees the queue, now with the service and the worker named
   and the customer still withheld.
4. `ago-console`'s `PendingBooking` interface and `CalendarQueuePage`'s own columns take the new
   fields; the `.ago-mono` short id stays as the fallback for a row whose name is genuinely absent,
   never as the default.

## Out of scope

- **`CalendarId`'s own name.** The mockup draws `cal a0f3c952` deliberately and the caption keeps it —
  one queue spans every calendar, and the calendar is context rather than the answer. Naming it is a
  separate judgement nobody has asked for.
- **The Android screen.** `26-48` renders whatever this response carries; it is written to render short
  ids honestly until this lands and needs no change when it does beyond using the new fields.
- Any change to who may see the pending queue. The gate is `23-57`'s and stays exactly as it is.

## Done when

- [ ] A caller holding only `booking:reject` reads the pending queue and gets the service and worker
      names, and `customerDisplayName: null`.
- [ ] A caller holding `customer:read` additionally gets the customer's name when one is recorded.
- [ ] An integration test covers both callers against the same booking and asserts the difference is
      exactly the customer field.
- [ ] `ago-console`'s `/calendar/waiting` shows the names, with the short id surviving only as the
      no-name fallback.
- [ ] `dotnet format Ago.Calendar.slnx --verify-no-changes`, `dotnet build`, `dotnet test` green in
      `ago-calendar`; `npm run typecheck && npm run lint && npm run test && npm run ux-gate` green in
      `ago-console`.
