# ADR-0188: Operator manual booking entry claims straight into Booked, minting a fresh person, in a dedicated store

- **Status**: Accepted
- **Date**: 2026-09-29
- **Stage**: Stage 26 (`26-268`)

## Context

A new AGO Calendar tenant already runs a business and has near-term bookings taken outside the
system (by phone). The operator must be able to re-enter those by hand so the slots are blocked and
online visitors cannot double-book them — without the visitor's verify-and-confirm dance, and without
creating a chat conversation (the design pass, `docs/backlog/26-268-manual-booking-entry.md`).

The constraints this decision has to live inside:

- **The atomic claim is the product's one concurrency guarantee** (`adr/0059`/`adr/0086`): a run is
  claimed by `UPDATE events SET ... WHERE status='Available' AND starts_at>@now`, whose rows-affected
  count is the verdict. Any manual path must go through this exact mechanism.
- **The person model is thin and calendar-local** (`adr/0184`): the calendar keeps only
  `PersonRecord` (phone + verification facts); the name and contact channels are owned by AGO Chat,
  reached only through the outbox (`PersonRegistered`), never a synchronous call (rule 8).
- **The operator write path already exists for reschedule** (`26-208`/`adr/0187`):
  `IBookingRescheduleStore` proves both that an operator-authenticated claim can land straight in
  `Booked` with no veto window, and that a store's own transaction is where a distinct write shape
  belongs. Reschedule carries an *existing* person forward; manual entry must *create* one.
- **A phone is a hint, not proof** (`adr/0147`): a number can be shared, and recognising a client by
  phone must never auto-merge — only surface candidates for the operator to confirm.
- `booking:create` (added in `26-268` slice #1) is the gate, alone — not paired with `customer:edit`,
  because the client this handler creates is the booking's own trusted side-effect, the same way a
  widget booking mints one with no permission check at all (`customer:edit` guards a different,
  never-invoked sub-operation on this path).

## Decision

**An operator manual entry is a new use case (`EnterManualBookingHandler`) over a new port
(`IManualBookingStore`)** that, in one transaction:

1. checks `booking:create` first;
2. validates the phone (`PhoneNumber`'s own constructor);
3. resolves calendar/worker/service/schedule, rejecting if the worker does not offer the service or
   either is inactive;
4. runs `ConsecutiveRunFinder.FindRun` as a courtesy read (rule 8 — availability is decided in the
   claim's own `WHERE`, never here);
5. **mints a new person id** via `IIdGenerator` — always, in this slice (see Phone-based recognition
   below for what is deferred and why);
6. calls the store, which upserts the fresh `PersonRecord` (phone, `PhoneConfirmedByOperatorAt = now`,
   `PhoneVerifiedAt` left null — the operator has *not* proven the number by SMS, only "I called and it
   is them", `23-12`'s own distinct fact), claims the run straight into `Booked` (no deadline, no
   `origin_conversation_id` — a manual entry never has a chat origin), and stages exactly two outbox
   events: `PersonRegistered` (the minted id → chat, creating a Person and contact details, no
   conversation) and `BookingConfirmed` (deliberately **not** `BookingPendingStateChanged` — this
   booking was never pending).

**A third port, not a flag on `IBookingStore` or `IBookingRescheduleStore`.** Each existing port already
earned its own shape for the identical reason: `IBookingStore` claims into `PendingConfirmation` and
upserts a person that may already exist; `IBookingRescheduleStore` claims into `Booked` but carries an
*existing* person forward and stages one `BookingRescheduled`. Manual entry is the one combination that
claims into `Booked` **and** always inserts a fresh person **and** stages a different pair of events.
Generalising any existing port with a `targetStatus`/`registerPerson` flag would couple a third,
differently-shaped caller onto either the hot contended public path or the cancel-and-claim reschedule,
for a shape neither of them has today.

**Permission**: `booking:create` alone (decided in the design pass, §2) — the client is the manual
booking's own trusted side effect.

**No veto window**: the operator asserting a booking that already happened by phone has nothing to be
vetoed; the confirmation window exists to let the business second-guess a *visitor's* request, which is
meaningless here.

**Phone-based recognition (reuse vs. mint) is designed here, built in a later slice (`26-268` §2a):**
the operator will enter the phone first; the server looks up existing `PersonRecord`s by that number for
the tenant, and:
- one match → show the client (name + a returning-client hint) with «Это он» (reuse) / «Новый клиент»
  (mint) both offered;
- several matches → a short pick-list, plus «Новый клиент»;
- no match → proceed to new-client entry.

This does **not** auto-merge (`adr/0147` stays intact): the lookup only *surfaces* candidates; the
**operator** asserts identity by choosing, which is the human confirmation `adr/0147` requires. The
lookup is a cross-cutting read (calendar `PersonRecord` by phone → chat-owned name/history) and is
scoped as its own slice rather than folded into this write.

**Deferred to a later feature, not this ADR's problem to solve**: a booking-origin marker
(`Online`/`OperatorManual`) for analytics — cheapest as a field on the anchor `Event` and on
`BookingConfirmed` — is a real contract choice for whoever builds the outcome-capture feature
(`26-268` §7), not added here (no migration in this slice).

## Consequences

**Positive.**
- Reuses the identical atomic-claim guarantee every other booking path relies on — no new race, no new
  way to double-book a slot.
- `PersonRegistered`/`BookingConfirmed` are both existing, already-consumed contracts; a manual entry
  needs no new wire shape today.
- The store's own transaction boundary keeps the "no trace for an entry that never happened" property
  `IBookingStore` already established: a lost claim race rolls back the person insert too.
- Slice #2a (phone recognition) and slice #3 (optional email) both compose cleanly onto this shape:
  recognition only changes step 5 from unconditional-mint to conditional; email only adds a field to
  `PersonRegistered` and this handler's command.

**Negative / now-owed.**
- A third store alongside `IBookingStore`/`IBookingRescheduleStore` to maintain, each with its own raw
  SQL and its own concurrency test surface.
- `booking:create` must stay in lock-step across `ago-chat`'s and `ago-calendar`'s `Permission.cs`
  (`adr/0093`'s existing cost, paid once more).
- No dedup against existing contacts by phone in this slice — a manual entry always creates a new
  `PersonRecord`/Person even for a client already known to the tenant, until `26-268` §2a ships. Flagged
  in the design pass, not silently accepted.
- No backfill of `booking:create` to existing tenant roles is needed *only* because there are zero real
  tenants as of this writing (`feedback_zero_real_tenants_free_to_change_backend`) — this must be
  re-confirmed before it is relied on again.

## Alternatives considered

- **Reuse `IBookingStore` with a `targetStatus` + `skipDeadline` flag.** Rejected: couples the hot,
  contended public booking path to a third caller with a different concurrency profile and a different
  event set.
- **Claim into `PendingConfirmation` then immediately call `Confirm`.** Rejected: leaks a transient
  pending state that was never real, and stages the wrong events (`BookingPendingStateChanged` for a
  state nobody should observe).
- **A new `Event.EnterManually` domain method.** Rejected — the identical reasoning `adr/0187` already
  gives for reschedule: an aggregate sees only itself and cannot span the person row and the slot row's
  transaction; the composition belongs in a use case, with the transaction in the store beneath it.
- **Dedup/reuse an existing contact by phone in this slice.** Deferred, not rejected — `adr/0147`'s "a
  phone is a hint, not proof" means dedup needs an operator-confirmed recognition step, which is real
  scope (`26-268` §2a), not a corner to cut into the write itself.
