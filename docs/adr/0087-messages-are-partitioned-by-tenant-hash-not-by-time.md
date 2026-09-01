# ADR-0087: `messages` is partitioned by tenant hash, not by time

- **Status**: Accepted
- **Date**: 2026-09-02
- **Amends**: `adr/0031` (its partition-key half — the retention *policy* stands, its *mechanism* changes),
  `adr/0019` (the unique-index widening, which follows whatever the partition key is)
- **Supersedes in practice**: `2-06`/`13-06`'s own monthly grid

## Context

`messages` is today `PARTITION BY LIST (retention_class)`, each class `PARTITION BY RANGE (created_at)`
monthly (`2-06`, then `13-06`/`adr/0031`). That shape was chosen for one reason, stated plainly in
`adr/0031`: retention by `DROP PARTITION` — instant, no bloat, no vacuum pressure, and an archive
boundary that is naturally a whole table.

Read behaviour was never the reason, and checking it against the real code shows what that cost:

- **`ConversationReadStore.GetHistoryAsync` — the most frequent query in the product, one per
  conversation open — filters on `conversation_id` alone.** No `created_at`, no `site_id`. Against a
  table partitioned by `created_at`, that means **no pruning at all**: Postgres visits every leaf
  partition, three retention classes wide and as many months deep as retention keeps. Each visit is an
  index lookup rather than a scan (`conversation_id` leads the unique index), so this is not
  catastrophic — but the hottest path in the system gets nothing from the partitioning it pays for.
- **`ConversationSearchStore.SearchAsync` does prune**, because `from`/`to` are mandatory parameters —
  but only on the time axis. It never filters `retention_class`, so it fans out across all three class
  subtrees for every window it touches.

Two further facts made this the moment to decide rather than defer. There are **no live clients and no
data to migrate** — the cheapest this change will ever be. And the monthly grid has a standing failure
mode: partitions are created looking *forward* only, so any CI run in the first days of a calendar
month rejects inserts dated a few days earlier (`23514: no partition of relation "messages_free" found
for row`, which broke `ago-chat`'s CI on 2026-09-01 and would have recurred every month).

## Decision

**`messages` is partitioned by `HASH (site_id)` into a fixed number of buckets, with no time
dimension.**

- **`retention_class` leaves the partition key** and stays an ordinary column. It still decides how long
  a message lives; it no longer decides where the row is stored.
- **Bucket count is fixed at 64, chosen at creation and not changeable afterwards** without a full
  rehash-and-copy. 64 is a power of two, so a later shard split divides cleanly (64 → 32 → 16 → …), and
  the bucket → shard mapping is the whole point of choosing a tenant hash over anything else. The
  number is *not* justified by a measurement: with zero clients there is nothing to measure, and
  inventing a figure here would be exactly the fabricated benchmark this project's own rules forbid. It
  is justified by splittability, and by being small enough that the fan-out cost of a query that
  *forgets* to filter `site_id` stays bounded.
- **Every query that reads `messages` must filter `site_id`.** This is what converts the decision into
  the win: `GetHistoryAsync` gains a `site_id` predicate (its caller already loads the `Conversation`,
  which carries `SiteId`), and both dominant queries then prune to exactly one partition. A query
  without a `site_id` predicate silently touches all 64 — the failure mode is a performance cliff, not
  an error, so it has to be caught by review and by test rather than by the type system.
- **Retention becomes a `DELETE` sweep** rather than `DROP PARTITION`. `adr/0031`'s policy — that a
  message's retention class is immutable, that archiving moves the liability rather than ending it —
  is unchanged. Only the mechanism that enforces it changes.
- **`PartitionMaintenanceJob` is deleted.** With no time axis there is nothing to maintain: the 64
  buckets are created once, by the migration, and never again.

## Consequences

- **Positive, and the reason for the change**: both dominant read paths prune to one partition. The
  conversation-history query goes from touching every leaf partition to touching exactly one.
- **Positive**: partition count becomes a constant — 64, forever, independent of tenant count *and* of
  elapsed time. The alternative the author initially proposed (a partition per tenant) would have grown
  as tenants × months; the current design grows as 3 × months. This grows as neither.
- **Positive**: an entire bug class disappears structurally, not by a fix. There is no month boundary,
  so there is no look-back window to get wrong, and the CI failure that prompted this discussion cannot
  recur. A pending fix for that failure (`fix/partition-maintenance-look-back`) is discarded unmerged
  as a result — the right outcome for a fix to a mechanism being removed.
- **Positive**: buckets are a real shard key. Nothing in this decision performs sharding, but it stops
  being a change with no natural boundary to cut along.
- **Negative, and the price paid deliberately**: retention loses `DROP PARTITION`. A `DELETE` sweep is
  slower, generates more WAL, marks rows dead rather than reclaiming space, and needs `VACUUM` to
  actually return disk. On the highest-volume, highest-sensitivity table either product has, this is a
  real operational regression, accepted because read behaviour was judged to matter more.
- **Negative**: `adr/0031`'s archive-then-drop machinery (`MessagePartitionPruneJob`,
  `MessagePartitionPruneQuery`, `MessageArchiveJob`, `MessageArchiveGate`) is built around a leaf
  partition being one class-month. All of it needs rework, and `MessagePartitionPruneQuery`'s
  `pg_partition_tree` walk stops meaning what it meant.
- **Negative**: a bucket grows without bound. Each holds 1/64 of every message ever written, with no
  cold-and-closed old partitions for autovacuum to skip. The full-text GIN index per bucket grows with
  it.
- **Negative**: 64 is now a one-way door. Changing it later is a rehash of the whole table.
- **Consequence for `adr/0019`**: its rule is unchanged — Postgres still requires the partition key
  inside every unique constraint — but what that means changes. The primary key and both unique indexes
  drop `created_at`/`retention_class` and take `site_id` instead, which is a *narrower* widening than
  the one `adr/0019` had to accept, and restores `(conversation_id, sequence)` uniqueness to something
  the database enforces within a tenant rather than something the application is trusted for.

## Alternatives considered

- **Keep `RANGE (created_at)`, with or without the class level.** Rejected: for reads it is pure cost,
  and the author's own argument for changing — unbounded partition growth on long-lived accounts — cuts
  against it rather than for it, since time is the axis that grows forever while tenant-hash buckets do
  not.
- **`HASH (site_id)` → `RANGE (created_at)`.** The obvious compromise: keeps `DROP`-based retention,
  still prunes the tenant axis. Rejected because it keeps the maintenance job and its whole failure
  class, and because the history query — which has no time predicate to give — would still fan out
  across every month. It buys back retention at the cost of the larger half of the prize.
- **`LIST (site_id)`, one partition per tenant.** Rejected: DDL on every tenant signup, and partition
  count growing as tenants × months, which is the growth the author was trying to avoid in the first
  place.
- **Leave the key alone and add `retention_class` to the search query's `WHERE`.** A genuinely cheaper
  fix, weighed seriously: it would collapse the search's 3× class fan-out for the price of one SQL
  change. Rejected because it does nothing for the conversation-history query, which is both more
  frequent and worse off, and because it needs a reliable list of which classes a given site actually
  has rows in — a site that changed tier has two, and guessing from the current tier would silently
  drop search results.
