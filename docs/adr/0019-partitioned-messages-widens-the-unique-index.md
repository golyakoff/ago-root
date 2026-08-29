# ADR-0019: Partitioning `messages` widens its unique index to include `created_at`

- **Status**: Accepted
- **Date**: 2026-08-21
- **Stage**: 2

## Context

`data-model.md` names `2-06` as the item that partitions `messages` `PARTITION BY RANGE (created_at)`,
monthly - bounded index size and cheap retention via `DROP PARTITION`, per the rationale already
committed to before this item existed.

Postgres enforces a hard rule on any `RANGE`- or `LIST`-partitioned table: every unique constraint,
primary key included, must include all of the partition key's columns. The reason is structural, not
a missing feature - each partition only enforces uniqueness within itself via its own local index;
nothing checks across partitions, so the only way Postgres can still promise "this constraint holds
table-wide" is by requiring the partition key to be part of what makes a row unique in the first
place.

`messages` has two constraints that collide with this rule: the primary key (`id` alone today) and
the unique index `(conversation_id, sequence)` that `concurrency.md` calls the ordering guarantee's
"last line of defence" - an out-of-order or duplicate `sequence` is supposed to be caught here if it
gets past everything upstream.

## Decision

- The physical primary key becomes `(id, created_at)`. `MessageId` (UUID v7) never collides in
  practice regardless, so this changes nothing about how a row is identified - it only satisfies
  Postgres's requirement. `MessageConfiguration`'s EF-level `HasKey` deliberately stays `id`-only
  (see its own comment): EF never validates a `DbContext`'s model against the live schema, and
  mirroring the physical composite key into the C# model would drag composite-key ceremony into
  every place a `Message` is tracked, for no behavioural gain.
- The unique index becomes `(conversation_id, sequence, created_at)`. This is a real, deliberate
  weakening: two inserts racing to claim the same `(conversation_id, sequence)` pair no longer
  collide at the storage level if they land with different `created_at` values - which, once messages
  span more than one partition, they usually will.
- The primary defence against that race was never this index. `Conversation.LastSequence` is
  incremented in memory and persisted through the aggregate's normal load-mutate-save cycle, which
  uses Postgres's `xmin` for optimistic concurrency (`data-model.md`'s `conversations` entry). Two
  concurrent saves computing the same `LastSequence` already means one of them loses the `xmin` check
  and throws, before either one's `INSERT` into `messages` happens. The unique index was always a
  storage-level backstop for whatever got past that - a bug that bypasses the aggregate, most
  plausibly - not the mechanism actually relied upon in the normal path.
- Both migrations (`Stage2PartitionMessages`) and the ongoing maintenance job
  (`PartitionMaintenanceJob`) create the physical DDL by hand via raw SQL / raw `NpgsqlCommand`s.
  Neither `PARTITION BY RANGE` nor `PARTITION OF` has an EF Core fluent-API shape at all, so this was
  never a choice between "EF-native" and "raw SQL" - only raw SQL can express it.

## Consequences

- The uniqueness guarantee this index provides is now scoped to "within one partition, or across
  partitions if `created_at` also happens to match" rather than "across the whole table,
  unconditionally." A conversation whose messages happen to straddle a month boundary is the
  realistic case where this matters, and it is now only caught upstream (the aggregate's optimistic
  concurrency), not at the storage level too.
- A future feature that mutates an existing `Message` by `id` alone (marking it delivered or read -
  `data-model.md` names both columns as not yet implemented) would need `created_at` in its lookup
  too, or pay for a scan across every partition: there is no longer an index that serves `id` alone
  efficiently. Not a problem today - messages are insert-only in every use case that exists - but
  worth knowing before adding one.
- `MessageConfiguration`'s EF model (`HasKey(m => m.Id)`) permanently diverges from the physical
  primary key (`(id, created_at)`). Harmless in practice (EF never reads the live schema to validate
  against), but a reader of that file alone would not know the physical shape differs without its
  comment - which is why that comment exists.

## Alternatives considered

- **A separate, non-partitioned sequence-allocator table** (`message_sequences(conversation_id,
  sequence) UNIQUE`, written in the same transaction) to keep a genuinely global, partition-spanning
  uniqueness guarantee. Rejected: it is a second table and a second write path for a guarantee the
  aggregate's optimistic concurrency already provides as the primary mechanism: this ADR's whole point
  is that the `messages` index was always the backstop, not the guarantee itself, so paying for a
  second table to keep the backstop at full strength is solving a problem the architecture does not
  actually have.
- **Do not partition `messages` at all**, keeping the single global unique index intact. Rejected:
  `data-model.md` already committed to partitioning before this item existed, for reasons (bounded
  index size, cheap retention) unrelated to this trade-off - reopening that decision here would be
  solving the wrong problem.
- **Keep two indexes**: the existing `(conversation_id, sequence)` as a plain non-unique index (for
  the query pattern) plus the widened `(conversation_id, sequence, created_at)` as the enforcing
  unique one. Rejected: query plans already use the unique index for the equality-on-conversation
  lookup pattern this table has today, so a second index would only add write overhead without
  serving a query the first one does not already serve.

## Addendum (2026-08-29) — widened a second time by `13-06`

`13-06`/`adr/0031` repartitions `messages` a second time — `PARTITION BY LIST (retention_class)` on
top of this ADR's own `PARTITION BY RANGE (created_at)` — and the consequence this ADR already argued
for applies once more, unchanged in kind: the physical primary key becomes
`(id, created_at, retention_class)` and the `(conversation_id, sequence, created_at)` unique index
widens to `(conversation_id, sequence, created_at, retention_class)`. Nothing in this ADR's own
Decision or Alternatives needed to be reopened — `adr/0031`'s own Consequences section states this
widening as "a further weakening of the same backstop, not a new kind of risk," which is this ADR's
own argument, reapplied rather than replaced. `MessageConfiguration`'s `HasKey(m => m.Id)` divergence
(this ADR's own second bullet) stays exactly as documented.

This is now the ADR every future partition-key widening on `messages` should extend, rather than
restate.
