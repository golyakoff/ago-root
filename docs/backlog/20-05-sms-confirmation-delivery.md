# AGO Calendar: SMS booking-confirmation delivery

- **Stage**: 20
- **Status**: won't build (2026-08-29) — same business decision as `14-03`'s own:
  `ago-business/docs/decisions/0008-lestnica-tarifov-imena-ceny-kanaly-calendar.md` records SMS
  deprioritized entirely in favour of WhatsApp. Left in the backlog, not deleted, since the port
  design below stays findable if this is ever revisited.
- **Depends on**: `20-04-confirmation-sweep-and-operator-queue.md` (the `BookingConfirmed` integration
  event this item's consumer subscribes to)

## Goal

A booking confirmation — whether the operator explicitly does nothing and the sweep job confirms it,
or a future path confirms it some other way — triggers a real SMS to the customer's phone number,
sent through a new platform-shaped port, published via the outbox exactly like every other reliable
side effect in this codebase. This item builds the port, the outbox wiring, and a documented fake
adapter proven end to end; it deliberately does **not** pick or integrate a real SMS gateway vendor,
naming that choice as a real open question rather than guessing at one (`CLAUDE.md`: "do not invent
numbers, benchmarks, or 'typical' production figures").

## Context to read first

`docs/architecture/messaging.md`'s "Outbox dispatcher" section and `docs/adr/0005-transactional-outbox.md`
— the same "commit the write and the event in one transaction, publish separately" discipline
`CLAUDE.md` rule 4 states, applied here to a customer-facing SMS instead of an internal integration
event. `docs/architecture/file-storage.md`'s `IFileStorage` port shape — the closest existing precedent
for "a technical port above a specific vendor, implemented once per real provider," including its own
"no vendor-specific type leaks above the Infrastructure boundary" rule; this item's `ISmsSender` follows
the identical shape. `docs/backlog/8-01-public-deployment-target.md`'s own real research on VPS hosting
pricing (`adr/0026`) — cited here as the precedent this item's Open questions section points to: real
vendor/pricing research, done for real with real numbers and real citations, is how this kind of open
question gets closed properly, when a session actually has the time and access to do it; naming it as
open rather than guessing is the acceptable fallback, not a shortcut, and this item takes the fallback.
`docs/adr/0006-broker-abstraction.md`'s own "ports are the largest common denominator that does not
lie" reasoning — applied here to justify why `ISmsSender` exposes only "send this text to this number,"
nothing gateway-specific (delivery receipts, sender-ID registration, unicode segmentation cost) leaking
above the port.

## Scope

- `ISmsSender` (`Ago.Platform.Abstractions` — **not** `Ago.Calendar.Application.Abstractions`, and the
  response must state why: it contains no domain concept, a second product could plausibly send an SMS
  for a completely different reason, and it can be described without naming calendars or bookings at
  all — `clean-architecture.md`'s own three-part platform-qualifying test, applied here the same way
  it was applied to `IFileStorage`/`ICache`). Shape: `Task SendAsync(PhoneNumber to, string body,
  CancellationToken ct)` — deliberately minimal, no delivery-receipt callback in v1 (a real gap, named,
  not built speculatively for a use case this item does not have).
- `SmsDeliveryConsumer` (`Ago.Calendar.Worker`): subscribes to `BookingConfirmed` (`20-04`'s event,
  `Competing` mode, a real consumer name per `5-11`'s own found-live lesson about consumer-identity
  naming), records the delivery attempt in the `inbox` table for idempotency (`messaging.md`'s "every
  consumer records `message_id`... handlers must be safe to run twice" — a redelivered
  `BookingConfirmed` must not double-send the SMS), formats the confirmation text, and calls
  `ISmsSender`.
- A **documented fake adapter** (`Ago.Platform.Sms.Fake` or an in-repository test double, state which
  once implemented) that logs the would-be message instead of sending it — this is what lets
  `Ago.Calendar.Integration.Tests` and local development prove the whole path end to end without a real
  gateway credential, the same role `Ago.Chat.LoadDriver`'s fake CRM (`6-04`) plays for webhooks.
- `Ago.Platform.Resilience`'s existing timeout/retry/circuit-breaker mechanism wraps every real-gateway
  call once a real adapter exists (out of scope here, named so the eventual adapter item does not have
  to rediscover it) — the fake adapter this item ships has no failure mode to wrap.

## Out of scope

- **A real SMS-gateway adapter for any specific vendor** — a new, small follow-up item once the vendor
  question below is answered; this item's own `ISmsSender` port is exactly what makes that follow-up
  cheap (implement the interface, wire it up via configuration, nothing else in this item's own code
  changes).
- Delivery-receipt handling, retry-on-gateway-failure beyond what `Ago.Platform.Resilience`'s generic
  mechanism already provides once wrapped — a real gap for the real adapter to name, not this item's.
- Any Inbox-side reuse question (`14-03`'s own SMS *channel* adapter is a different, bidirectional
  concern — receiving arbitrary conversation messages, not sending one fixed confirmation template);
  state explicitly, once both items exist, whether they end up sharing one gateway account/adapter or
  stay independent, but do not resolve that question in this item.

## Done when

- [ ] `Ago.Calendar.Integration.Tests`, real Postgres + real RabbitMQ: a `BookingConfirmed` event
      results in exactly one call to the fake `ISmsSender`, with the customer's real phone number and a
      real confirmation text — proven end to end, not asserted from the handler alone.
- [ ] A redelivered `BookingConfirmed` (same `MessageId` twice) does not double-send — proven with a
      forced redelivery against the real inbox-table check.
- [ ] `docs/architecture/messaging.md` gains `ISmsSender`'s port shape and this consumer's entry in
      whichever "Topics"-equivalent table `ago-calendar`'s own docs end up using (per `20-01`'s open
      item on doc placement).

## Open questions

**Which real SMS gateway to integrate, and its real per-message price** — genuinely open, deliberately
not invented here. `CLAUDE.md`'s own rule against inventing numbers applies directly to a figure that
would understate or overstate a real recurring cost. A future item (or this item's own follow-up, once
answered) should do the same kind of real, cited research `adr/0026` did for VPS hosting — current
pricing for a Russian-market SMS gateway (matching this project's own established Russian-hosting/
payment-provider constraints, `adr/0026`'s "Real payment constraint" section) — before the real adapter
is built, and record the finding in a new small ADR the same way `adr/0026` recorded VPS pricing, rather
than guessing at a number here.
