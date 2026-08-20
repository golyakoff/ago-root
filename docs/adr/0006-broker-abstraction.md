# ADR-0006: Broker abstraction at topic + partition key + at-least-once

- **Status**: Accepted
- **Date**: 2026-08-20
- **Stage**: 2

## Context

Swapping RabbitMQ for Kafka by configuration is a stated goal. Their models genuinely differ:
exchanges/queues/bindings versus topics/partitions/consumer groups; per-queue versus per-partition
ordering; no replay versus offset replay.

## Decision

The port exposes exactly the intersection that both can honour without lying: **topic, partition key,
at-least-once delivery, explicit ack/nack/dead-letter**, plus a declared subscription mode
(`Competing` or `Broadcast`) and a retry policy. Exchanges, bindings, consumer groups, offsets and
partition counts stay inside the adapters. Ordering is guaranteed per partition key only, which is
what `concurrency.md` depends on.

## Consequences

- Application code expresses intent, and Stage 9 proves the swap with a green run on both brokers.
- Known leaks are documented in `messaging.md` rather than discovered late: parallelism is configured
  per adapter, replay exists only on Kafka, ordering scope is equivalent for our key but not in general.
- Cost: Kafka-specific strengths (compaction, long retention, replay-driven rebuilds) are unavailable
  through the port. Anything needing replay must be rebuildable from PostgreSQL instead.

## Alternatives considered

- **A generic `IMessageBus.Send(object)`** - looks cleaner, hides ordering and acknowledgement, and
  makes the ordering guarantee unimplementable. It leaks *silently*, which is worse than leaking loudly.
- **MassTransit** - a mature answer to this exact problem, and the correct choice for production work
  with a deadline. Rejected here deliberately: it would supply the interesting part (outbox, retries,
  dead-lettering, ordering) as a black box, and demonstrating that competence is the point. The
  README states this explicitly so the choice does not read as ignorance.
