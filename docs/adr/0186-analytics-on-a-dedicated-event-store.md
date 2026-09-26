# ADR-0186: Analytics — raw events in ClickHouse, rollups in a dedicated Postgres analytics database

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

- **The operational Postgres (`ago_chat`) is the platform's scaling bottleneck**, and the rest of the
  platform is built to protect it: `concurrency.md`'s contended-assignment path, `caching.md`, and rule 8
  all exist to keep load off it. The pressure on it is *connection-pool contention and concurrent-session
  write load*, not raw disk. Analytics is a read concern that consults no write decision (rule 8 does not
  bite), so neither its high-volume event ingestion nor its heavy aggregation has to run against that
  database — and given the bottleneck, must not.
- **Raw events must be retained, write-only, with no lossy pre-quantization.** The author wants to build
  new reports later by slicing raw events (by hour, segment, funnel). Daily buckets are a *derived* view,
  never the only stored form. High-volume per-event writes are their own concern, distinct from the small,
  batch, low-frequency writes that produce the reports.
- **The report read path should stay on Postgres/Dapper.** The report data the screens serve is small
  (per-day-per-tenant buckets), read O(days), and already has a Dapper-shaped read side (`adr/0004`).
  Keeping the *reports* on the familiar SQL/Dapper path — with no ClickHouse dependency in the report
  queries — is worth preserving; only the high-volume raw substrate needs the columnar engine.
- **The report store must be independently relocatable.** The author wants the report data off the
  operational `ago_chat` database *and* able to move to its own Postgres host later as a cheap operation —
  ideally a connection-string/secret change, not a code change or a data-model rework.
- **The day boundary is the tenant's IANA zone**, not UTC — store each event's UTC instant + the tenant
  zone, roll up by the tenant-local day (`date-and-time.md`). AGO Chat has no per-site zone today (the
  calendar owns zones, `adr/0049`), so one must be added. The default is **`Europe/Moscow`** (the first
  clients are Russian), an IANA name rather than a fixed `+03:00` offset so it stays correct if policy
  ever reintroduces DST; per-site editable later.
- **Eventual consistency is explicitly accepted.** Reports may lag by up to ~1 day. The two requirements
  are that reads are **fast** and that the staleness is **known and displayed** (a `computedAsOf` marker),
  not that data is real-time or query-time-exact.
- The platform already provides a transactional outbox (`adr/0005`), an `OutboxDispatcher`, competing
  consumers with an `inbox` ledger (`adr/0017`), RabbitMQ now / Kafka later behind one abstraction
  (`adr/0006`), MinIO object storage, and EF-for-writes / Dapper-for-reads (`adr/0004`). It runs **one
  Postgres instance holding several databases** — `ago_chat`, `keycloak`, `ago_calendar` — each created
  and migrated independently on that instance (`adr/0026`). At-least-once delivery is assumed everywhere
  (rule 5).
- This is a portfolio project with a 1–2-person team pre-launch: a new stateful deployable is a real,
  recurring cost (deploy, PVC, secret, backup, upgrades — `edge.md`, `secrets.md`, `take-a-backup`).

Two earlier proposals were rejected. The **first** maintained the rollups in the operational `ago_chat`
Postgres off the outbox — rejected because it spends the exact resource the platform protects. The
**second** (the immediately-preceding version of this ADR) put *both* layers — raw events and rollups — in
ClickHouse. That correctly moved the high-volume raw writes off Postgres, but it also moved the small
report read path onto a second query engine and its driver for no gain, and gave the report data no home
that is both off `ago_chat` and independently relocatable on the familiar Postgres tooling. This ADR
replaces that direction with a two-store split.

## Decision

Serve analytics from **two stores**, each matched to the load it carries, fed through the existing
outbox/broker path. Full design, schema, freshness contract and slice plan:
[`docs/design/analytics-precompute.md`](../design/analytics-precompute.md).

1. **Raw events → ClickHouse** (single node), a columnar MergeTree store: cheap high-volume batched
   inserts, raw retention without pre-quantization, arbitrary re-slicing for future reports, TTL for
   retention tiering, native `BACKUP` to the MinIO bucket already on the stand. `analytics_events`
   (`ReplacingMergeTree` keyed on `event_id` = outbox `MessageId`) holds one append-only row per analytics
   fact — the UTC instant, the tenant IANA zone, ids and immutable attribution values — never a message
   body or personal content (`messaging.md`, `personal-data.md`). Metrics like first-response seconds are
   *derived* from the stream, never pre-stored, so a future report can redefine them.
