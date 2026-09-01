# ADR-0086: The booking claim generalises from one row to a claimed set

- **Status**: Accepted
- **Date**: 2026-09-01
- **Stage**: 20 (`20-18`)
- **Amends**: `adr/0059` (the booking claim is a compare-and-set)

## Context

`20-14` made a worker's slot length an explicit tenant-set number instead of deriving it from the
longest offered service, which broke an implicit guarantee: a service longer than one slot could not
be booked at all. `20-18` removes that stopgap — such a service is claimed as several consecutive
slots, atomically, as one booking.

## Decision

`adr/0059`'s whole argument survives unchanged; only the shape of what is compared-and-set widens from
one row to a set.

```sql
UPDATE events
SET status = 'PendingConfirmation', customer_id = @customerId, service_id = @serviceId,
    confirmation_deadline = @deadline, booking_id = @bookingId
WHERE id = ANY(@eventIds) AND calendar_id = @calendarId
  AND status = 'Available' AND starts_at > @now
RETURNING id, worker_id, starts_at, ends_at, local_date
```

Still one statement, still Postgres as the sole arbiter, still no lock invented over an interval — it
now arbitrates a set instead of a singleton. The verdict is still the rows-affected count, generalised
from "1 or 0" to "equal the run's own length or not": two customers racing for overlapping runs cannot
both win, because at least one shared row can only be updated once, and a partial match rolls the whole
transaction back — a run is claimed whole or not at all, so a torn claim (some slots taken, some not)
can never be observed.

**Data model**: `events.booking_id`, nullable, self-referencing (another event row's own id — the
run's anchor, its own id for a single-slot booking). Not a second `bookings` table: a booking carries
no state its member rows do not already carry identically.

**"Consecutive" is computed server-side** (`ConsecutiveRunFinder`, in Domain — pure, no I/O), walking
a worker's own day in start order from the chosen slot, requiring each next row to begin exactly at the
previous row's end plus the worker's buffer. Never trusted from the client — a client that could name
three arbitrary event ids could otherwise claim three unrelated times as one booking.

**Operator-driven transitions widen the same way, staying on the load-mutate-save path `adr/0059`
already reserved for them.** `Cancel`/`Reject`/`MarkNoShow` now resolve the whole group via
`IEventRepository.ListByBookingIdAsync` and save it in one `SaveRangeAsync` call — EF's own implicit
transaction is the atomicity guarantee, no explicit `BeginTransaction` needed, matching `adr/0059`'s own
"uncontended single-actor writes" characterisation of this path.

**The confirmation sweep's claim is now two statements, not one, and still uses `SKIP LOCKED` — on the
anchor row only.** A plain `SKIP LOCKED` over every row of a multi-row booking would let two
`Ago.Calendar.Worker` replicas each lock a *different* row of the *same* run. Locking one representative
row per booking first (`WHERE id = booking_id`) closes that window: of two replicas racing one booking,
exactly one locks its anchor and the other skips it entirely, never reaching that booking's siblings.
Only the winner's own second statement (`WHERE booking_id = ANY(@won)`, plain `FOR UPDATE`) touches the
rest of the group — safe against other sweep replicas by construction, and merely serialises (rather
than races) against a concurrent operator transaction on the same booking, an acceptable trade for a
background tick that the customer-facing claim path never makes.

## Consequences

- `BookingAttempt`/`BookingConfirmation` carry `EventIds`/`BookingId` instead of a single `EventId`;
  `BookingConfirmedResponse`'s own `BookingId` field is unchanged in shape (still the customer's one
  quotable id — now the run's anchor).
- The sweep's batch size now bounds *bookings* claimed per tick, not *event rows* — the correct unit,
  since a booking's rows must be confirmed together.
- One `BookingConfirmed` message per booking, not per slot, carrying the run's own whole span.
- One migration backfills `booking_id = id` for every row a claim already touched
  (`customer_id IS NOT NULL`), so pre-`20-18` data groups correctly rather than reading as "ungrouped".

## Alternatives considered

- **A separate `bookings` table.** Rejected: a second aggregate, a bigger migration, and a second
  place for tenant isolation to be got wrong, for state the member rows already carry identically.
- **A freshly minted booking id** (`Guid` via `IIdGenerator`). Rejected: the anchor's own id already
  uniquely identifies the run in start order; minting a second id would add a type with no behaviour
  the anchor's id doesn't already have.
- **Plain `FOR UPDATE` (no `SKIP LOCKED`) for the sweep's whole claim.** Considered, since it would
  need no anchor-first split. Rejected: it would reintroduce cross-replica blocking the sweep's own
  `SKIP LOCKED` was built to avoid, and a pre-existing liveness test already holds that property
  (`ASweeperThatFindsEverythingLocked_ReturnsZeroRatherThanBlocking`).
