# ADR-0186: Analytics runs on a dedicated event store, not the operational Postgres

- **Status**: Proposed
- **Date**: 2026-09-26
- **Stage**: 18 (Operator productivity) — a scaling follow-up to `18-08`..`18-14`

## Context

AGO Chat's analytics reads (`IOperatorAnalyticsReadStore`, `IConversionReportReadStore`,
`ITagBreakdownReadStore`, `IOperatorLoadReportReadStore`) compute their aggregates on every request. The
site-analytics query runs a `LEFT JOIN LATERAL` per conversation over the 64-way-partitioned `messages`
table plus `GROUP BY GROUPING SETS` across five dimensions; the own-analytics endpoint runs **three** such
site-wide aggregations concurrently to keep one operator's row. The cost is **O(conversations ×
messages-per-conversation) per request**, recomputed on every load, and the aggregate is unindexable
because the aggregate is the answer. The Android «Аналитика» screen timed out (client 499); the query
measured **~0.5 ms** only because the store holds 132 conversations of test data and there are no real
tenants yet. It is fast because there is nothing to aggregate.

Forces this must live with:

- **The operational Postgres is the platform's scaling bottleneck**, and the rest of the platform is built
  to protect it: `concurrency.md`'s contended-assignment path, `caching.md`, and rule 8 all exist to keep
  load off it. Analytics is a read concern that consults no write decision (rule 8 does not bite), so its
  storage and its heavy aggregation do **not** have to live on that instance — and given the bottleneck,
  should not.
- **Raw events must be retained, write-only, with no lossy pre-quantization.** The author wants to build
  new reports later by slicing raw events (by hour, segment, funnel). Daily buckets are a *derived* view,
  never the only stored form.
- **The day boundary is the tenant's IANA zone**, not UTC — store each event's UTC instant + the tenant
  zone, roll up by the tenant-local day (`date-and-time.md`). AGO Chat has no per-site zone today (the
  calendar owns zones, `adr/0049`), so one must be added.
- **Eventual consistency is explicitly accepted.** Reports may lag by up to ~1 day. The two requirements
  are that reads are **fast** and that the staleness is **known and displayed** (a `computedAsOf` marker),
  not that data is real-time or query-time-exact.
- The platform already provides a transactional outbox (`adr/0005`), an `OutboxDispatcher`, competing
  consumers with an `inbox` ledger (`adr/0017`), RabbitMQ now / Kafka later behind one abstraction
  (`adr/0006`), MinIO object storage, and EF-for-writes / Dapper-for-reads (`adr/0004`). At-least-once
  delivery is assumed everywhere (rule 5).
- This is a portfolio project with a 1–2-person team pre-launch: a new stateful deployable is a real,
  recurring cost (deploy, PVC, secret, backup, upgrades — `edge.md`, `secrets.md`, `take-a-backup`).

An earlier proposal maintained the rollups **in the operational Postgres** off the outbox. The author
rejected it: it spends the exact resource the platform protects. This ADR replaces that direction.

## Decision

Serve analytics from a **dedicated, off-Postgres event store** holding two layers — raw events plus daily
rollups derived from them — fed through the existing outbox/broker path. Full design, schema, freshness
contract and slice plan: [`docs/design/analytics-precompute.md`](../design/analytics-precompute.md).

1. **The engine is ClickHouse** (single node), a columnar MergeTree store: cheap high-volume batched
   inserts, fast columnar aggregation, raw retention without pre-quantization, arbitrary re-slicing for
   future reports, TTL for retention tiering, and native `BACKUP` to the MinIO bucket already on the stand.
   It sits behind a new Infrastructure adapter (`Ago.Chat.Infrastructure.Analytics`), so the engine is
   swappable and no client leaks into Application or Domain (rule 2).
2. **Raw layer** (`analytics_events`, `ReplacingMergeTree` keyed on `event_id` = outbox `MessageId`): one
   append-only row per analytics fact, carrying the UTC instant, the tenant IANA zone, ids and immutable
   attribution values — never a message body or personal content (`messaging.md`, `personal-data.md`).
   Metrics like first-response seconds are *derived* from the event stream, not pre-stored, so a future
   report can redefine them.
3. **Delivery** is unchanged in shape: state change → outbox in the same transaction (rule 4) → RabbitMQ →
   a new `AnalyticsIngestConsumer` in `Ago.Chat.Worker` that batch-inserts into ClickHouse. New integration
   events (`ConversationStarted` enriched with attribution + tenant zone, `ConversationOutcomeRecorded`,
   `ConversationTagged`/`Untagged`) are added where the input is not already on the broker. The consumer is
   idempotent **without** the Postgres `inbox` ledger — a row per analytics event would be the very load
   being avoided — relying instead on `event_id` dedup in the store plus recompute-from-deduplicated-raw.
4. **A scheduled batch aggregator** (`AnalyticsRollupAggregator`, a `PeriodicTimer` `BackgroundService`,
   default **hourly**, configurable, loosenable to daily) recomputes each dirty `(site, local_day)` —
   including the current partial day — from the deduplicated raw into `analytics_daily_rollups`
   (`local_day = toDate(occurred_at, tenant_zone)`). Recompute-from-raw is idempotent, so at-least-once
   redelivery, out-of-order arrival and late events are all the same operation. Each successful run records
   an `analytics_rollup_runs` row; the **`computedAsOf`** marker returned with every analytics response is
   the last successful run's instant, so staleness is bounded and shown.
