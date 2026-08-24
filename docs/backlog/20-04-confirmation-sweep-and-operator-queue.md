# AGO Calendar: confirmation sweep, operator queue, cancellation and no-show

- **Stage**: 20
- **Status**: ready
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

- [ ] `Ago.Calendar.Integration.Tests`: an event whose `ConfirmationDeadline` has passed is flipped to
      `Booked` by the sweep job on its next tick, and the `BookingConfirmed` outbox row exists in the
      same transaction (proven the same way `4-02`'s own atomic claim-plus-assignment was — inspecting
      the committed transaction, not just the end state).
- [ ] `Ago.Calendar.Concurrency.Tests`: two concurrently running sweep-job ticks (simulating two
      `Worker` replicas) against the same batch of expired events do not double-process any row —
      `SKIP LOCKED` proven under real concurrent transactions, the same technique
      `WaitingConversationClaimQueryTests` already used.
- [ ] `RejectBookingHandler`/`CancelBookingHandler`/`MarkNoShowHandler` each have a positive test and a
      permission-denied test (an operator without the relevant permission is rejected).
- [ ] The shared-queue read returns pending bookings across every calendar for a tenant, proven with two
      calendars and two operators — any operator sees and can act on either calendar's pending bookings,
      neither is scoped to "their own."
- [ ] `docs/architecture/messaging.md` (or `ago-calendar`'s own copy) gains the `BookingConfirmed`
      event's shape in its own "Topics" table, matching how every other integration event in this
      codebase is documented.

## Open questions

None — the sweep's architectural shape, the shared-queue model, and the no-reschedule/no-self-service-
cancel limits are all fixed by the product spec; nothing here needs the author's judgment beyond
ordinary implementation mechanics already covered by `4-02`'s own precedent.
