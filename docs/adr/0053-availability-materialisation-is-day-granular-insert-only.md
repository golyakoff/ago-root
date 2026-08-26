# ADR-0053: Availability materialisation is day-granular and insert-only

- **Status**: Accepted
- **Date**: 2026-08-26
- **Stage**: 20 (`backlog/20-02-availability-materialization-and-manual-editing.md`)
- **Refines**: `adr/0049` (supersedes one of its consequences — see below)

## Context

`adr/0049` decided that a bookable slot is a real `events` row written ahead of time, and that the
no-overlap guarantee lives in a GiST exclusion constraint. It left the generating job to `20-02`, and
it named one method as the way the job would know where to resume: `GetMaterializedHorizonAsync`,
returning the latest `ends_at` among rows that still occupy the worker.

Building the job showed that method is the wrong question, because of the feature it sits next to.
The product spec deliberately has **no declarative exception model** for recurring schedules: a tenant
who is closed next Tuesday edits Tuesday's generated rows directly. So the job and the tenant write to
the same table, and the job has to be safe to re-run over days the tenant has already changed — and
over days a customer has already booked.

That is not one requirement but three, and they are easy to conflate:

1. **Re-running must not duplicate.** Two runs over the same window produce one set of rows.
2. **Re-running must not destroy.** A row that has moved past `Available`, and a day a human edited,
   survive every subsequent run untouched.
3. **Two `Ago.Calendar.Worker` replicas must not collide.** Neither may fail, and neither may produce
   a duplicate, when both find the same empty day at the same instant.

`6-09`/`6-10` in AGO Chat are the standing reminder of how requirement 3 is usually got wrong: a read
that decides what to write, with a window between them.

## Decision

**Materialisation is day-granular, insert-only, and coordinated by the database alone.**

### The unit is the business-local day, not an instant

The job asks `ListMaterializedLocalDatesAsync(calendar, worker, from, to)` — which local days in the
window already hold at least one `events` row — and generates only for the days not in that set. This
replaces `GetMaterializedHorizonAsync`, which is removed rather than left with no caller.

An instant-valued horizon can only describe a *prefix*: "materialised up to here". Manual editing
punches holes in the middle of the window, and a prefix cannot express a hole. The unit the
non-destructive rule operates in is the day, so the question the port asks has to be about days.

**Every status counts, cancelled included.** This inverts `adr/0049`'s own consequence, and the
inversion is the point: with an instant-valued horizon the question was "how far does this worker's
occupied time reach", and a cancellation frees the worker's time, so a cancelled row was not evidence.
With a day-valued check the question is "was this day generated", and a cancelled row is perfect
evidence that it was. Counting it is what stops the job writing a fresh grid on top of a day's own
history.

### The invariant, stated so that it needs no bookkeeping

> The job only ever inserts rows into business-local days that have no event row at all. It never
> updates, never deletes, and never regenerates a day it has already generated.

Everything `20-02` promises reduces to that one sentence. A booked slot survives because its day is
skipped. A hand-edited day survives for exactly the same reason. **Nothing marks an edited day as
edited** — there is no `is_manually_edited` column, no exception table, no "last generated" watermark
to keep in sync. The absence of a mechanism is the mechanism, and it is why the rule is phrased as
"the job only fills empty days" rather than "the job avoids edited days", which would need a way to
know which those are.

### A day off is a row, not an absence

`DeleteDayOffHandler` deletes the day's unclaimed rows and writes one `Blocked` event spanning what it
replaced. Deleting them and leaving the day empty would be undone by the very next run — the tenant's
"I am closed next Tuesday" would hold until the small hours and then quietly reverse itself.

The blocking row is not a marker invented to defeat the job. It is the literal truth (this worker is
unavailable for this time), it is what `Event.BlockOut` already existed for, and it participates in
`ex_events_worker_no_overlap`, so nothing can be materialised or booked across it even if the
day-level check were somehow bypassed.

`EditDayBoundaryHandler` may replace `Blocked` rows as well as `Available` ones, which makes it the
only way v1 offers to undo a day off. That is safe because a `Blocked` row has no customer attached by
construction: neither `Event.Block` nor `Event.BlockOut` ever sets one.

### The write is one statement, and the constraint is the only arbiter

```sql
INSERT INTO events (...)
SELECT * FROM unnest(@ids::uuid[], ...)
ON CONFLICT DO NOTHING
```

`ON CONFLICT DO NOTHING` with **no conflict target** covers every usable constraint on the table —
including the GiST exclusion constraint, not only the primary key. Two replicas that both find the
same empty day both succeed: the loser's rows are dropped, its transaction is not aborted, and no
exception is raised for an outcome that is not exceptional.

The day-set query is therefore an *optimisation*, not the guarantee. No read decides what this
statement writes; there is no check-then-act to lose.

The job holds no lease, takes no advisory lock and elects no leader. Coordination would add a
component that can fail to a job whose only failure mode is already handled by a constraint that
cannot.

### Manual edits are day-scoped rewrites guarded by the `DELETE`'s own `WHERE`

