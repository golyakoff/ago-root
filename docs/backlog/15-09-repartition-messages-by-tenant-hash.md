# Repartition `messages` by tenant hash, and rebuild what depended on the monthly grid

- **Stage**: 15
- **Status**: ready
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

- [ ] A conversation-history read touches exactly one partition, proven by `EXPLAIN` in a test rather
      than asserted.
- [ ] A tenant search touches exactly one partition, proven the same way.
- [ ] Every query in either backend that reads `messages` is audited for a `site_id` predicate, and the
      audit is written into the report — including the ones that turn out not to need one and why.
- [ ] Retention still removes expired messages and still archives before removing, proven by the
      existing archive/prune tests adapted rather than deleted.
- [ ] `PartitionMaintenanceJob` no longer exists, and no test references it.
- [ ] The full suite is green **run on a day near a month boundary** — the failure this removes was
      date-dependent, so a green run alone does not prove it gone; a test seeding a message dated
      well into the past must pass regardless of today's date.

## Open questions

- Whether `MessageArchiveJob`'s own object-key layout (`archive/messages/{siteId}/{class}/{period}.zip`)
  still makes sense when a period is no longer a physical partition. Probably yes — the key is a
  logical grouping, not a partition name — but confirm rather than assume.
