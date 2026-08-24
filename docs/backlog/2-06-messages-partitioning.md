# messages: partition by created_at, with ahead-of-time partition creation

- **Stage**: 2
- **Status**: done
- **Depends on**: `1-04-postgres-persistence.md` (independent of `2-01`..`2-05` - no messaging code
  touches this; can be done in parallel with the outbox chain)

## Goal

`messages` is `PARTITION BY RANGE (created_at)`, monthly, per `data-model.md`, with partitions for the
current and next month always present before they are needed - never created reactively on first
insert into a month that has no partition yet (which would fail the insert).

## Context to read first

`docs/architecture/data-model.md`'s Partitioning section (rationale: bounded index size, cheap
retention via `DROP PARTITION`), its Migrations section (reversibility rules, raw SQL via
`migrationBuilder.Sql`), `docs/conventions/concurrency.md`'s `BackgroundService`/`PeriodicTimer` rules
for the maintenance job.

## Scope

- A migration converting `messages` to a partitioned table. Postgres cannot `ALTER TABLE` a regular
  table into a partitioned one in place - the migration recreates it (rename old table, create the
  partitioned table with the same shape/indexes/FKs, copy rows, drop the old table). Mark this
  migration explicitly one-way with a comment explaining why, per `data-model.md`'s own rule for
  exactly this situation - do not attempt a reversible down-migration that would have to reassemble a
  non-partitioned table from partitions.
- Initial partitions: current month and the next two, created by the migration itself so a fresh
  environment (including CI's Testcontainers Postgres) never starts with zero partitions.
- A `PartitionMaintenanceJob` (`BackgroundService` in `Ago.Chat.Worker`, `PeriodicTimer`, runs daily)
  that ensures the current month plus the next two always have partitions, creating any that are
  missing. Idempotent by construction (`CREATE TABLE IF NOT EXISTS` per partition), so a missed run or
  an overlapping run under multiple `Worker` replicas is harmless.
- The unique `(conversation_id, sequence)` index and both existing FKs must still hold across
  partitions after the conversion - a test proves the constraint still rejects a duplicate insert
  post-partitioning, not just pre-partitioning (`1-04` already proved it before this item; this item
  must not silently lose that guarantee).

## Out of scope

- Retention / dropping old partitions - `data-model.md` names `DROP` as the cheap-retention mechanism
  this enables, but no stage has committed to an actual retention policy or schedule yet. Do not invent
  one; leave partitions accumulating until a real requirement names a window. **That requirement arrived
  2026-08-24**: a 2Gi volume on a one-node public deployment, and `15-04-retention-and-pruning-jobs.md`
  is where the drop schedule gets built - still not here.
- Partitioning any other table - only `messages` is named in `data-model.md`.

## Done when

- [x] `Ago.Chat.Integration.Tests` (real Postgres): the migration applies cleanly to a fresh database,
      inserts landing in the current month succeed, and the `(conversation_id, sequence)` unique
      constraint still rejects a duplicate insert after partitioning. (`MessagePartitioningTests`,
      `MessageUniqueSequenceTests` - the unique index widened to `(conversation_id, sequence,
      created_at)`, a documented trade-off, `adr/0019`.)
- [x] A test for `PartitionMaintenanceJob`: run it against a database missing next month's partition,
      assert the partition now exists; run it again immediately, assert no error and no duplicate
      partition (idempotency under a second, concurrent-simulated run).
      (`PartitionMaintenanceJobTests`.)
- [x] `docs/architecture/data-model.md`'s Partitioning section updated from "introduced in Stage 2"
      (forward-looking) to a statement of what actually shipped, matching how `1-04` closed out schema
      documentation.
- [x] `docs/runbooks/local-dev.md` checked: no change needed, since `dotnet run --project
      Ago.Chat.Worker` already starts every `BackgroundService` in that host, `PartitionMaintenanceJob`
      included, once it is registered in `Program.cs`.

## Open questions

None.
