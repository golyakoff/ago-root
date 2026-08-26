# AGO Calendar: booking claim and the customer lead card

- **Stage**: 20
- **Status**: done
- **Depends on**: `20-02-availability-materialization-and-manual-editing.md`
- **Decision**: `adr/0059` — the booking claim is a compare-and-set, and a lost race is not an error

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

- [x] `Ago.Calendar.Application.Tests` (handler-level, fakes for the store): a successful claim upserts
      the customer and transitions the event; a claim against a non-`Available` event is rejected
      without touching the customer row.
      (`Ago.Calendar.Application.Tests`, 17 tests across `BookEventHandlerTests` and
      `BookingConfirmationDisclosureTests`. The negative half asserts the stronger property the
      Done-when implies: a rejected booking never reaches `IBookingStore` at all, so no lead card is
      written for a booking that did not happen — checked for an unknown/foreign slot, an unpublished
      calendar, a malformed phone, a service the worker does not perform, and an inactive worker.)
- [x] `Ago.Calendar.Integration.Tests`, against real Postgres, real concurrency: N concurrent booking
      attempts against the *same* `Event` — exactly one succeeds, the rest observe "no longer
      available," and the event's final state is `PendingConfirmation` with exactly one `customer_id`,
      never a torn or double-claimed state — the same concurrency bar `OperatorCapacityStoreTests`
      already proved for AGO Chat's own compare-and-set claim.
      (`Ago.Calendar.Concurrency.Tests.ConcurrentBookingTests`, at 2, 8 and 24 callers. Contention is
      forced rather than hoped for: each caller gets its own `DbContext` on its own pooled connection,
      **opens that connection before** parking on a shared `TaskCompletionSource` gate, and all are
      released together — without the pre-open, the handshake staggers the arrivals across exactly
      the interval a compare-and-set is meant to be tested across. Asserted afterwards on the rows:
      one `PendingConfirmation` with the winner's `customer_id`, one deadline, and **exactly one lead
      card**, because every loser's transaction rolled back whole. Two further tests guard the other
      direction — sixteen callers on sixteen *different* slots all succeed, so the claim does not
      serialise bookings that are not competing; and sixteen concurrent bookings from **one** phone
      end with one lead card, which is the upsert's own race that the slot race hides.)
- [x] A repeated booking attempt by the same phone number updates the existing `Customer` row (name,
      last-seen) rather than creating a duplicate lead card — proven with a real duplicate-phone
      booking against a running instance.
      (`BookingStoreTests.ARepeatedBookingFromTheSamePhone_UpdatesTheOneLeadCard`, against real
      Postgres, plus `BookingEndpointTests` over real HTTP against the real host. Two further tests
      pin the merge rules that make the update correct rather than merely single-rowed: a late-arriving
      request never rewinds `last_seen_at` (`GREATEST`), and a blank or different name never overwrites
      one an operator curated (`COALESCE`).)
- [x] Rate limiting proven the same way `3-05`'s own `RateLimitingTests` proved it — a denied booking
      attempt returns `429`/`Retry-After`, not a bare rejection with no guidance.
      (Proven at both levels. `Ago.Calendar.Concurrency.Tests.BookingRateLimitTests` drives the real
      `RedisRateLimiter` against a Testcontainers Redis through the real handler — a burst allows
      exactly capacity, concurrent attempts on one bucket never exceed it, the calendar bucket bounds
      a flood arriving from many different numbers, and two tenants sharing one phone number do not
      share a bucket. `Ago.Calendar.Integration.Tests.BookingEndpointTests` then makes a real HTTP
      request to the real host and asserts `429` with a `Retry-After` header parseable as
      delta-seconds and never zero — the header only exists once something maps an outcome onto it,
      and that mapping is not provable from a handler's return value.)

## Open questions

None — the compare-and-set mechanic, the "no cache" rule, and the "one service per booking" v1 limit
are all fixed by the product spec and `CLAUDE.md`'s own non-negotiable rules; nothing here needs the
author's judgment beyond ordinary implementation mechanics already covered by existing precedent.

## What shipped, and what it changed

Full reasoning is `adr/0059`. What is worth flagging here:

- **`IBookingStore`, not `IEventClaimStore`.** The item named a port holding only the claim; it became
  one port holding the claim *and* the lead-card upsert, because the two share a transaction and a
  transaction has to belong to something a reader can see. The reason they share one is data
  minimisation rather than consistency: a lost race rolls the lead card back, so an unauthenticated
  public endpoint never accumulates phone numbers for bookings that did not happen. This is the
  product's first multi-aggregate port, three items earlier than `ITenantRepository` predicted.
- **`BookEventHandler` returns `BookingOutcome`, not `Result<T>`.** `Error` is `(Code, Message)` with
  nowhere to put a retry-after, and `api-design.md` promises a real `Retry-After` header. AGO Chat
  squeezed it into the message text and `ErrorExtensions` there carries a comment apologising for the
  missing header; repeating that seemed worse than one non-standard return type.
- **`200`, not `201` with a `Location`.** The endpoint creates nothing — a slot and its booking are one
  row — so there is no new URL to point at. A deliberate deviation from `api-design.md`'s POST rule.
- **Redis is now a dependency of AGO Calendar**, for the two rate-limit buckets and nothing else. It
  is never a source of truth; the claim reads nothing from it.
- **`AddRedisCaching` could not be used, and that is a platform finding, not a workaround note.** It
  registers `CacheInvalidationPublisher`, which needs an `IEventPublisher`, so a product with no
  broker fails service-provider validation in Development. Verified by doing it. Worked around inside
  `Ago.Calendar.Infrastructure.Redis`; **no `ago-platform` commit was made**.
- **`CalendarModule` now reads `ConnectionStrings:Calendar` before falling back to
  `AGO_CALENDAR_CONNECTION_STRING`**, so a `WebApplicationFactory` can point the real host at a
  Testcontainers Postgres without mutating process-wide state that parallel test collections share.
  Nothing is weakened: the rule was never "read only the environment", it was "never commit a
  credential to a settings file".
- **A registration bug the handler tests could not have caught**: `IBookingStore` was never added to
  `AddCalendarPostgresPersistence`. The HTTP test found it on its first run, which is the argument for
  having one.

Deliberately left for later: the confirmation sweep, operator reject, cancellation and no-show
(`20-04`); SMS delivery of the confirmation (`20-05`); several services in one booking (v1 takes one);
and the public availability read model, which `20-01`'s `IEventRepository` predicted would arrive
here — it did not, because nothing in this item reads availability, and the first genuine caller is
`20-06`'s booking widget.
