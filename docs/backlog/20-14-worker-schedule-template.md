# The worker's schedule template: cycle patterns, explicit slot and buffer, per-worker horizon

- **Stage**: 20
- **Status**: ready
- **Depends on**: `20-13-worker-card-and-list.md` — the card this adds a section to.
  `20-02-availability-materialization-and-manual-editing.md` (done) — the materialiser this changes
  the inputs of.

## Why this, and why now

`WorkingHoursRule` expresses "an ordinary week" and deliberately nothing else — its own doc comment
says so: *no RRULE, no interval, no exceptions*. That was right for `20-02`. It means a shop running
**"2 через 2"** or **"сутки через трое"** — the author's own two named cases — cannot be described at
all, because the rule is keyed on `DayOfWeek` and a cycle needs an anchor date instead.

Three more numbers a tenant must control are out of reach today: slot length is *derived* from the
longest service the worker offers, the buffer between slots is per **calendar**, and the
materialisation horizon is a single deployment-wide `HorizonDays = 30`.

## What already exists, checked before scoping the rest

- `SlotGrid.Fill(window, slotLength, buffer)` **already produces exactly the cutting the spec asks
  about** — 12:00–18:00 at a two-hour slot gives 12–14, 14–16, 16–18, with a partial tail dropped —
  on instants, DST-correct by construction. This item does not change it, only what feeds it.
- `MaterializeAvailabilityHandler.SlotLengthFor` takes the **longest** service the worker offers, with
  a doc comment already naming the cost of that choice.
- `BookingCalendar.BufferMinutes`, per calendar, read once per materialisation run.
- `AvailabilityMaterializationJobOptions.HorizonDays = 30`, per deployment.
- The handler is strictly non-destructive: any business-local day that already holds *any* event row
  is skipped, which is the whole of `adr/0053`'s insert-only guarantee.
