# The materialised slot view: what the tenant's schedule actually produced

- **Stage**: 20
- **Status**: ready
- **Depends on**: `20-13-worker-card-and-list.md` — the card this is reached from.
  `20-12-permissioned-contact-visibility-and-tenant-contacts-report.md` (done) — the permission gate
  this reuses rather than works around.

## Why this, and why now

A tenant configures working hours and then has no way to see what came out. The materialiser runs in
`Ago.Calendar.Worker` on a timer; the only surface that shows its output is the **public booking
widget**, which shows a customer's view of free time — not the tenant's view of their own week, and
not booked or cancelled slots at all. Today the honest answer to "did my schedule come out right" is
"open the widget and count".

Deliberately the plainest possible screen: a table of date, weekday, time, status, and who holds it.
No calendar grid, no drag-and-drop. That matches `18-08`'s own restraint for the analytics report,
and it is what makes this item small enough to sit between two large ones.

## What already exists, checked before scoping the rest

- `Event` carries everything the table needs: `LocalDate`, `StartsAt`/`EndsAt`, `Status`,
  `CustomerId`, `ServiceId`, `WorkerId`.
- `PendingBookingReadStore` (`20-04`, widened by `20-12`) is the closest structural precedent: a
  Dapper read store, permission-gated, with **two separate SQL constants** — one that joins
  `customers` and one that does not — rather than one query that always joins and then masks. That
  shape is the reason `20-12` could claim a caller without the permission never reads the data at
  all, and this item copies it rather than inventing a third approach.
- No read store today returns slots by worker and date range. `IBookingSurfaceReadStore` returns the
  public view: free slots only, for a published calendar.

## Decided: gated on `CalendarConfigure`, with the contact column additionally on `CustomerRead`

The screen is a configuration screen — it exists so whoever sets schedules can check them — so
`Permission.CalendarConfigure` gates the screen itself.

The contact column gets `20-12`'s own gate on top. The author's intent was "the owner works on this
screen and sees everything", and **that already happens with no special case**: by `adr/0083` the
tenant's account owner cannot fail to hold a role granting `CustomerRead`, because `Operator.Grant`
and `Operator.Revoke` refuse to produce that state. So the owner passes both gates by construction.

What the second gate buys is the case the first one misses: an operator deliberately given a
config-but-no-contacts role would otherwise read here the phone numbers `20-12` withheld from them one
screen away, and the narrower role would become decoration. A screen that quietly bypasses a
permission is worse than one that never had it.

## Scope

- `IWorkerSlotReadStore` in `Application/Abstractions` with its Dapper adapter, following
  `PendingBookingReadStore`'s two-constants shape: the unpermitted query does not join `customers`,
  and selects a literal null for the contact columns so both variants materialise the same row shape.
  *(`20-12` learned that last part the hard way — a record's default parameter value does not give
  Dapper a second constructor.)*
- `GET /workers/{workerId}/slots?from=&to=`, gated on `CalendarConfigure`, tenant-isolated, returning
  per slot: business-local date, weekday, local start and end, status, service name where chosen, and
  — when permitted — the customer's display name and phone.
- A console screen reached from the worker row and the worker card, rendering one table. The withheld
  contact renders as an honest `hidden` with a title explaining why, exactly as `QueuePage.tsx`
  already does — never a blank cell indistinguishable from "nobody booked this".

## Out of scope

- Editing anything from this screen. Day-off and day-boundary edits already have their own surface
  (`AvailabilityPage`), and re-cutting is `20-16`.
- A calendar/grid visualisation.
- Any aggregate or count. This is a list of rows, not a report.
- Cross-worker views. One worker at a time, reached from that worker.

## Done when

- [ ] The table shows a worker's slots over a date range with date, weekday, local time and status.
- [ ] An occupied slot shows the customer's name and phone to a caller holding `CustomerRead`, and
      `hidden` to one without — on identical underlying data, proven by a test.
- [ ] The unpermitted query genuinely does not read `customers` — proven by a test whose fixture puts
      a customer row in place that must not appear in the response.
- [ ] Another tenant's worker returns not-found rather than an empty list, proven by a test.
- [ ] The console reaches the screen from both the worker list row and the worker card.

## Open questions

- **The default date range.** Today through the worker's own horizon is the most informative and can
  be 180 rows per worker; today through +14 is the readable default. Leaning to +14 with the range
  editable, but decide when implementing.
- **Whether past days are shown at all.** They answer "who came last Tuesday", which is arguably the
  contacts report's job (`20-12`), not this screen's.
