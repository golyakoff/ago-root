# AGO Calendar: confirmation sweep, operator queue, cancellation and no-show

- **Stage**: 20
- **Status**: done
- **Depends on**: `20-03-booking-and-lead-card.md`

## Goal

A `PendingConfirmation` event either gets explicitly rejected by an operator or, if nobody acts before
its `ConfirmationDeadline`, is automatically flipped to `Booked` by a periodic sweep — the second half
of the two-step booking mechanic `20-03` started. Every one of a tenant's operators shares one queue of
pending bookings across every calendar (no per-operator assignment, mirroring AGO Chat's own
unassigned-conversation queue shape). Operators can also manually cancel a `Booked` event and flag a
past one as a no-show.

## Context to read first

`docs/architecture/concurrency.md`'s description of `ConversationAssignmentJob`/`OutboxDispatcher` — the
product spec is explicit that this item's sweep job is **the same architectural shape**, not a new
mechanism: `PeriodicTimer`, `FOR UPDATE SKIP LOCKED` batch-claim of expired-but-unactioned rows, one
transaction per batch, a lost race on any single row is a normal retry-next-tick outcome, not an error.
Restate this "same shape as an existing shipped mechanism" reasoning in the response (teaching mode)
rather than presenting the sweep as new architecture. `docs/architecture/messaging.md`'s "Topics" table
— this item needs a new integration event (`BookingConfirmed` or similar, past-tense fact, carrying
`EventId`/`CustomerId`/`TenantId` at minimum) for `20-05`'s SMS delivery to consume; state its shape
here even though `20-05` is the one that wires a real consumer to it, so that item does not have to
invent the contract from scratch. `docs/adr/0016-rbac-authorization-model.md` — the permission checks
this item's operator-facing endpoints need (`booking:confirm`... actually v1 has no explicit "confirm"
action, since confirmation is the *default* outcome of doing nothing — the operator-facing action is
`booking:reject`, plus `booking:cancel` and `booking:no_show`, state the exact names once implemented).

## Scope

