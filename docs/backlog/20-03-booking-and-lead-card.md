# AGO Calendar: booking claim and the customer lead card

- **Stage**: 20
- **Status**: ready
- **Depends on**: `20-02-availability-materialization-and-manual-editing.md`

## Goal

A visitor (unauthenticated, identified only by phone number) can claim a real `Available` `Event` row
and have it look instantly confirmed, while internally the row only moves to `PendingConfirmation` with
a `ConfirmationDeadline` — the exact two-step mechanic the product spec calls out as the central design
decision of this whole product. A `Customer` lead card is created or updated by phone number on the
same booking. This item builds the claim itself; the confirmation sweep and operator reject/cancel
actions that act on the row afterward are `20-04`.

## Context to read first

`docs/architecture/concurrency.md`'s "Operator assignment — the contended path" section in full — the
atomic `UPDATE ... WHERE active_chats < capacity` statement this item's own claim is modelled on
directly, substituting `WHERE Status = 'Available'` for the capacity predicate. `CLAUDE.md` rule 8
("never cache what a write decision depends on... compare-and-set read comes from the database inside
the transaction") — this item's claim must be a real `WHERE Status = 'Available'` compare-and-set
inside a transaction, never a cache check or an application-level optimistic lock, matching the product
spec's own explicit instruction. `docs/backlog/4-01-waiting-queue-and-capacity-model.md` — the closest
existing precedent for "a raw atomic UPDATE, not an EF aggregate load-mutate-save," including its own
stated reasoning for why this is a deliberate exception to `adr/0004`'s "EF for writes" default; restate
that same reasoning here in the response (teaching mode) rather than treating it as a one-off precedent
that only applied to `Operator.active_chats`. `docs/architecture/data-model.md`'s partial-index pattern
(`ix_conversations_waiting`) — this item's claim query reads through the equivalent index `20-01`
already created on `events`.

## Scope

- `IEventClaimStore` (or similarly named, `Ago.Calendar.Application.Abstractions`) —
  `TryClaimAsync(EventId, CustomerPhone, TimeSpan confirmationWindow, CancellationToken) -> ClaimResult`,
  implemented in `Ago.Calendar.Infrastructure.Postgres` as a raw atomic
  `UPDATE events SET status = 'PendingConfirmation', customer_id = @customerId,
  confirmation_deadline = @deadline WHERE id = @id AND status = 'Available'` — a row count of 0 is "lost
  the race" or "no longer available," a normal outcome every caller must treat as such, never logged at
  `Error`, matching `4-01`'s own precedent for this exact class of outcome.
- `BookEventHandler` (`Ago.Calendar.Application.UseCases.BookEvent`): validates the requested `Event` is
  actually `Available` and belongs to the calendar/tenant the request claims, upserts the `Customer`
  lead card by phone number (`INSERT ... ON CONFLICT (tenant_id, phone) DO UPDATE` — a real upsert, not
  a read-then-branch, for the same race-avoidance reason every other contended write in this codebase
  uses one), calls `TryClaimAsync`, and — only on a successful claim — returns success to the caller.
  On a lost race, returns a `Result` the caller renders as "sorry, that slot was just taken," never a
  500.
- `ConfirmationWindow`'s length is a configuration value (`BookingOptions.ConfirmationWindow`), not
  a number this item invents a "correct" default for — matching `CLAUDE.md`'s instruction against
  invented numbers, the same treatment `20-02`'s rolling horizon already got.
- `POST /api/v1/calendars/{calendarId}/events/{eventId}/book` (or the equivalent shape once
  `api-design.md`'s own conventions are applied — follow its existing route-naming rules rather than
  inventing new ones), unauthenticated (a visitor books with no account, matching `Customer`'s own "no
  password" design), rate-limited per phone number and per calendar the same two-bucket shape `3-05`
  established for AGO Chat (`IRateLimiter`, reused unchanged from `Ago.Platform.Abstractions` — the
  exact kind of second-caller proof `vision.md`'s platform claim exists to produce).

## Out of scope

- The confirmation-sweep job, operator reject, cancellation, and no-show — `20-04`.
- SMS delivery of the confirmation — `20-05`; this item's own `Done when` stops at the row transitioning
  correctly and the customer lead card existing, not at any notification being sent.
- Multiple services in one booking — explicitly out of scope for v1 per the product spec; `BookEventHandler`
  takes exactly one `EventId`, already tied to at most one `Service` by `20-01`'s own domain shape.

## Done when

- [ ] `Ago.Calendar.Application.Tests` (handler-level, fakes for the store): a successful claim upserts
      the customer and transitions the event; a claim against a non-`Available` event is rejected
      without touching the customer row.
- [ ] `Ago.Calendar.Integration.Tests`, against real Postgres, real concurrency: N concurrent booking
      attempts against the *same* `Event` — exactly one succeeds, the rest observe "no longer
      available," and the event's final state is `PendingConfirmation` with exactly one `customer_id`,
      never a torn or double-claimed state — the same concurrency bar `OperatorCapacityStoreTests`
      already proved for AGO Chat's own compare-and-set claim.
- [ ] A repeated booking attempt by the same phone number updates the existing `Customer` row (name,
      last-seen) rather than creating a duplicate lead card — proven with a real duplicate-phone
      booking against a running instance.
- [ ] Rate limiting proven the same way `3-05`'s own `RateLimitingTests` proved it — a denied booking
      attempt returns `429`/`Retry-After`, not a bare rejection with no guidance.

## Open questions

None — the compare-and-set mechanic, the "no cache" rule, and the "one service per booking" v1 limit
are all fixed by the product spec and `CLAUDE.md`'s own non-negotiable rules; nothing here needs the
author's judgment beyond ordinary implementation mechanics already covered by existing precedent.