2. **Rollups → a dedicated Postgres analytics database, `ago_analytics`** — a **separate database, NOT
   `ago_chat`**, on the same Postgres instance for now (`adr/0026`'s one-instance-many-databases shape),
   with its **own role, own credentials (`ANALYTICS_DB_PASSWORD`) and own connection string
   (`AnalyticsDb`)** resolved independently of the operational connection. It holds `analytics_daily_rollups`
   (per tenant-local-day × site × dimension, additive counters and decomposed averages/rates) and
   `analytics_rollup_runs` (freshness metadata). It has its **own migration path** — a dedicated EF Core
   `DbContext` with its own `__EFMigrationsHistory` inside `ago_analytics` — separate from `ago_chat`'s EF
   migrations. Because it is a distinct database reached by a distinct connection string, **relocating it
   to its own Postgres host later is a connection-string + credential change plus a data move, not a code
   change** — which is the point. To keep that true, **the rollups are self-contained and keyed by ids;
   no cross-database join to `ago_chat` is ever issued** (label resolution happens in the app layer, §8 of
   the design).
3. **Delivery** is unchanged in shape: state change → outbox in the same transaction (rule 4) → RabbitMQ →
   a new `AnalyticsIngestConsumer` in `Ago.Chat.Worker` that batch-inserts into ClickHouse. New integration
   events (`ConversationStarted` enriched with attribution + tenant zone, `ConversationOutcomeRecorded`,
   `ConversationTagged`/`Untagged`) are added where the input is not already on the broker. The consumer is
   idempotent **without** the Postgres `inbox` ledger — a row per analytics event would be the very load
   being avoided — relying instead on `event_id` dedup in ClickHouse plus recompute-from-deduplicated-raw.
4. **A scheduled batch aggregator** (`AnalyticsRollupAggregator`, a `PeriodicTimer` `BackgroundService`,
   default **hourly**, configurable, loosenable to daily) reads the deduplicated raw from **ClickHouse**,
   recomputes each dirty `(site, local_day)` — including the current partial day — and **writes the rollup
   rows into `ago_analytics`** (a per-day delete-then-insert, so a rebuild is idempotent). Recompute-from-raw
   makes at-least-once redelivery, out-of-order arrival and late events all the same operation. Each
   successful run records an `analytics_rollup_runs` row in `ago_analytics`; the **`computedAsOf`** marker
   returned with every analytics response is the last successful run's instant, so staleness is bounded
   and shown.
5. **Reads → `ago_analytics` via Dapper.** The analytics read ports keep their query signatures unchanged;
   the implementations become an O(days) grouped scan over `analytics_daily_rollups` through **Dapper on the
   `AnalyticsDb` connection** — the familiar read path (`adr/0004`), with **no ClickHouse dependency in the
   report queries**. The one contract change is the additive `computedAsOf` field, sourced from a small new
   `IAnalyticsFreshnessReadStore` reading `analytics_rollup_runs`.
6. **`sites.time_zone`** (IANA, default **`Europe/Moscow`**) is added to AGO Chat so the publisher can
   stamp each event's tenant zone; a zone change affects future rollups only.
7. A **re-runnable backfill** job rebuilds raw (and thus rollups) from existing Postgres history — the one
   place the old O(N) read still runs, once, offline, off the request path. Operator-load stays
   compute-on-read (its interval-overlap does not reduce to an additive daily counter and it was not the
   timeout culprit).

## Consequences

Positive:

- Analytics reads become fast and O(days), independent of total history — the 499's cause is removed — and
  **every kind of analytics load leaves the operational `ago_chat` database**: high-volume raw writes go to
  ClickHouse; the small report reads/writes go to a *separate* database with its own connection pool, so
  `ago_chat`'s pool and concurrent-session bottleneck are untouched.
- The report read path stays on **Postgres/Dapper** — the familiar tooling, no ClickHouse client in the
  report queries — while the high-volume substrate gets the columnar engine that fits it.
- The report data is **independently relocatable**: a future move of `ago_analytics` to its own Postgres
  host is a connection-string + credential change plus a data move, because the split was designed with a
  distinct connection and no cross-database joins from day one.
- Raw events are retained write-only for arbitrary future reports; daily buckets are a cheap derived view,
  rebuildable from raw at any time. Recompute-from-deduplicated-raw makes redelivery, out-of-order and late
  events one idempotent operation, and doubles as the reconciliation tool.
- Staleness is bounded by a simple batch cadence and shown to the reader (`computedAsOf`), so eventual
  consistency is honest rather than hidden.

Negative / what gets harder:

- **Two analytics stores to operate and back up**, not one. ClickHouse is a new stateful pod with its own
  PVC, a new `CLICKHOUSE_PASSWORD` secret, its own native `BACKUP` step in `backup.sh`, and its own
  upgrades. `ago_analytics` is a second Postgres database with its own role and `ANALYTICS_DB_PASSWORD`
  secret; it is cheaper (no new pod, and `backup.sh` already dumps *every* database it enumerates, so it is
  picked up automatically — `take-a-backup`), but it is still a second credential and a second migration
  path to maintain.
- **Two moving parts in the pipeline**, spanning two engines: an ingest consumer writing ClickHouse and an
  aggregator reading ClickHouse and writing Postgres. The aggregator holds two connections and is the one
  place the two stores meet.
- **A second Postgres database + role + connection string** to provision, migrate and rotate — the
  `ago_analytics` migration path is deliberately separate from `ago_chat`'s EF migrations, which is more
  surface than one migrations history.
- **No cross-database joins allowed.** Reports return id-keyed aggregates; resolving an operator's display
  name or a tag's label happens in the app layer against `ago_chat`'s own read ports, never as a
  cross-database SQL join. This is the constraint that keeps `ago_analytics` relocatable, and it costs a
  little handler-side merge code the old single-database query got for free with a `JOIN`.
- **The first consumer that does not use the Postgres `inbox` ledger.** Idempotency moves into ClickHouse's
  dedup semantics; a deliberate divergence from rule 5's usual realisation (not from its intent), forced by
  the "keep load off `ago_chat`" constraint, and must be understood before copying the pattern.
- **A new NuGet** (a ClickHouse ADO.NET provider) and a ClickHouse DDL/migration path separate from EF.
- **New integration-event contracts** become public promises (`messaging.md` versioning), carrying no
  personal data on the wire; and `sites.time_zone` is a new column with a chosen default.
- **A second place personal data lives** — in fact two: ClickHouse (raw ids) and `ago_analytics` (id-keyed
  rollup rows), both ids not content; `personal-data.md` gains rows for both, and site-level erasure
  (`SiteErased`) must propagate to both.

## Alternatives considered

- **Both layers in ClickHouse** (the immediately-preceding version of this ADR, now superseded). It moved
  the high-volume raw writes off Postgres — which this decision keeps — and needed only one new store. The
  author prefers PG-for-rollups because it keeps the small report read path on the familiar Postgres/Dapper
  tooling with no second query engine in the report queries, and because a Postgres rollup database is
  independently relocatable to its own host on ordinary Postgres tooling (`pg_dump`/restore, a
  connection-string change), where a ClickHouse-resident rollup would tie the report path to ClickHouse's
  availability and driver. The cost of the split — two stores, a second credential, an aggregator that
  spans both — is accepted for those two properties.
- **Rollups in the operational `ago_chat` Postgres, maintained off the outbox** (the original proposal,
  rejected). It reused only-existing machinery and kept one database — genuinely the smallest change.
  Rejected because the whole point is to keep analytics off the instance that is already the platform's
  scaling bottleneck (`concurrency.md`, `caching.md`, rule 8) *and* to leave the report data independently
  relocatable; putting the rollups back in `ago_chat` loses both — they would share `ago_chat`'s connection
  pool and could not move hosts without a data split. A separate `ago_analytics` database gets the
  familiar-tooling benefit that made this option attractive **without** loading the operational database or
  welding the report store to it.
- **TimescaleDB on a separate instance** for the raw layer — hypertables + continuous aggregates, familiar
  SQL. Rejected for *raw*: it is row-oriented at heart (columnar only via compressed chunks), so it loses
  to ClickHouse on write throughput and scan cost for a wide append-only event log, and it adds a second
  Postgres *flavour* to version. (Note: the rollup store here *is* ordinary Postgres — but as a small
  derived table read O(days), not as the high-volume raw substrate, so it needs no Timescale features.)
- **Kafka-as-log + an OLAP sink.** Kafka is "later" on this platform (`adr/0006`) and answers no query
  itself, so this is two new systems, not one. Rejected: doubles the new-infra count and still needs a
  query engine on the end.
- **Elasticsearch / OpenSearch.** A search engine, not a columnar OLAP one; aggregations are memory-hungry
  and it is the heaviest to operate (JVM heap, shards) for this team size. Rejected on shape and ops weight.
- **Druid / Pinot.** Purpose-built real-time OLAP, but multi-component (coordinator/broker/historical/…) —
  built for a scale and an operations team this project is nowhere near. Rejected on ops weight.
- **DuckDB / Parquet on MinIO** for raw. The lightest *infrastructure* — no new pod, reuses MinIO, columnar
  and re-sliceable. Rejected as the raw store: DuckDB is embedded/single-writer with no query server, and
  Parquet is immutable, so continuous ingestion means many small files to compact and the rollup engine
  becomes code we write and own. Worth revisiting only if a new stateful pod is ever genuinely unacceptable.
- **Keep compute-on-read, add indexes.** Rejected: there is no index that turns "average first-response
  time across every conversation in 30 days" into a point read. The aggregate is the work.
