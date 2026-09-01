# Re-cutting an already-materialised horizon

- **Stage**: 20
- **Status**: ready
- **Depends on**: `20-14-worker-schedule-template.md` — the cursor this moves backwards, and the
  template whose change makes moving it necessary.

## Why this, and why now

`20-14`'s cursor only ever moves forward, which means a tenant who fixes their schedule sees **nothing
change for as long as the horizon is already cut** — up to 180 days. They will file that as a bug, and
they will be right to.

The author's own resolution: the "materialise from" date is public and editable. Move it back to
tomorrow, and the days between are regenerated from the new template. That gives the product a
property worth naming out loud — **the background job never destroys anything, and destruction only
ever happens because a human asked for it, by name, having been shown what they would lose.**

## What already exists, checked before scoping the rest

- `MaterializeAvailabilityHandler` is strictly insert-only, and skips any business-local day holding
  any event row (`adr/0053`). That stays true: this item does not change the job.
- `adr/0049`'s exclusion constraint physically refuses overlapping event rows for one worker. That is
  not a preference this item can design around — see the day-skipping decision below.
- `20-02` already built two manual day-level edits (`DeleteDayOffHandler`, `EditDayBoundaryHandler`)
  and both **refuse a day that has bookings**, returning `availability.day_has_bookings`. This item is
  the same problem one level up, and the first place that offers a way *through* the refusal rather
  than around it.
- A real cancellation path exists — `CancelBookingHandler`, `POST /bookings/{id}/cancel`, with a
  `CancellationReason` — so a booking this item ends is cancelled properly, not deleted behind the
  customer's back.

## Decided (ADR-0085): the job stays insert-only; re-cutting is an explicit human action

`adr/0053` said materialisation is insert-only. That remains true of the thing it was said about — the
background job. What this item adds is a second, manual entry point that deletes, and ADR-0085 records
why the distinction is real rather than a loophole: the job runs unattended on a timer against every
calendar, so a destructive job is a destructive surprise; this runs once, for one worker, from a
console screen, after showing the operator exactly what disappears.

## Decided: a day whose booking is kept is not re-cut at all

The tenant chooses **per booking** — cancel it, or keep it. "Keep" means the *whole day* stays in the
old grid, untouched.

That is not a preference, it is the exclusion constraint. A kept 12:30–13:30 booking and a new
12:00–14:00 slot overlap, and Postgres refuses the insert. The only alternative would be re-cutting
around the kept booking, leaving a day that is half one grid and half another with a hole between —
harder to explain to the operator looking at it than "this day kept its old schedule because it had a
booking on it".

## Decided: the preview's world is re-checked inside the transaction

A booking can land between the operator reading the preview and pressing confirm — the public widget
never stops taking bookings. If the set of bookings in range differs from what the request accounted
for, the whole operation is **refused** and the operator is sent back to a fresh preview. Refusing is
the only honest option: applying decisions to a booking the human never saw is exactly the silent loss
this item is built to prevent.

## Scope

- `POST /workers/{workerId}/schedule/recut/preview` with a `from` date → per affected business-local
  day: the date, how many `Available` slots would be deleted, and every booking on it (id, local time,
  status, service, and — gated on `CustomerRead` per `20-12` — the customer's name and phone).
- `POST /workers/{workerId}/schedule/recut` with the `from` date and an explicit per-booking decision
  (`cancel` | `keep`), plus whatever token or booking-set fingerprint the preview returned, so the
  staleness check above has something to compare.
- Behaviour per day, in one transaction: no bookings → cleared and re-cut; every booking cancelled →
  cleared and re-cut; any booking kept → skipped whole, left in the old grid.
- Cancellation goes through the existing cancellation use case, so the customer is told; `Booked` and
  `PendingConfirmation` rows are never deleted by any path in this item.
- The cursor is set to `from` and the re-cut runs immediately rather than waiting for the job's next
  tick — the operator pressed a button and must see the result.
- Console: the preview screen with a per-booking control, and a confirmation that names the counts.
- **ADR-0085.**

## Out of scope

- Moving a booking into the new grid instead of cancelling it — `20-17`, deferred by the author.
- Re-cutting across several workers at once. One worker, one operation; a tenant with ten workers who
  changed everything presses the button ten times, and that is an acceptable price for an operation
  this destructive.
- Anything before `from`, and anything past the worker's horizon.
- Changing what the background job does.

## Done when

- [ ] Days with no bookings in the re-cut range are cleared and regenerated from the current template,
      proven by a test where the template changed between the two cuts.
- [ ] A day whose booking the operator kept is left entirely in the old grid, and the response says
      which days those were.
- [ ] A booking the operator chose to cancel is cancelled through the ordinary cancellation path — its
      row still exists, with a cancellation reason — and is not deleted.
- [ ] A booking created between preview and confirm causes the whole operation to be refused, proven
      by a test that inserts one in between.
- [ ] Nothing outside `[from, horizon]` for that worker is touched, proven by a test with a second
      worker on the same calendar whose slots must survive untouched.
- [ ] No path in this item deletes a `Booked`, `PendingConfirmation` or `NoShow` row.

## Open questions

- **What the staleness check compares.** A fingerprint over the booking ids and statuses in range is
  the cheap version; a per-booking version number is the precise one. The cheap version can refuse
  spuriously when an unrelated booking in range merely changed status, which for an operation this
  rare is a fine trade — but decide it deliberately rather than by accident.
