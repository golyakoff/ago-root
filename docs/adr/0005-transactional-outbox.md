# ADR-0005: Transactional outbox for reliable publishing

- **Status**: Accepted
- **Date**: 2026-08-20
- **Stage**: 2

## Context

An acknowledged message must never be lost. Writing to PostgreSQL and publishing to the broker are
two systems: doing both inside a request handler means one can succeed while the other fails, and no
atomic operation spans them.

## Decision

The state change and an `outbox` row are written in **one transaction**; the client is acknowledged
only after it commits. A dispatcher in `Ago.Chat.Worker` claims unpublished rows with
`FOR UPDATE SKIP LOCKED`, publishes, and marks them published. Consumers are idempotent and
deduplicate through an `inbox` ledger, because this yields at-least-once, never exactly-once.

## Consequences

- The durability guarantee becomes provable: kill anything, restart, nothing acknowledged is lost.
- Multiple dispatcher replicas are safe by construction - no leader election.
- Cost: end-to-end latency gains the dispatch interval. Mitigated by poll-plus-notify instead of a
  fixed poll, and measured in Stage 7, since it lands directly in the p95 target.
- Cost: outbox growth needs pruning, which becomes a maintenance job with its own runbook entry.

## Alternatives considered

- **Publish directly from the handler** - one less moving part and a guaranteed silent-loss window
  the first time the broker blips.
- **Two-phase commit across DB and broker** - poor real-world support, operationally fragile, slower
  than the problem deserves.
- **Change Data Capture (Debezium)** - genuinely good and genuinely heavier: another deployed system
  and a very different local-dev story, for a guarantee the outbox already provides.
