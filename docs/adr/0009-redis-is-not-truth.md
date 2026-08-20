# ADR-0009: Redis is a cache and coordination store, never truth

- **Status**: Accepted
- **Date**: 2026-08-20
- **Stage**: 3

## Context

Redis ends up holding cache entries, rate-limit counters, the connection registry and presence. It is
tempting to also let it hold things like an operator's current chat count, because that read sits in
a hot path.

## Decision

Nothing in Redis is authoritative. Every key is either a copy of PostgreSQL data (with TTL and an
invalidation story), an ephemeral runtime fact (presence, connection ownership), or a counter whose
loss is acceptable (rate limits fail open to the next window). **No value read from Redis may be used
in a compare-and-set that decides a write** - capacity checks happen in the database, inside the
transaction.

## Consequences

- `FLUSHALL` is survivable: the system degrades (cache misses, reconnects, stale presence) and
  recovers by itself. This is a Stage 7 test scenario, not a thought experiment.
- The cache layer can be added, removed or bypassed without a correctness review.
- Cost: some hot paths pay a database round trip a cached value could have served - deliberately, and
  only where a stale value would be a correctness bug.

## Alternatives considered

- **Redis as the presence/capacity source of truth with periodic persistence** - faster, and it makes
  every race condition invisible until production. It is the most common way portfolio projects
  acquire silent data corruption.
