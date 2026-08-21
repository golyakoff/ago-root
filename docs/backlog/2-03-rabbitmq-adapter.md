# Ago.Platform.Messaging.RabbitMq: the port, implemented for real

- **Stage**: 2
- **Status**: done - built in a separate `git worktree` (`feat/2-03-rabbitmq-adapter`, stacked on
  `2-01`'s branch) so `2-01`'s own branch stayed untouched and ready to commit independently.
  `Ago.Platform.Integration.Tests` 12/12 against a real Testcontainers RabbitMQ (`rabbitmq:4-management`)
  and Postgres together, `Ago.Platform.Tests` 11/11, `Ago.Platform.Architecture.Tests` 2/2 (including
  the extended "no `Ago.Chat.*` reference" rule), `dotnet pack` produces
  `Ago.Platform.Messaging.RabbitMq.0.2.0.nupkg` alongside the other four packages, `dotnet format
  --verify-no-changes` clean. **One deliberate scope reduction versus this file's original wording**:
  `EventEnvelope` has no `Topic` field (that was this file's own inaccuracy - `2-01` shipped `Type`,
  matching `messaging.md`'s exact field list; fixed below). More substantively, the adapter uses one
  fanout exchange per topic with a single shared queue for `Competing` mode, not the N-queue
  consistent-hash topology `concurrency.md` describes for per-key ordering at scale - ordering holds
  trivially with one queue, but the throughput-scaling design is deferred; see the code remarks on
  `RabbitMqEventConsumer` and revisit when Stage 4's ordering work needs it.
- **Depends on**: `2-01-platform-outbox-inbox-and-messaging-port.md`

## Goal

`IEventPublisher`/`IEventConsumer` (`2-01`) have a real adapter that talks to an actual RabbitMQ
broker - publish-confirmed, ack/nack/dead-letter all real, `Competing` vs `Broadcast` subscription
actually different queue topologies. Still no product code touched: this proves the adapter against
the port in isolation, the same way `2-01` proved the outbox writer in isolation.

## Context to read first

`docs/architecture/messaging.md` (the "known leaks" section - RabbitMQ-specific behaviour this adapter
owns and hides), `docs/adr/0006-broker-abstraction.md`, `docs/architecture/resilience.md`'s row for
"RabbitMQ / Kafka" (timeout, retry with jittered backoff, publisher confirms).

## Scope

- `Ago.Platform.Messaging.RabbitMq`: `RabbitMqEventPublisher` using **publisher confirms** (not
  fire-and-forget publish - `resilience.md` names this explicitly), mapping `EventEnvelope.Type` to
  a fanout exchange (one per topic) and carrying `PartitionKey` as the message's routing key for a
  future sharded topology, even though a single shared queue makes routing-key-based delivery
  unnecessary today (see Status for the honest scope note on this).
- `RabbitMqEventConsumer`: explicit ack/nack(requeue)/dead-letter, retry policy via a delay/retry
  exchange per subscription (attempts, backoff - configured per subscription, not hardcoded).
  `Competing` mode is an ordinary shared queue; `Broadcast` mode is a fanout exchange with a
  per-node exclusive queue (`messaging.md`'s `CacheInvalidated` row is the example, though nothing
  uses `Broadcast` until later stages - the mode must exist and be tested even with no caller yet,
  since it is part of the port contract from `2-01`, not new scope).
- `RabbitMqOptions` bound from `Messaging:RabbitMq:*` config keys (`PrefetchCount` etc named in
  `naming-and-structure.md`'s example), validated at startup.
- Connection/channel lifecycle: one connection, channels per publisher/consumer as RabbitMQ.Client
  best practice requires, automatic recovery on connection loss (`resilience.md`: "outbox accumulates
  while it is down" - the adapter must resume cleanly when the broker returns, not require a restart).

## Out of scope

- Wiring this into `Ago.Chat.Worker` - that is `2-04`. This item's tests exercise the adapter directly
  against a Testcontainers RabbitMQ, not through any product host.
- Kafka adapter - Stage 9.
- Circuit breaker / bulkhead around the broker call - that is `Ago.Platform.Resilience`, Stage 6.
  Timeout and retry-with-backoff on the publish path are in scope here (`resilience.md`'s table lists
  them for this boundary now, circuit breaker is not listed for this boundary at all - Postgres and
  webhooks get breakers, RabbitMQ/Kafka does not).

## Done when

- [x] `Ago.Platform.Integration.Tests` (Testcontainers RabbitMQ): publish-then-consume round-trip,
      `Competing` mode with two consumers only one of which gets each message, `Broadcast` mode with
      two consumers both getting every message.
- [x] A test stops the RabbitMQ container mid-publish and asserts the publisher surfaces a retryable
      failure rather than hanging or throwing an unhandled exception.
- [x] A test proves nack-with-requeue redelivers, and dead-letter after N attempts lands the message
      (with its envelope) on the configured DLQ, not silently dropped.
- [x] `Ago.Platform.Architecture.Tests` green - this adapter references `Ago.Platform.Abstractions`
      only, never `Ago.Chat.*`.

## Open questions

None.
