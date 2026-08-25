# ADR-0049: AGO Calendar's time model, and where the no-overlap guarantee lives

- **Status**: Accepted
- **Date**: 2026-08-25
- **Stage**: 20 (`backlog/20-01-domain-model-and-persistence.md`)

## Context

AGO Calendar's whole reason to exist is answering one question correctly under load: *is this slot
still free?* Getting it wrong produces two customers in one chair, which is the kind of defect a
booking product does not survive.

Two forces make that question harder here than the equivalent one in AGO Chat.

**First, time in a calendar is not one thing.** At least four distinct notions appear in the product
spec, and any two of them conflated produces a bug that only shows up for somebody in another
timezone or twice a year:

1. a worker's recurring schedule — "Mon-Fri, 09:00-18:00", a statement about a clock on a wall;
2. a concrete slot — an interval of real time that either has passed or has not;
3. the business's own zone — which converts (1) into (2), and which is a property of a place;
4. the customer's zone — which affects only how (2) is rendered to them.

AGO Chat never had to separate these. Its only real time concern was `adr/0011`'s "store UTC, order
by sequence, never by a clock", and its ordering guarantee deliberately does not depend on time at
all. A calendar cannot make that move: the domain *is* time.

**Second, "no double booking" is two different rules, not one.** One customer must not take a slot
another already took. And separately, a worker must not end up with two events covering the same
interval at all — which a materialisation run repeating itself, a manual edit lengthening a day, or
an administrative block dropped on top of an existing booking can all produce with no customer
involved. The first rule is about one row; the second is about the relationship between rows.

`6-09`/`6-10` in AGO Chat are the worked precedent for getting this class of thing wrong: an
application-level "check, then act" on operator capacity leaked a slot on every close, and the fix was
an atomic compare-and-set inside the transaction. `CLAUDE.md` rule 8 is that lesson written down.

## Decision

**One decision with two halves, because neither can be made without the other** — the no-overlap
constraint is expressed as a range over the very columns the time model decides to store.

### Half one: what is stored, in what

- **`events.starts_at` / `events.ends_at` are `timestamptz`** — absolute instants, mapped to
  `DateTimeOffset`. This is the only table in the product that stores instants, and it is the only
  one that needs to: overlap, "has it started", and "has it ended" are questions with one answer for
  every observer on earth.
- **`working_hours_rules.starts_at` / `ends_at` are `time` (no zone), with a `day_of_week` name** —
  wall clock, mapped to `TimeOnly`/`DayOfWeek`. `date-and-time.md`'s own carve-out ("`DateOnly`/
  `TimeOnly` for genuine calendar values") is doing real work here rather than being a footnote.
- **`calendars.time_zone` is an IANA zone id as `text`** (`Europe/Moscow`), never a UTC offset. It is
  the single bridge between the two above, applied exactly once — at materialisation (`20-02`) — and
  never again downstream.
- **`events.local_date` is a `date`**: the business-local day the slot belongs to, computed through
  that zone when the row is written.
- **The customer's zone is stored nowhere.** It is a rendering parameter carried on the request, the
  same way `adr/0011` already treats it for chat.

Two consequences are deliberate. `BookingCalendar.TimeZone` has no setter — every already-materialised
row's `local_date` was computed in the zone the calendar had at the time, so re-zoning a live calendar
is a data migration with a human in the loop, not a settings change. And `Ago.Calendar.Domain` never
calls `TimeZoneInfo.FindSystemTimeZoneById`: `CalendarTimeZone` validates the *shape* of a zone id and
refuses anything that looks like an offset, but resolving it against the tz database is an
Infrastructure concern, because that database is ambient machine state that differs between a Windows
dev box and a Linux container.

### Half two: the aggregate enforces the state machine; the database enforces overlap

- **A slot and the booking that takes it are one row.** `Event` carries a `status`
  (`Available | PendingConfirmation | Booked | Cancelled | NoShow | Blocked`), and booking is that
  row's own transition, not the insert of a second row somewhere else. The claim is therefore a
  single compare-and-set — `... WHERE id = @id AND status = 'Available'` — whose rows-affected count
  *is* the verdict.
- **`Event` enforces only what it can see**: which transition may follow which, and the time-based
  preconditions on each (no claim on a slot that has started, no confirmation window that has already
  closed, no no-show before the visit ended). It never asks whether another row overlaps.
- **Postgres enforces overlap**, with a GiST exclusion constraint on `events`:

  ```sql
  EXCLUDE USING gist (worker_id WITH =, tstzrange(starts_at, ends_at, '[)') WITH &&)
      WHERE (status <> 'Cancelled')
  ```

  `btree_gist` supplies the equality half. `'[)'` matches `TimeSlot.Overlaps`'s own half-open
  comparison exactly, so back-to-back slots are adjacent rather than colliding. Cancelled rows are
  excluded because a cancellation genuinely frees the time; `Blocked` and `NoShow` are *not* excluded,
  because both still occupy the worker.
