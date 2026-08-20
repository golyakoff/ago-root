# ADR-0004: PostgreSQL, EF Core for writes, Dapper for reads

- **Status**: Accepted
- **Date**: 2026-08-20
- **Stage**: 1

## Context

Writes are aggregate-shaped, need a transaction shared with the outbox, and benefit from change
tracking and migrations. Reads are list-shaped and latency-critical: keyset-paginated history and hot
handshake lookups. One tool doing both well is unlikely.

## Decision

PostgreSQL is the only source of truth. EF Core owns the write path (aggregates, transactions,
migrations, outbox rows in the same transaction). Dapper owns the read path behind explicit read
ports (`IConversationReadStore`) returning DTOs from hand-written SQL.

## Consequences

- Read queries are reviewable SQL with predictable plans, and pagination stays keyset-based instead
  of an `OFFSET` that dies exactly where the demo is supposed to shine.
- The aggregate stays a write-side consistency tool, which is what it is for.
- Cost: two mapping mechanisms, and SQL that a migration can break silently. Mitigation: read stores
  are covered by integration tests against a real Postgres.
- Cost: this is CQRS-flavoured without event sourcing; say so explicitly so nobody assumes the latter.

## Alternatives considered

- **EF Core for everything** - fewer moving parts, but read plans become an argument with the
  provider, and the project loses its concrete place to demonstrate query and index work.
- **Dapper for everything** - full control, no migration story, hand-rolled change tracking; the
  write path gets worse in exchange for nothing the read path did not already have.
- **A document store for messages** - tempting for append-heavy data, but it trades away the
  transactional outbox, which is the more valuable thing to demonstrate.