Both edit handlers go through one transaction: `DELETE ... WHERE ... status IN ('Available',
'Blocked')`, then insert the replacements. A claimed row is **not addressable** by that statement, so
no edit — and no bug in a caller — can delete a booking. A caller whose pre-read was overtaken by a
customer does not delete that customer's row; its replacements then overlap the survivor, the
exclusion constraint refuses the whole transaction, and the caller gets `SlotOverlapException`. The
pre-read exists only so that the ordinary case gets "cancel the booking first" instead of a constraint
violation.

### Slot length is the worker's longest offered service

A slot exists before anybody has chosen a service for it (`events.service_id` is null until the
claim), so its length must be one every service the worker performs fits inside. The shortest would
publish 15-minute slots a 45-minute haircut can never be booked into. The cost is real and stated
rather than hidden: a worker offering a 15-minute and a 90-minute service publishes 90-minute slots.
The fix is a per-service grid, which is a different data model — a slot would stop being one row with
one status — and is not what this item is for.

## Consequences

- **`GetMaterializedHorizonAsync` is gone**, and with it `adr/0049`'s consequence bullet requiring it
  to skip cancelled rows. The replacement carries a strictly stronger test: the day set is asserted to
  include a cancelled row's day, to exclude days outside the window, and to be served by
  `ix_events_worker_day` per `EXPLAIN`.
- **A new non-partial index**, `ix_events_worker_day` on `(calendar_id, worker_id, local_date)`. Its
  reason for not being partial is the rule above: a filter on `status` would hide exactly the rows
  whose presence is the decision.
- **A cancelled slot is never re-offered.** A day with seven `Available` rows and one `Cancelled` one
  is skipped, so the cancelled slot's time stays unbookable. This is consistent with `adr/0049`'s
  deliberate absence of any transition back to `Available`, and it is `20-04`'s decision to make, not
  a gap to paper over here.
- **A day off cannot be declared past the horizon.** With no row to leave behind there is nothing to
  stop the next run filling the day in, so `DeleteDayOffHandler` refuses rather than succeeding
  falsely. Pre-declaring a closure further out needs a durable statement the materialiser reads, which
  is new scope.
- **A widened horizon is not reclaimed by narrowing it.** The job never deletes, so days generated
  under a larger `HorizonDays` stay.
- **Wall clock becomes an instant in exactly one place**, and it is now enforceable rather than
  documented: `Ago.Calendar.Infrastructure.Time` exists as its own assembly so that an architecture
  test can assert `System.TimeZoneInfo` is referenced by exactly one product assembly. That assembly
  boundary is most of the reason the project exists — a static helper in Application would have been
  cheaper to write and impossible to police.
- **The resolver returns UTC**, not the zone's own offset (CLAUDE.md rule 11). Two representations of
  one instant circulating — `-05:00` from the resolver, `+00:00` read back from `timestamptz` — is the
  ambiguity this time model exists to remove, and Npgsql refuses any other offset for a `timestamptz`
  parameter anyway.
- **Postgres-specific, for the Stage 9 list**: `ON CONFLICT DO NOTHING` against an *exclusion*
  constraint has no MySQL equivalent, which is the same friction `ex_events_worker_no_overlap` already
  put on that list rather than a new one.

## Alternatives considered

- **Regenerate the whole window every run, upserting.** Rejected outright. It makes every run a
  potential destroyer of bookings and the safety of the job becomes a property of how carefully its
  `WHERE` clauses were written, re-checked on every future edit. Insert-only means the job has no
  statement that *can* destroy anything.
- **Keep an instant-valued horizon and rely on nothing ever leaving a hole.** Genuinely tempting,
  because with the blocking-row design above no hole can occur. Rejected because that is a
  documented-but-fragile convention: it is correct only as long as every future writer remembers to
  leave a tombstone, and the failure would be silent slots reappearing on a day a tenant closed.
- **Mark manually edited days with a column or a `schedule_exceptions` table.** Rejected. It is a
  second source of truth beside the rows, it is exactly the declarative exception model the product
  spec replaced with direct editing, and it needs the job to consult it correctly forever. The
  day-granular rule needs no such column and cannot get it wrong.
- **A distributed lock or leader election so only one replica materialises.** Rejected: it adds a
  component that can fail (a lease that expires mid-run, a lock nobody releases after a crash) to
  guard against an outcome the exclusion constraint already makes impossible. `4-03` measured the
  Redis-lock alternative against `SKIP LOCKED` in AGO Chat and the cheaper mechanism won there too.
- **`AddRange` + `SaveChanges` and catch the overlap violation.** Rejected. It is control flow by
  exception for the *expected* outcome of two replicas doing their job, it rolls a whole day's batch
  back rather than dropping the rows that collided, and it forces every caller to distinguish "I lost
  a harmless race" from "something is wrong" — a distinction the count returned by
  `ON CONFLICT DO NOTHING` makes for free.
- **Delete a day's rows and leave the day empty for a day off.** Rejected: the next run refills it.
  This is the single decision that makes manual editing durable, and the naive version of it is the
  bug the item's own done-when demands a test for.
- **Nudge only the first and last event when a day's boundary moves.** Rejected. It produces a grid
  that is no longer a grid — a first slot of a different length to its neighbours, and a lengthened day
  with a gap where a buffer should be. Rebuilding the day from the same `SlotGrid` the materialiser
  uses means a hand-edited Tuesday and a generated Wednesday are the same shape, buffer included.