- **The aggregate's own optimistic concurrency is Postgres's `xmin`**, mapped as a row version exactly
  as `1-04` did for `conversations`. Two callers who each loaded the same `Available` row both pass
  `Event.Claim` in memory; one save commits and the other is rejected, surfacing as
  `EventConcurrencyConflictException` rather than as an EF type.

The division stated in one line: **an aggregate can enforce a rule about itself; only the database can
enforce a rule about the relationship between rows.**

## Consequences

- **The overlap guarantee is provable, and was proven.** `Ago.Calendar.Integration.Tests` opens two
  real concurrent transactions on a Testcontainers Postgres, has both insert overlapping events for
  one worker, and shows the second parked on the first's lock (`pg_stat_activity`) and then refused
  with `23P01` once the first commits. Removing the two `migrationBuilder.Sql` lines turns exactly
  four tests red and leaves the rest green — checked by doing it.
- **A booking failure has two distinct shapes a caller must handle**, and that is a real cost of not
  putting everything in one place: `EventConcurrencyConflictException` ("somebody else claimed this
  row") and `SlotOverlapException` ("this time is taken by a different row"). Both are translated at
  the adapter so no handler sees an ORM or Npgsql type, but `20-03` genuinely has to decide what to do
  about each.
- **This is Postgres-specific and goes on the Stage 9 friction list.** MySQL has neither exclusion
  constraints nor range types; a MySQL adapter would need a different mechanism entirely — a lock or a
  serialized transaction — not a translated DDL statement. `data-model.md`'s Stage 9 section records
  it.
- **A `Cancelled` row no longer participates in the constraint, so "how far is this worker
  materialised" must skip cancelled rows too**, or one cancellation at the far end of a window
  convinces the materialiser it has nothing left to generate. `IEventRepository.GetMaterializedHorizonAsync`
  does, with a test.
- **`events` carries `tenant_id` even though it is reachable through `calendar_id`.** A denormalisation,
  taken deliberately because `data-model.md` already records the opposite choice as a standing cost:
  `messages` has no `site_id`, so every per-tenant question about messages is a join, forever. This
  product's hottest cross-calendar read — `20-04`'s tenant-wide pending-confirmation queue — would be
  exactly that join.
- **`local_date` is only correct for the zone the calendar had when the row was written.** That is the
  price of not deriving it, and it is why the zone is immutable. The benefit is that "delete this
  worker's slots for Tuesday" is an indexed equality predicate instead of a non-sargable
  `AT TIME ZONE` expression no index can serve.
- **A test that crosses a DST boundary is not optional here.** `date-and-time.md` already asked for
  one; in this product it is load-bearing rather than diligent, and `DaylightSavingTimeTests` uses
  `America/New_York` deliberately — Russia has not observed DST since 2014, so a Moscow-only test
  would pass against code that stored a fixed offset and prove nothing.

## Alternatives considered

- **Model slots as computed intervals and bookings as rows** (materialise nothing; derive availability
  from the rules at read time). Rejected, and the product spec rejects it too. Deriving availability
  means the thing a customer books does not exist until they book it, so "is it free" has no row to
  compare-and-set against and needs a separate locking mechanism invented on top of computed
  intervals. Materialised rows also make the spec's central feature — a tenant editing a generated day
  directly, instead of describing an exception to a rule — a plain `UPDATE`.
- **Two tables: `slots` and `bookings`.** Rejected. It reads cleaner and makes the concurrency worse:
  "is this slot free" becomes "does a booking row exist for it", a read followed by an insert, which is
  correct only if a unique index on `slot_id` is added to make it correct — at which point the index is
  doing the work and the second table is bookkeeping.
- **Enforce overlap in the aggregate**, by loading the worker's neighbouring events and checking. This
  is the tempting one, because it puts the rule where a reader looks for it. Rejected: it is a
  check-then-act over a set, so two concurrent writers both read a clean set and both write. It is
  `6-09`'s defect with different nouns.
- **Enforce overlap with a serializable transaction** instead of a constraint. Rejected: it makes every
  writer pay for a rule that a partial index can enforce for free, and it converts a deterministic
  rejection into a serialization failure the caller must retry — more machinery, weaker signal.
- **Store a UTC offset on the calendar instead of an IANA zone.** Rejected outright by
  `date-and-time.md`, and worth restating because a booking product is where the rule bites: an offset
  chosen at configuration time is wrong for half of every year in any DST-observing zone, and the
  failure mode is a shop that quietly opens an hour late in March.
- **Store the recurring rule as instants** (a first occurrence plus a repetition). Rejected for the
  same reason: "we open at nine" is a fact about a wall clock, and any instant chosen to represent it
  bakes in one side of a DST transition.
- **Derive `local_date` at query time with `AT TIME ZONE`.** Rejected: non-sargable, so no index can
  serve a per-day query, and it puts the zone into every query that groups by day — where one omission
  silently returns the wrong day's slots.
- **A `slot_range tstzrange` column instead of two `timestamptz` columns.** Genuinely close, and it
  would let the constraint name a column instead of an expression. Rejected because every other read
  in the product wants the endpoints individually (order by `starts_at`, filter on `ends_at`), and EF
  Core would need a custom mapping for a type the domain would immediately decompose again.
