# AGO Calendar: availability materialization and manual editing

- **Stage**: 20
- **Status**: ready
- **Depends on**: `20-01-domain-model-and-persistence.md`

## Goal

`Event` rows in `Available` status exist in the database ahead of any real booking, generated from
each `(Worker, Calendar)` pair's `WorkingHoursRule` out to a rolling horizon, spaced by the owning
`Calendar`'s `BufferMinutes`. A tenant can also directly edit already-materialized future days — delete
a day's `Available` events (a day off), or shorten/lengthen a day by editing its boundary events —
without those edits being silently overwritten the next time materialization runs. After this item,
`20-03`'s booking claim has real rows to claim against, and a tenant has a real way to say "I'm closed
next Tuesday" without inventing a declarative exception model for the recurring rule.

## Context to read first

The product spec's own reasoning for why materialization exists at all, in full — the considered and
rejected alternative (computing available slots on the fly from the schedule minus existing bookings,
locking a computed interval instead of a real row) and why it loses: materialized rows give the
booking claim (`20-03`) a single source of truth to compare-and-set against, the same reasoning
`data-model.md` already used once for `active_chats` being a real column rather than a derived value.
Restate this reasoning in the response when this item is implemented — teaching mode
(`CLAUDE.md`) — rather than treating "materialize in advance" as an unexplained given.
`docs/architecture/concurrency.md`'s "Rules for every async code path" — this item's own materialization
job is a `BackgroundService`/`PeriodicTimer` loop in `Ago.Calendar.Worker`, following
`PartitionMaintenanceJob`'s exact shape (`data-model.md`, `2-06`): idempotent by construction via
`INSERT ... ON CONFLICT DO NOTHING` (or an equivalent existence check) per day, safe under a missed run
or two `Worker` replicas racing to materialize the same day. `docs/architecture/db-migration` skill and
`20-01`'s own `WorkingHoursRule`/`Event` shapes.

## Scope

- A `Worker`/`Application` job (`AvailabilityMaterializationJob`, `Ago.Calendar.Worker`,
  `PeriodicTimer`, daily — the exact cadence is an implementation parameter, not measured or claimed as
  a number, matching `PartitionMaintenanceJob`'s own "daily, unmeasured starting point" precedent) that,
  per `(Worker, Calendar)` pair with an active `WorkingHoursRule`, ensures `Available` `Event` rows
  exist out to a rolling horizon (a configurable day count — **do not invent a specific number**; state
  it as a named, documented configuration value with no claimed-optimal default, the same "hardcode a
  sane unmeasured starting point" precedent `3-05`'s rate-limit buckets already established). Adjacent
  events within one day are spaced by the owning `Calendar.BufferMinutes`.
- **Idempotent and non-destructive by construction**: materializing day N twice must not duplicate
  rows, and must never touch a day's events that already exist and have moved past `Available` (a
  `PendingConfirmation`/`Booked`/`Cancelled`/`NoShow` event from a prior run is never regenerated or
  overwritten) or that the tenant has manually edited (below) — the job only ever inserts rows for days
  that do not yet have any materialized events at all, extending the horizon forward, never rewriting
  what is already there. State this rule explicitly in the job's own code, since it is the mechanism
  that makes manual editing safe rather than a documented-but-fragile convention.
- Tenant-facing manual editing, as real use cases (`Ago.Calendar.Application.UseCases`):
  `DeleteDayOffHandler` (deletes every `Available` event for a given worker/calendar/day — rejects if
  any event that day is already `PendingConfirmation`/`Booked`, since deleting a claimed slot out from
  under a real booking is a different, unbuilt operation, not silently allowed here) and
  `EditDayBoundaryHandler` (adjusts a day's first/last `Available` event start/end, regenerating the
  buffered set for just that day). Both operate only on `Available` rows for exactly the reason above.
- `data-model.md` (or `ago-calendar`'s own copy, per `20-01`'s open item on where this lives) gains the
  materialization job's shape and the "never overwrites a manually-edited or claimed day" invariant,
  matching how `2-06`'s own `PartitionMaintenanceJob` is documented.

## Out of scope

- The booking claim itself (`Available → PendingConfirmation`) — `20-03`.
- Any UI for day-off/boundary editing — `20-06`; this item builds the handlers only.
- Widening the horizon dynamically based on real booking demand, or any other materialization
  optimisation — the rolling horizon is a fixed configuration value in v1, not an adaptive one.

## Done when

- [ ] `Ago.Calendar.Integration.Tests`: running the materialization job twice against the same
      `WorkingHoursRule` produces exactly the same set of `Available` events the second time (no
      duplicates), against a real Postgres.
- [ ] A test proves the non-destructive rule directly: claim one event (`Event.Claim`, from `20-01`'s
      own domain method, called without going through the full `20-03` handler since that item does
      not exist yet at this point in the sequence — state explicitly how this test constructs that
      precondition), run materialization again, and assert the claimed event's status is untouched and
      no duplicate `Available` row was created for its slot.
- [ ] `DeleteDayOffHandler`/`EditDayBoundaryHandler` each have a positive test (the edit sticks) and a
      negative test (rejected when the day already has a non-`Available` event), and a further test
      proving a subsequent materialization run does not resurrect a deleted day-off's events.
- [ ] `Ago.Calendar.Concurrency.Tests` (or wherever this repository's own concurrency-test project ends
      up living, matching `Ago.Chat.Concurrency.Tests`' precedent): two concurrent materialization job
      runs (simulating two `Worker` replicas racing the same day) do not produce duplicate `Available`
      rows — proven under real concurrency, not sequential awaits, the same bar `WaitingConversationClaimQuery`
      was held to.

## Open questions

None — the "materialize in advance, never overwrite a claimed or manually-edited day" design is fixed
by the product spec; the rolling-horizon day count is deliberately left as an unmeasured configuration
value rather than a genuine open question, per `CLAUDE.md`'s own instruction against inventing a number
this item has no basis to claim as correct.
