# Repartition `messages` by tenant hash, and rebuild what depended on the monthly grid

- **Stage**: 15
- **Status**: done (`ago-chat#147`, merged 2026-09-02) — see Outcome below
- **Decided by**: `adr/0087` — read it first; this item builds what that ADR decided, and does not
  re-open the choice.
- **Amends in code**: `2-06`/`13-06`'s own monthly partition grid, `adr/0031`'s retention *mechanism*
  (its policy is unchanged), `adr/0019`'s unique-index shape.

## Why now, in one line

There are no live clients and no data to migrate — the cheapest this change will ever be — and the
monthly grid has a standing monthly-recurring CI failure that this removes structurally rather than
patches.

## What already exists, checked before scoping

- `messages` is `PARTITION BY LIST (retention_class)` → `PARTITION BY RANGE (created_at)` monthly.
- `ConversationReadStore.GetHistoryAsync`/`GetDeltaAsync` filter `conversation_id` only — **no pruning
  at all** today, on the product's most frequent query.
- `ConversationSearchStore.SearchAsync` filters `site_id` + a mandatory `from`/`to` window, so it prunes
  on time but fans out across all three retention classes.
- `PartitionMaintenanceJob` (+ its options and tests) creates the monthly grid forward-only. A pushed,
  green, unmerged branch (`ago-chat` `fix/partition-maintenance-look-back`) fixes its look-back gap and
  is **discarded** by this item rather than merged — it fixes a mechanism this item removes.
- `MessagePartitionPruneJob`, `MessagePartitionPruneQuery` (walks `pg_partition_tree`),
  `MessageArchiveJob`, `MessageArchiveGate` all assume a leaf partition is one class-month.
- `MessageSearchIndexJob` builds `(site_id, created_at)` + full-text GIN per leaf partition.
- `PlatformOverviewFixture` creates its own partitions by name for a `-95`-day test.

## Scope

- **The repartition itself**: `PARTITION BY HASH (site_id)`, 64 buckets, no time dimension.
  `retention_class` stays as an ordinary column. One migration, create-copy-drop, following
  `Stage2PartitionMessages`'s own established shape.
- **Keys and indexes**: PK and both unique indexes take `site_id` and drop
  `created_at`/`retention_class`, per `adr/0019`'s rule applied to the new key.
- **Every query touching `messages` gains a `site_id` predicate** — starting with `GetHistoryAsync`/
  `GetDeltaAsync`, whose callers already hold the `Conversation` and therefore its `SiteId`. This is
  what makes the ADR's win real rather than theoretical; a query without it silently visits all 64
  buckets.
- **`PartitionMaintenanceJob` and its options/tests are deleted.**
- **Retention reworked to a `DELETE` sweep**, preserving `adr/0031`'s policy exactly: retention class
  immutable, archive before removal, the archive gate still gating. Only the removal mechanism changes.
- **`MessageSearchIndexJob`** builds its indexes per bucket instead of per class-month.
- **Docs updated in the same change**: `data-model.md`'s Partitioning section, and any
  `personal-data.md` row whose "what removes it" column names a partition drop.

## Out of scope

- Actual sharding. This item makes buckets a usable shard key; it does not split anything.
- Changing retention *windows* — still `13-05`'s own blocked business decision.
- `messages_free`-era historical data migration beyond what the create-copy-drop migration does.

## Done when

- [x] A conversation-history read touches exactly one partition, proven by `EXPLAIN` in a test rather
      than asserted. **18 → 1.**
- [x] A tenant search touches exactly one partition, proven the same way. **18 → 1.**
- [x] Every query in either backend that reads `messages` is audited for a `site_id` predicate, and the
      audit is written into the report — including the ones that turn out not to need one and why.
- [x] Retention still removes expired messages and still archives before removing, proven by the
      existing archive/prune tests adapted rather than deleted.
- [x] `PartitionMaintenanceJob` no longer exists, and no test references it.
- [x] The full suite is green **run on a day near a month boundary** — verified on 2026-09-02, two days
      into a month, which is exactly when the removed failure used to bite.

## Outcome

Built and merged 2026-09-02 (`ago-chat#147`). Independently re-verified by the managing session:
1885/1885, all 7 assemblies confirmed present (Domain 424, Application 634, Architecture 40, FakeCrm 21,
Concurrency 38, Integration 728; FakeMax discovers 0, pre-existing), `dotnet format`/build clean, zero
warnings. CI green.

**The pruning proof, which is the whole point of the item**: `MessagePartitionPruningExplainTests` runs
`EXPLAIN` against the *real production SQL* (`internal` via `InternalsVisibleTo` — a hand-copied
approximation could drift from what ships and keep passing), with a **negative control** proving an
unscoped query still touches all 64 buckets so the assertion cannot pass vacuously. Independently
re-proven by the managing session: neutralising the `site_id` predicate in `ConversationReadStore.Sql`
produced a plan naming every bucket `messages_00`…`messages_63`, one index scan each — the exact
degradation this item removes — then restored byte-identical and re-verified.

**`adr/0031`'s policy confirmed intact by reading `MessagePartitionPruneJob` directly**, not taken on
report: the archive gate is checked before any delete, an unconfirmed slice is left in place and logged,
and referenced attachments are read *before* the rows go (once deleted there is no way left to ask which
attachments they referenced).

**Three jobs deleted**: `PartitionMaintenanceJob` (nothing to maintain — 64 buckets, fixed forever),
`MessageSearchIndexJob` (moved into the migration), `MessageSiteIdBackfillJob` (`site_id` is now
`NOT NULL`).

**Beyond the item's literal scope, judged necessary and named**: `site_id` made `NOT NULL`. `HASH`
partitioning permits `NULL`, and a `NULL` row would be permanently unreachable by every `site_id`-scoped
query this item exists to make fast. The repartition migration already joined every row to
`conversations`, so closing it cost nothing extra.

**A correction the implementer found by running rather than reasoning**: Postgres does *not* allow
`CREATE INDEX CONCURRENTLY` on a partitioned parent table (`0A000`). Fixed by looping per bucket, and
the wrong claim corrected in four places rather than left standing.

**One flake reported honestly rather than re-run away**: a second local full-suite run had
`ConversationAssignmentFanoutEndToEndTests` time out on cross-node RabbitMQ delivery. It passes in 1s in
isolation, passed in the first full run on byte-identical code, and CI was green — resource contention
under a loaded suite, not a defect.

## Open questions

- Whether `MessageArchiveJob`'s own object-key layout (`archive/messages/{siteId}/{class}/{period}.zip`)
  still makes sense when a period is no longer a physical partition. Probably yes — the key is a
  logical grouping, not a partition name — but confirm rather than assume.