- `PendingBookingSweepJob` (`Ago.Calendar.Worker`, `PeriodicTimer`): per tenant, per tick, claims a
  batch of `PendingConfirmation` events whose `ConfirmationDeadline` has passed
  (`FOR UPDATE SKIP LOCKED`, mirroring `WaitingConversationClaimQuery`'s own exact query shape), and for
  each, atomically transitions it to `Booked` inside the same transaction as the claim — a crash between
  claim and transition must not leave a row silently stuck, the same reasoning `4-02`'s own "capacity
  claim and the assignment it enables must commit atomically" already established for AGO Chat's
  assignment engine. On success, stages the new `BookingConfirmed` outbox row in the same transaction
  (`CLAUDE.md` rule 4 — write and event committed together, published separately).
- `RejectBookingHandler`: an operator explicitly rejects a `PendingConfirmation` event before the
  deadline (`PendingConfirmation → Cancelled`), gated by `Permission.BookingReject`, checked the same
  way `IPermissionChecker` already gates every AGO Chat permission (`adr/0016`'s pattern, a new,
  independent permission catalogue per `20-01`'s own note — not a shared enum with `Ago.Chat.Domain`).
- **One shared pending-bookings queue across all of a tenant's operators, across every calendar** — a
  read (`GetPendingBookingsForTenantHandler`, Dapper, matching `adr/0004`'s "reads bypass the
  aggregate" rule) that any operator with `Permission.BookingReject` can act against; no per-operator
  assignment exists in v1, mirroring the product spec's explicit instruction that this is "the same
  'unassigned queue' shape this project's own conversation-assignment already established, not
  per-operator assignment."
- `CancelBookingHandler`: operator-only, manual cancellation of a `Booked` event
  (`Booked → Cancelled`), gated by `Permission.BookingCancel`. No customer self-service cancel in v1 —
  stated explicitly, matching the product spec's own "no SMS-link self-service cancel" instruction.
  Reschedule is not a first-class operation: cancelling and rebooking is the only path, and this item
  builds no reschedule-specific mechanism.
- `MarkNoShowHandler`: operator-only, sets a past `Booked` event to `NoShow` — a simple manual flag,
  seeding future logic (e.g. a pre-payment requirement for customers with a no-show history) that is
  explicitly **not** built here, just the flag and its persistence.

## Out of scope

- SMS delivery of the confirmation — `20-05`, which consumes the `BookingConfirmed` event this item
  stages.
- Any pre-payment/no-show-history enforcement logic — the `NoShow` flag exists as raw material only.
- A reschedule operation — explicitly rejected for v1, cancel-and-rebook is the only path.
- Per-operator assignment of pending bookings — explicitly rejected for v1, matching the product spec.

## Done when

- [x] `Ago.Calendar.Integration.Tests`: an event whose `ConfirmationDeadline` has passed is flipped to
      `Booked` by the sweep job on its next tick, and the `BookingConfirmed` outbox row exists in the
      same transaction (proven the same way `4-02`'s own atomic claim-plus-assignment was — inspecting
      the committed transaction, not just the end state).
- [x] `Ago.Calendar.Concurrency.Tests`: two concurrently running sweep-job ticks (simulating two
      `Worker` replicas) against the same batch of expired events do not double-process any row —
      `SKIP LOCKED` proven under real concurrent transactions, the same technique
      `WaitingConversationClaimQueryTests` already used.
      (`ConcurrentConfirmationSweepTests`, four tests: two sweepers on one row, then 4 and 12
      sweepers on twenty rows with a batch bound of five so each one claims several times.
      Contention is forced rather than hoped for — each sweeper opens its connection **before**
      parking on a shared gate, because a handshake after release staggers the arrivals across
      exactly the interval the claim is meant to be tested across. A fourth test isolates the
      property `SKIP LOCKED` exists for, as opposed to a plain `FOR UPDATE`: with every expired
      row held by an open transaction, a sweeper returns zero promptly instead of blocking. That
      one takes 31 seconds and times out when `SKIP LOCKED` is removed, which is the clearest
      evidence in the suite that the clause is load-bearing.)
- [x] `RejectBookingHandler`/`CancelBookingHandler`/`MarkNoShowHandler` each have a positive test and a
      permission-denied test (an operator without the relevant permission is rejected).
      (`BookingLifecycleHandlerTests`, twelve tests. Each denial asserts the stronger property:
      a refused caller never reached the database *and never loaded the booking*, so the error
      cannot be used to learn whether an id exists. A further test pins adr/0016's granularity
      argument directly — holding `booking:reject` does not let an operator cancel a confirmed
      visit. Permissions resolve against real `roles`/`operator_roles` rows in
      `SharedPendingQueueTests` as well, because a permission model that resolved nothing would
      leave every fake-backed test passing.)
- [x] The shared-queue read returns pending bookings across every calendar for a tenant, proven with two
      calendars and two operators — any operator sees and can act on either calendar's pending bookings,
      neither is scoped to "their own."
      (`SharedPendingQueueTests`, six tests, against real Postgres. Two calendars specifically,
      because a queue accidentally scoped to one calendar looks entirely correct in a
      single-calendar fixture — and the mutation that adds such a scope turns five of the six
      red. Seeing is tested separately from acting: one test has an operator reject a booking on
      the calendar they did not "belong" to.)
- [x] `docs/architecture/messaging.md` (or `ago-calendar`'s own copy) gains the `BookingConfirmed`
      event's shape in its own "Topics" table, matching how every other integration event in this
      codebase is documented.
      (`messaging.md` gains an **AGO Calendar's own topics** section rather than a row in AGO
      Chat's table — separate product, separate vhost, separate database (`adr/0027`), and the
      two consume nothing of each other's. `personal-data.md` gains a row for this product's
      `outbox.payload` too, which the item did not ask for: the payload carries a `customer_id`,
      an id that singles somebody out, and an opaque "just ids" wave-through is what `14-06`
      taught me to stop doing.)

## Open questions

None — the sweep's architectural shape, the shared-queue model, and the no-reschedule/no-self-service-
cancel limits are all fixed by the product spec; nothing here needs the author's judgment beyond
ordinary implementation mechanics already covered by `4-02`'s own precedent.

## What shipped, and what it changed

- **The exact permission names**, as the item asked: `booking:reject`, `booking:cancel`,
  `booking:mark_no_show`. All three already existed in this product's own catalogue (`20-01`), which
  is independent of AGO Chat's by `adr/0027` and shares no enum and no `roles` table with it. The read
  is gated on `booking:reject` rather than a separate `booking:read` — the queue exists to be acted
  on, so an operator who can see it and cannot act is watching a countdown they cannot stop.
- **`Permission.BookingConfirm` still has no caller, and that is now a contradiction worth
  resolving.** This item's own scope says v1 has no explicit confirm action, because confirmation is
  what happens when nobody acts — and that is coherent: the queue is a veto list. But `20-01`'s
  `Event.Confirm` doc comment names "an operator who is looking at the request right now" as one of
  its two legitimate callers, and the permission was declared for it. One of the two should change:
  either `20-06` builds an early-confirm action, or the permission goes. Not decided here.
- **`Customer.NoShowCount` still has no writer.** `20-01`'s `EventNoShowRecorded` doc names the lead
  card as its only consumer and points at `20-04`; this item's scope says "just the flag and its
  persistence". The scope won, so the column stays structurally zero. Incrementing it means a
  second aggregate in the same transaction and therefore a multi-aggregate port this item was not
  asked to invent. Whoever builds the pre-payment rule needs that writer.
- **`EventConfirmed` was widened** with `CalendarId` and `LocalDate`. It is an in-memory record with
  no storage impact, and both were missing for reasons that turned out to be oversights rather than
  decisions: `EventClaimed` already carried `CalendarId`, and `LocalDate` exists precisely so nothing
  downstream re-derives a business day (`adr/0049`).
- **Dapper arrived**, three items after `20-01` predicted it would. That prediction named `20-02`;
  `20-02`'s reads were all write-side questions and `20-03` books a slot the caller already chose, so
  the shared queue is genuinely the first projection. The stale prediction in
  `Directory.Packages.props` is corrected in the same change.
- **A real limitation found by running it**: EF cannot translate containment on a value-converted
  `text[]`, so `PermissionChecker` materialises an operator's roles and tests membership through
  `Role.Grants` instead. ago-chat's equivalent translates because its column is a plain `string[]`
  with no converter; this product kept the strongly-typed `Permission`, and this is the price. Cheap
  — one role, seven short strings — and it keeps the aggregate as the single definition of what a
  role grants.

Deliberately left: SMS delivery (`20-05`, which consumes `BookingConfirmed`); any pre-payment or
no-show-history enforcement; a reschedule operation (cancel-and-rebook is the only path); per-operator
assignment; and HTTP endpoints for the three actions — the item's scope names handlers, and `20-06`
builds the console that calls them, matching `20-02`'s own handlers-only precedent.