- `WorkingHoursRule` refuses a window crossing midnight ("a shift crossing midnight is two rules, on
  two days"). **The cycle design below removes any need to revisit that** — see Decided.

## Decided: a separate `WorkerSchedule` aggregate, not fields on `Worker`

`Worker` already owns two relationships and its invariants are about *who this person is and whose
they are*. A schedule is about *when they work*, it is the materialiser's input, and it carries a
cursor the background job writes. Folding it in would make `20-13`'s CRUD screen save fields it has
no business touching, and every rename would write the row the job owns. A separate aggregate with
its own repository port keeps the two lifecycles apart — the same reason `WorkingHoursRule` is not a
list inside `Worker` today.

## Decided: two template kinds, one worker, one kind at a time

- **Weekly** — a set of `(DayOfWeek, StartsAt, EndsAt)`. The existing `WorkingHoursRule` rows,
  unchanged.
- **Cycle** — `(AnchorDate, WorkingDays N, RestDays M, StartsAt, EndsAt)`: one pair of hours applied to
  every working day the cycle produces. Whether a given business-local day is a working one is a pure
  function of `(anchor, N, M, day)`, so it needs no state and no drift correction.

**The cycle chooses which days, never the hours inside a day** — and that is what dissolves the
midnight problem entirely. "Сутки через трое" is `1/3` plus the worker's ordinary daytime window: a
worker on duty overnight still sells slots inside stated hours, because nobody books a haircut at
03:00. No 24-hour bookable window is ever generated, and `WorkingHoursRule`'s midnight refusal stays
exactly as it is.

Mixing the two kinds on one worker is not offered. Switching kind clears the other kind's parameters,
and the console says so before saving; it does **not** touch already-materialised days, which are
`20-16`'s business and nothing else's.

## Decided: the cursor moves forward only, in this item

`MaterializeFrom` — a business-local `DateOnly` on the schedule. The job materialises from
`max(today, MaterializeFrom)` out to `today + HorizonDays`, then advances the cursor past what it
cut.

**Moving the cursor backwards is a destructive re-cut, and it is deliberately not reachable from this
item's own save** — it is `20-16`, with a preview and a confirmation. That split is the point: nothing
in *this* item can delete anything, so `adr/0053`'s insert-only argument survives intact for the
background job, and destruction gets exactly one named entry point with a human on it.

## Decided: slot length and buffer move to the schedule, and the calendar loses its copy

`BookingCalendar.BufferMinutes` is **removed**, with the migration copying its current value into
every worker schedule it governs today. Keeping it as "the default for new workers" was rejected: the
same number in two places diverges, and the support question then opens with "which one won".

The buffer keeps its existing meaning — dead time *between* consecutive slots, zero meaning
back-to-back. It is not a lunch break; a lunch break is a hole in the middle of a day, which the
weekly template already expresses as two rules on one day.

## Decided: a service longer than the slot is not offered, until `20-18`

With an explicit slot length, "every service the worker offers fits in a slot" stops being structural
— it was guaranteed only because the length was derived from the longest one. Until `20-18` lands, the
booking surface simply **does not offer** a service whose duration exceeds that worker's slot length,
rather than offering a booking nobody can honour.

Named plainly rather than buried: a shop with 30/60/90-minute services on a 30-minute grid can sell
only the 30-minute one until `20-18` ships. That is why `20-18` is queued immediately after this item
and not later.

## Scope

- A `WorkerSchedule` aggregate, its repository port in `Application/Abstractions`, its Postgres
  adapter, and a migration.
- Fields: kind; the weekly rules or the cycle parameters; `SlotMinutes`; `BufferMinutes`;
  `HorizonDays` (**capped at 180** — without a bound a tenant types 3650 and the job cuts ten years of
  slots per worker); `MaterializeFrom`; `CreatedAt`/`UpdatedAt`.
- `MaterializeAvailabilityHandler` reads slot length and buffer from the schedule, honours the
  per-worker horizon and the cursor, and advances the cursor after a successful run.
- `AvailabilityMaterializationJobOptions.HorizonDays` stops being the materialisation horizon and
  becomes the value a newly created schedule is seeded with.
- `GET`/`PUT /workers/{id}/schedule`, gated on `Permission.CalendarConfigure`.
- The schedule section of `20-13`'s worker card.
- **ADR-0084** — a worker's schedule is a template of two kinds, and the cycle kind chooses days, not
  hours. It records the reversal of `WorkingHoursRule`'s own "deliberately not a recurrence language"
  and why the reversal is narrow: one cycle shape, no general recurrence language, hours still
  weekday-or-cycle wall clock resolved per day.

## Out of scope

- Re-cutting already-materialised days — `20-16`.
- Bookings spanning several slots — `20-18`.
- Per-service slot grids. A slot is still one row with one status, materialised before anybody has
  chosen a service; that stays true.
- A lunch break as a first-class field. Two weekly rules on one day already express it.

## Done when

- [ ] A `2/2` cycle anchored on a given date produces slots on exactly the right business-local days
      across a month — proven by a test covering the anchor day itself and a resting day.
- [ ] `1/3` ("сутки через трое") produces slots on one day in four, inside the stated hours, with no
      slot crossing midnight.
- [ ] A working day 12:00–18:00 at a two-hour slot with a zero buffer produces exactly three slots —
      12–14, 14–16, 16–18. The spec's own example, as a test.
- [ ] The same day with a 30-minute buffer produces two slots (12:00–14:00, 14:30–16:30) and drops the
      tail — so the buffer is *shown* consuming time rather than asserted to.
- [ ] Two workers on one calendar with different slot lengths produce different grids on the same day.
- [ ] A horizon above 180 is refused by the API.
- [ ] The cursor advances after a run, and an immediate second run inserts nothing.
- [ ] A service longer than the worker's slot is not offered for that worker on the booking surface.
- [ ] `BookingCalendar.BufferMinutes` is gone and no code path reads it.

## Open questions

- Whether `RegisterTenantHandler`'s provisioning transaction should create a default schedule for the
  first worker it makes, or whether a worker starts with no schedule and materialises nothing until a
  human writes one. The second is today's behaviour for a worker with no rules and is the safer
  default; the first makes the demo tenant work out of the box. Decide when implementing.