5. **Reads** become an O(days) grouped scan over the rollup, behind the analytics read ports whose **query
   signatures are unchanged** (implementations move to the ClickHouse adapter). The one contract change is
   the additive `computedAsOf` field, sourced from a small new `IAnalyticsFreshnessReadStore`.
6. **`sites.time_zone`** (IANA, default UTC) is added to AGO Chat so the publisher can stamp each event's
   tenant zone.
7. A **re-runnable backfill** job rebuilds raw (and thus rollups) from existing Postgres history — the one
   place the old O(N) read still runs, once, offline, off the request path. Operator-load stays
   compute-on-read (its interval-overlap does not reduce to an additive daily counter and it was not the
   timeout culprit).

## Consequences

Positive:

- Analytics reads become fast and O(days), independent of total history — the 499's cause is removed — and
  **the aggregation load leaves the operational Postgres entirely**, which is the whole point.
- Raw events are retained write-only for arbitrary future reports; daily buckets are a cheap derived view,
  rebuildable from raw at any time.
- Recompute-from-deduplicated-raw makes redelivery, out-of-order and late events one idempotent operation,
  and doubles as the reconciliation tool.
- Staleness is bounded by a simple batch cadence and shown to the reader (`computedAsOf`), so eventual
  consistency is honest rather than hidden.

Negative / what gets harder:

- **A new stateful deployable to operate.** ClickHouse is a new pod with its own PVC, a new
  `CLICKHOUSE_PASSWORD` secret (`secrets.md`), a new backup path in `backup.sh` (native `BACKUP` to MinIO,
  named in the backup manifest so a silent omission is caught — `take-a-backup`), and its own upgrades. For
  a 1–2-person team this is the real cost, and it is why the alternative of staying in Postgres was
  attractive.
- **A second datastore to reason about**, eventually consistent with Postgres — a second place personal
  data lives (ids, not content; `personal-data.md` gains a row), where erasure means either accepting
  dangling ids (as `conversation_assignments` already does) or propagating `SiteErased` to delete a
  tenant's analytics rows.
- **The first consumer that does not use the Postgres `inbox` ledger.** Idempotency moves into the store's
  dedup semantics; this is a deliberate divergence from rule 5's usual realisation (not from its intent),
  forced by the "keep load off Postgres" constraint, and must be understood before copying the pattern.
- **A new NuGet** (a ClickHouse ADO.NET provider) and a new ClickHouse DDL/migration path separate from EF.
- **New integration-event contracts** become public promises (`messaging.md` versioning), carrying no
  personal data on the wire; and `sites.time_zone` is a new column with a chosen default.
- **Two reporting shapes coexist** for a while (rollup-backed reads plus the deferred compute-on-read
  operator-load), which is more surface than one uniform mechanism.

## Alternatives considered

- **Rollups in the operational Postgres, maintained off the outbox** (the earlier proposal, now rejected).
  It reused only-existing machinery and kept one source of truth — genuinely the smaller change. Rejected
  because it puts analytics ingestion, a growing raw/fact projection, and aggregation load on the exact
  instance that is already the platform's scaling bottleneck (`concurrency.md`, `caching.md`, rule 8),
  spending the resource the rest of the design protects. Moving analytics off Postgres is the decision.
- **TimescaleDB on a *separate* instance** — hypertables + continuous aggregates, familiar SQL, reusing
  Npgsql/Dapper and `pg_dump` backup. The strongest runner-up, and what a team optimising for tooling
  familiarity would pick. Rejected: it is row-oriented at heart (columnar only via compressed chunks), so
  it loses to ClickHouse on write throughput and scan cost for a wide append-only event log, and it adds a
  *second Postgres flavour* to version and operate — the tooling familiarity is real but does not outweigh
  the fit.
- **Kafka-as-log + an OLAP sink.** Kafka is "later" on this platform (`adr/0006`) and answers no query
  itself, so this is two new systems, not one. Rejected: doubles the new-infra count and still needs a
  query engine on the end.
- **Elasticsearch / OpenSearch.** A search engine, not a columnar OLAP one; aggregations are memory-hungry
  and it is the heaviest to operate (JVM heap, shards) for this team size. Rejected on shape and ops
  weight.
- **Druid / Pinot.** Purpose-built real-time OLAP, but multi-component (coordinator/broker/historical/…) —
  built for a scale and an operations team this project is nowhere near. Rejected on ops weight.
- **DuckDB / Parquet on MinIO.** The lightest *infrastructure* — no new pod, reuses MinIO, columnar and
  re-sliceable. Rejected as the primary choice: DuckDB is embedded/single-writer with no query server, and
  Parquet is immutable, so continuous ingestion means many small files to compact and the rollup engine
  becomes code we write and own, with no incremental view. It trades a pod for a pile of maintained code;
  worth revisiting only if a new stateful pod is ever genuinely unacceptable.
- **Keep compute-on-read, add indexes.** Rejected: there is no index that turns "average first-response
  time across every conversation in 30 days" into a point read. The aggregate is the work.
