# ADR-0084: A worker's schedule is a template of two kinds, and a cycle chooses days, not hours

- **Status**: Accepted
- **Date**: 2026-09-01
- **Stage**: 20 (`20-14`)

## Context

`WorkingHoursRule`'s own doc comment states its scope deliberately: "no RRULE, no interval, no
exceptions" — it can express only an ordinary week, keyed on `DayOfWeek`. That was the right shape for
`20-02`. It cannot express the two patterns the author named as real, current cases: **"2 через
2"** (two working days, two resting, cycling) and **"сутки через трое"** (one working day, three
resting). Neither has a `DayOfWeek` to key on — a cycle needs an anchor date, not a weekday.

`20-14` also had to answer where three numbers that were in the wrong place actually belong: slot
length (until now *derived* from the longest service a worker offers — `MaterializeAvailabilityHandler.SlotLengthFor`),
the buffer between slots (`BookingCalendar.BufferMinutes`, one number per **calendar**, shared by every
worker on it), and the materialisation horizon (`AvailabilityMaterializationJobOptions.HorizonDays`,
one number for the **whole deployment**). None of these are calendar-level or deployment-level facts —
they are facts about one worker's own schedule.

## Decision

**A new `WorkerSchedule` aggregate, one per worker, carries two mutually exclusive kinds.**

- **`Weekly`** — unchanged: read the worker's existing `WorkingHoursRule` rows, keyed on `DayOfWeek`,
  exactly as `20-02` always did. `WorkerSchedule` carries none of those hours itself, only the fact
  that weekly is the active kind, plus the numbers every kind needs.
- **`Cycle`** — `(AnchorDate, WorkingDays, RestDays, StartsAt, EndsAt)`. Whether a given business-local
  day is a working one is a pure function of `(anchor, workingDays, restDays, day)` —
  `CycleGrid.IsWorkingDay`, zero infrastructure dependency, the same reason `SlotGrid.Fill` already
  lives in Domain with none. **The cycle answers only "is this a working day", never "what hours does
  it have"** — the one pair of hours (`CycleStartsAt`/`CycleEndsAt`) applies to every working day the
  cycle produces, resolved exactly the way `WorkingHoursRule`'s own hours already are.

That single restriction is what dissolves the midnight problem `WorkingHoursRule`'s own doc comment
refuses to solve ("a shift crossing midnight is two rules, on two days"). "Сутки через трое" is `1`
working day in `4`, plus the worker's ordinary daytime hours — never a 24-hour bookable window. A
worker nominally "on duty overnight" still only sells the hours the shop states. Nothing in either
kind ever has to reason about a shift crossing midnight, because no kind ever generates one.

**Switching kind clears the other kind's own fields.** `ReconfigureWeekly`/`ReconfigureCycle` each null
out what the other kind uses, so a schedule can never carry stale cycle numbers behind a `Weekly` flag
or vice versa — a state a reader could otherwise misinterpret with no error to catch it.

**Slot length and buffer move to the schedule and become per-worker, explicit numbers the tenant
sets — not derived, not shared.** `SlotMinutes` replaces the longest-offered-service derivation;
`BufferMinutes` moves off `BookingCalendar` entirely (the property is deleted, not deprecated — a
"default for new workers" reading was rejected explicitly, since the same number living in two places
diverges over time); `HorizonDays` becomes per-worker, capped at 180 days (`WorkerSchedule.MaxHorizonDays`)
so a fat-fingered value cannot make the job cut a decade of slots for one worker on its very next run.

**`MaterializeFrom` — the forward-only cursor.** The materialisation job reads from
`max(today, MaterializeFrom)` to `today + HorizonDays`, then advances the cursor past what it cut.
`WorkerSchedule` itself refuses, as a Domain invariant, to let any caller move this cursor backwards —
`ValidateMaterializeFromNotRegressing`, checked by both `Reconfigure*` and the job's own `AdvanceCursor`,
throwing the same way `BookingCalendar.Reconfigure` already bounds its own buffer inline rather than
leaving the caller to remember. Moving the cursor backwards on purpose — a destructive re-cut — is a
different, later item's own entry point (`20-16`) and is deliberately unreachable from this one. This
is what keeps `adr/0053`'s insert-only promise for the background job intact: nothing this item builds
can delete a materialised row.

## Consequences

- **Positive**: a real gap in what a shop can describe about its own staffing is closed, without
  touching `SlotGrid`, `WorkingHoursRule`, or the exclusion constraint that guarantees no worker holds
  two overlapping events (`adr/0049`).
- **Positive**: the forward-only cursor is a single Domain-level guarantee every caller gets for free,
  rather than a convention each of two write paths (the console's save, the job's own advance) would
  otherwise have to remember independently.
- **Negative, named plainly**: a schedule change does not retroactively affect days already
  materialised — a tenant who fixes their hours sees nothing change for as long as 180 days, until
  something moves `MaterializeFrom` backwards. That something is `20-16`, not yet built at the time
  this ADR is accepted; until it ships, the gap is real and a tenant will notice it.
- **Negative**: an existing `WorkingHoursRule` for a day that already fell inside a previously-cut
  window is not backfilled once the cursor has passed it — the job only ever looks forward, never
  rescans.
- **Migration cost, honestly stated**: every worker who had a bookable slot before this item (a
  `WorkingHoursRule` row and at least one offered service) gets a backfilled `Weekly` schedule, with
  `BufferMinutes` copied from their calendar's old value and `SlotMinutes` recomputed by the identical
  longest-offered-service rule the handler used to apply inline — so the very next materialisation run
  after this migration produces the same grid the one before it did. A worker satisfying neither
  condition gets no schedule, on the stated principle that writing one would invent a fact rather than
  preserve one.

## Alternatives considered

- **A general recurrence language (RRULE or similar)** instead of one named cycle shape. Rejected:
  `WorkingHoursRule`'s own doc comment already rejected this once, for the same reason repeated here —
  a rule that expresses less is a rule the materialiser cannot misinterpret, and the two concrete cases
  named (2/2, 1/4) are both covered by the one shape actually built.
- **Cycle carrying its own hours per working day**, allowing different hours on different cycle days.
  Rejected as unrequested scope: the two named cases both want one uniform window, and the complexity
  of a per-day override was not worth building against a hypothetical.
- **Fields on `Worker` instead of a separate aggregate.** Rejected: the schedule is the materialiser's
  own input and carries a cursor the background job writes on every run; folding it into `Worker` would
  make `20-13`'s CRUD screen save a column the job owns, and every rename would touch the row the job
  reads.
