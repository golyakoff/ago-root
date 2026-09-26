# Analytics: raw events in ClickHouse, daily rollups in a dedicated Postgres analytics database

**Status:** design proposal. Decision recorded in [`adr/0186`](../adr/0186-analytics-on-a-dedicated-event-store.md).
**Scope:** AGO Chat's operator/site analytics family (Stage 18 `18-08`..`18-14`, plus the calendar-side
phone-reveal and booking-funnel reports). A product-local read-model change of the kind `adr/0004`
already governs — plus **one new Infrastructure dependency (ClickHouse) and one new Postgres database**,
which is why it also carries an ADR and touches `ago-deploy`, `secrets.md` and `personal-data.md`. No
platform-shape change: `Ago.Platform.*` gains nothing, and both stores sit behind AGO Chat's own
Infrastructure adapter (§8).

> **This revises two earlier passes.** The **first** proposed maintaining the rollups **in the
> operational `ago_chat` Postgres** off the outbox; rejected because `ago_chat` is the scaling bottleneck
> for concurrent conversations (`concurrency.md`, `caching.md`, rule 8) and the report data must also be
> independently relocatable. The **second** put **both** raw events and rollups in **ClickHouse**; it
> moved the high-volume raw writes off Postgres (kept here) but needlessly moved the *small report read
> path* onto a second query engine and gave the report data no home that is both off `ago_chat` and
> relocatable on familiar Postgres tooling. This version keeps the problem statement, the O(conversations)
> diagnosis, the 499 incident, the screen enumeration, ClickHouse-for-raw, tenant-local-day, and eventual
> consistency, and splits storage into **two stores**: raw events in ClickHouse, rollups in a dedicated
> **`ago_analytics`** Postgres database. `adr/0186` records why.

## 1. Problem statement

The Android «Аналитика» screen timed out with a client-side 499 (client gave up, closed the socket).
Investigation found the backend query returns in **~0.5 ms** today — but only because the store holds
**132 conversations and 50 messages total**, all the author's own test data, with **no real tenants yet**.
The concern that prompted this design is correct and forward-looking: *the query is fast because there is
nothing to aggregate*, and the shape does not scale.

### What actually runs on an analytics load

`GetOwnAnalyticsForOperatorHandler` — the endpoint the Android screen calls (`/conversations/analytics/me`)
— runs **three site-wide aggregations concurrently** for a 30-day default window, then throws away
everything except the caller's own row:

| Read store | Query shape | Cost per request |
|---|---|---|
| `OperatorAnalyticsReadStore.GetSiteAnalyticsAsync` | CTE with a **`LEFT JOIN LATERAL` per conversation** over the 64-way-partitioned `messages` table (min first-visitor / first-operator timestamps), a second lateral over `channel_identities`, an `operators` join, then `GROUP BY GROUPING SETS ((), channel, operator, referrer, campaign)` | **O(conversations × messages-per-conversation)** |
| `OperatorLoadReportReadStore.GetOperatorLoadReportAsync` | Two queries over `conversation_assignments`, each row carrying a **correlated overlap subquery** (`concurrent_load`), plus a per-interval correlated `messages` lookup for first reply | **O(intervals × overlapping-intervals)** |
| `ConversionReportReadStore.GetConversionReportAsync` | Single scan of `conversations` in window, `GROUP BY GROUPING SETS ((outcome), (operator, outcome))` | **O(conversations)** |

The own-analytics screen is the worst case: **the whole site's history is aggregated across three stores
to compute one operator's row.** At 132 conversations this is invisible. At a real tenant's volume — tens
of thousands of conversations, each with a message history, over a rolling 30-day window, recomputed on
every screen load, by every operator, unindexable because the aggregation is the answer — it is exactly the
`O(N)`-per-request shape that produces the 499 that was observed on plumbing that was otherwise healthy.

This is not a missing index. There is no index that turns "average first-response time across every
conversation started in the last 30 days" into a point read; the aggregate *is* the work. And it runs on
the **operational Postgres (`ago_chat`)** — the same instance serving every visitor mint, every message
write and every capacity claim, which `concurrency.md` and `caching.md` already treat as the resource under
most pressure.

## 2. What each analytics screen needs

Enumerated so the pre-computed model can be checked against every consumer, not just the one that timed out.

| Screen / endpoint | Port | Window keyed on | Dimensions (GROUPING SETS) | Metrics | Source tables |
|---|---|---|---|---|---|
| Site analytics `/conversations/analytics` | `IOperatorAnalyticsReadStore` | `conversations.created_at` | total, channel, operator, referrer host, UTM campaign | conversation count; avg first-response secs; avg duration secs; missed count | `conversations`, `messages`, `channel_identities`, `operators` |
| Own analytics `/conversations/analytics/me` | same three ports below, own row kept | same | (caller's own operator row only) | same as site analytics + own conversion row | same |
| Conversion `/conversations/conversion-report` | `IConversionReportReadStore` | `conversations.created_at` | total, operator | converted / not-converted / follow-up / unset counts; recorded count; rate | `conversations.outcome`, `operators` |
| Tag breakdown `/conversations/tag-breakdown-report` | `ITagBreakdownReadStore` | `conversations.created_at` | total coverage, **per tag (many-per-conversation)** | total conv count; tagged conv count; % tagged; per-tag conv count + conversion rate | `conversations`, `conversation_tags`, `tags` |
| Operator load | `IOperatorLoadReportReadStore` | `conversation_assignments.started_at` | operator, then **concurrent-load bucket** | interval count; distinct conversation count; additional-over-capacity count; per-load-bucket reply count + reply-secs | `conversation_assignments`, `operators`, `messages` |
| Booking funnel `/conversations/module-flow-report` | `IModuleFlowReadStore` | `module_tasks` open time | per module key | flows started; flows closed | `module_tasks` |
| Phone reveals (contact) | `IContactRevealRepository.List…` | `contact_reveals.id` keyset | (a receipt list, not an aggregate) | one row per reveal event | `contact_reveals` |
| Widget install funnel | `IWidgetActivityReadStore` | `day` (UTC) | site | loads / opens / conversations | **`site_widget_activity` — already a daily rollup** |

Two of these are already the right *shape* and are the precedent this design generalises — while showing
its limit:

- **`site_widget_activity`** (`23-07`) is a per-`(site_id, day)` counter table maintained by an
  increment upsert, read as an O(days) `SUM`. It proves the **rollup shape** is right. It lives in the
  operational `ago_chat` Postgres and is fed by a best-effort in-memory accumulator, and it is the very
  thing this design does *not* copy verbatim: its counters are approximate by licence, and it puts a daily
  table on the same instance under load. This design keeps its read shape and moves the storage to the
  dedicated `ago_analytics` database.
- **Phone reveals** are already a keyset list of individual receipt rows, not an aggregation — nothing to
  pre-compute, and nothing to move. It stays as is.

## 3. The two-store model, and where each layer lives

The author's own framing — "store the raw events, build reports on top, like Grafana" — is adopted in
full. There are two layers, and — the change this revision makes — **each lives in the store that fits its
load**:

| Layer | What it is | Load profile | Where it lives |
|---|---|---|---|
| **Raw events** | An append-only, write-only log of every analytics-relevant fact, one row per event, no lossy pre-quantization. The substrate any current *or future* report is sliced from — by hour, by segment, by funnel step. | **High-volume**, continuous, per-event batched inserts; wide columns; arbitrary re-aggregation | **ClickHouse** (§5), never `ago_chat` |
| **Daily rollups** | A derived, narrow table: per tenant-local **day** × site × dimension, additive counters and decomposed averages/rates. A *view* on the raw layer, cheap to read, cheap to rebuild, never the only stored form. | **Low-volume**: small batch writes (one per dirty day per aggregator run) + small O(days) reads | A **dedicated Postgres database `ago_analytics`** (§3.2), NOT `ago_chat` |

ClickHouse is the source of truth *for raw analytics facts*; `ago_analytics` holds only a derived view of
them; `ago_chat` PostgreSQL remains the source of truth for the business (`data-model.md`). The raw layer
is reconstructible from `ago_chat` by backfill (§10) for as long as `ago_chat` still holds the underlying
conversations, and the rollups are reconstructible from raw at any time — a strict `ago_chat` → ClickHouse
raw → `ago_analytics` rollups derivation chain.

### 3.1 The freshness contract — eventual consistency is accepted, and shown

**Analytics is explicitly allowed to be stale.** There is no requirement for real-time or query-time-exact
computation. Report data may lag by up to roughly **one hour** under the default cadence (§7.2) and that is
fine. The two real requirements are the ones this design optimises for:

1. **Reads are fast** — an instant grouped scan over a pre-computed rollup, never a live aggregation.
2. **The staleness is known and displayed up front** — every analytics response carries an explicit
   **`computedAsOf`** marker so the UI can state the data currency ("computed on data as of …"). A bounded,
   explicit, *shown* as-of marker, never a hidden lag a reader mistakes for live.

This permits the **simplest** aggregator that meets those two: a **scheduled/batch** rollup, not a tight
streaming pipeline. Raw events are still ingested continuously (§4) — they are cheap and the raw layer must
stay complete for future reports — but the *rollups* need not be near-real-time. The consequence, folded
through the rest of this document: the consistency/latency language is "fast reads + a known, displayed
freshness marker", the "today's partial day" handling is whatever the batch cadence naturally gives (§7),
and `computedAsOf` comes from the last successful rollup run (§7.3).

### 3.2 Why the rollups get their own Postgres database — and how the split stays cheap to unwind

The rollups do **not** go back into `ago_chat`, and they do **not** stay in ClickHouse. They live in a
**separate Postgres database, `ago_analytics`**, on the same Postgres instance for now (`adr/0026`'s
one-instance-many-databases shape — the precedent is `keycloak` and `ago_calendar`, each its own database
on that instance). Three properties drive this:

- **Off the operational bottleneck.** `ago_chat`'s pressure is connection-pool contention and
  concurrent-session write load. `ago_analytics` has its **own connection string and its own connection
  pool**, and carries only small batch writes (a handful of rows per dirty day per aggregator run) and
  small O(days) reads — so it does not compete for `ago_chat`'s pool or its write path even while sharing
  the same physical instance today.
- **Familiar read path.** The report reads are a grouped range scan over a narrow table — exactly the
  Dapper read-model shape `adr/0004` already governs. Keeping rollups in Postgres means the report queries
  stay on **Dapper/SQL with no ClickHouse dependency**; only the aggregator's *source read* touches
  ClickHouse.
- **Independently relocatable.** The database is reached through a **distinct `AnalyticsDb` connection
  string resolved independently** of the operational one. "Different database now, different host later" is
  realized by pointing `AnalyticsDb` at a new host and moving the data (`pg_dump`/restore of one small
  database) — **no code change**. The single rule that keeps this cheap: **the rollups are self-contained
  and keyed by ids; the aggregator and the read path issue no cross-database join to `ago_chat`** (label
  resolution happens in the app layer, §8). A cross-database join would weld the two databases to one host
  and defeat the relocation, so it is forbidden.

#### Provisioning `ago_analytics`

The instance's `initdb` creates exactly one database (`POSTGRES_DB` = `ago_chat`) and only on first
initialisation, so — exactly as `keycloak` and `ago_calendar` already do — a second database must be
created by a job/initContainer after Postgres is up. The pattern is the Keycloak one (`k8s/base/keycloak.yaml`):

- **Own role + credentials.** An idempotent bootstrap creates a dedicated login role with its own password
  from a new `ANALYTICS_DB_PASSWORD` secret (`CREATE ROLE analytics LOGIN …` guarded by
  `WHERE NOT EXISTS (… pg_roles …)`, with an unconditional `ALTER ROLE … PASSWORD` so rotating the secret
  takes effect — the Keycloak precedent), then `CREATE DATABASE ago_analytics OWNER analytics` guarded by
  `WHERE NOT EXISTS (… pg_database …)`. Idempotent, safe on every boot.
- **Own migration path.** The rollup + freshness schema is owned by a **dedicated EF Core `DbContext`
  (`AnalyticsRollupDbContext`)** with its **own `__EFMigrationsHistory` table inside `ago_analytics`**,
  run by an **analytics-migrator job** pointed at the `AnalyticsDb` connection string. This is a *separate
  migration path* from `ago_chat`'s EF migrations (`k8s/base/migrator.yaml`) — different DbContext,
  different history table, different database — so the two never share a migrations ledger and cannot
  collide. (The aggregator *writes* rollup rows with idempotent upserts (§7); EF here owns only the schema,
  not the hot write path.)
- **Own connection string.** A distinct `AnalyticsDb` connection string
  (`Host=postgres;Port=5432;Database=ago_analytics;Username=analytics;Password=$(ANALYTICS_DB_PASSWORD)`)
  in the Worker (aggregator write + freshness) and the Api (reads), resolved independently of the
  operational `ConnectionStrings:Default`. Relocating later changes only `Host`/credentials.

## 4. Delivery path — how a fact reaches the stores

The operational write path is untouched. Nothing publishes from a request handler (rule 4); nothing
queries either analytics store to make a write decision (rule 8, and it never could).

```
state change in Ago.Chat.Api / Worker
   │  (same DB transaction, rule 4)
   ▼
outbox row  ──OutboxDispatcher──▶  RabbitMQ  ──▶  AnalyticsIngestConsumer (Ago.Chat.Worker)
(operational ago_chat)              (Kafka later,        │  batches N events / T ms
                                     adr/0006)           ▼
                                          ClickHouse  analytics_events  (raw, append-only)
                                                          │
                                                          │  AnalyticsRollupAggregator (Ago.Chat.Worker)
                                                          │  reads deduplicated raw, per dirty (site, local_day)
                                                          ▼
                                          ago_analytics (Postgres)  analytics_daily_rollups  (derived)
                                                                    analytics_rollup_runs    (freshness)
```

### 4.1 Events available vs. events needed

The platform already has the machinery for the *delivery* half: a transactional **outbox** (`adr/0005`),
the **`OutboxDispatcher`** draining it to RabbitMQ, and competing consumers (`adr/0017`). The current
event set was built for delivery and fan-out, not analytics, so some inputs are not yet on the broker.

| Analytics input | Event today | Gap |
|---|---|---|
| Conversation started (+ site, visitor, attribution) | `ConversationStarted` **domain event only — no mapper, not published** | Needs an integration event, **enriched** with the read-time attribution dimensions: resolved channel label, `traffic_referrer_host`, `traffic_utm_campaign`, **and the tenant IANA zone** (§9) |
| First visitor / first operator message | `MessageAccepted` (published; carries `conversation_id`, `author_kind`, `sequence`, `OccurredAt`) | **Sufficient** — the aggregator derives first-of-kind timestamps from the stream |
| Operator attribution | `ConversationAssignedToOperator`, `ConversationTransferred` (both published) | Sufficient for the assigned-operator fallback; first-operator attribution comes from `MessageAccepted` |
| Conversation closed (+ duration, missed) | `ConversationClosed` → wire `ConversationEnded` (published) | **Confirm it carries `closed_at`**; duration and missed are resolved at close |
| Conversion outcome | `SetConversationOutcomeHandler` writes `conversations.outcome` — **no integration event** | Needs `ConversationOutcomeRecorded` (carries new outcome; supersedes prior) |
| Tags | `TagConversation` / `UntagConversation` — **no integration event** | Needs `ConversationTagged` / `ConversationUntagged` (carry `tag_id`) |
| Booking-funnel task | `module_tasks` open/close — **no integration event** | Needs `ModuleTaskOpened` / `ModuleTaskClosed` (carry `module_key`) — or leave module-flow compute-on-read (§10) |
| Phone reveals | `contact_reveals` row write — no event | **No change** — a receipt list, not an aggregate |

Every new event obeys the existing contract rules (`messaging.md`): past-tense fact, ids + immutable
values only, **no message body / no personal data on the wire** (`personal-data.md`), keyed by
`conversation_id`, `MessageId` as the idempotency key. Each is staged to the outbox **in the same
transaction** as the state change it reports (rule 4).

### 4.2 The ingestion consumer

A new competing consumer, **`AnalyticsIngestConsumer`**, in `Ago.Chat.Worker`, subscribed to the topics
above plus `MessageAccepted`. Its only job is to translate each event into one raw row and **insert in
batches into ClickHouse** — ClickHouse rewards large inserts and punishes per-row ones, so the consumer
buffers events and flushes on a size **or** time bound (whichever first), acking the batch once the insert
returns.

**Idempotency without the Postgres inbox.** Every other consumer records `(message_id, consumer)` in the
operational `ago_chat` `inbox` (rule 5, `adr/0017`). This one **must not** — a row per analytics event is
exactly the operational-Postgres write load this whole design exists to avoid. Idempotency moves into
ClickHouse instead:

- Each raw row carries `event_id` = the outbox `MessageId`. The raw table is a **`ReplacingMergeTree`**
  ordered on a key that includes `event_id`, so a redelivered event collapses to one row on background
  merge.
- Because merges are asynchronous, a duplicate can be briefly present. Counters therefore are **not**
  computed by a naive insert-time trigger that would double-count it; they are recomputed from the
  **deduplicated** raw layer by the aggregator (§7), which is idempotent by construction. At-least-once
  redelivery, out-of-order arrival and late events are then all the same operation: recompute the
  affected day from raw.

This is the first AGO consumer that does not use the Postgres inbox ledger. That is a deliberate,
recorded consequence (`adr/0186`), not an oversight — the ledger's guarantee is replaced by ClickHouse's
own dedup semantics, which is the only version of the guarantee that keeps the load off `ago_chat`.

## 5. Choosing the raw event store

This section is about the **raw** store only; the rollup store is decided (`ago_analytics` Postgres, §3.2).
Judged on: write throughput for high-volume append-only events; raw-retention + arbitrary re-aggregation;
**operational weight for a 1–2-person team pre-launch** (a new stateful pod means deploy, PVC, secret,
backup, upgrades — `edge.md`, `secrets.md`, `take-a-backup`); and fit with the existing single-node k8s
stand (postgres/redis/rabbitmq/minio, each one Deployment + one RWO PVC).

| Engine | Write throughput | Raw retain + re-slice | Ops weight (pre-launch) | Stand fit | Verdict |
|---|---|---|---|---|---|
| **ClickHouse** (MergeTree family) | Excellent — columnar, built for high-volume batched inserts | Excellent — raw `MergeTree` kept indefinitely at this volume; re-slice by any column; the tz-aware `toDate(instant, zone)` the tenant-local-day rollup needs | **Moderate** — one stateful pod, one binary, one secret; backup via native `BACKUP` to the existing MinIO, or `clickhouse-backup` | Same single-Deployment + RWO-PVC shape as rabbitmq/minio; HTTP + native ports | **Recommended** |
| TimescaleDB, **separate instance** | Good, row-store at heart; columnar only via compressed chunks | Good — hypertables + continuous aggregates; SQL familiar | Moderate–low *conceptually* (reuses Npgsql/Dapper + `pg_dump`) but it is **a second Postgres flavour to version and operate** | Fits, but now two Postgres-family engines on the box | Runner-up — loses on compression/scan for wide append-only events; wins only on tooling familiarity, which the rollup store already gets by being plain Postgres |
| Kafka-as-log + an OLAP sink | Excellent ingest | Only with the sink — Kafka answers no query itself | **High** — Kafka is "later" (`adr/0006`), and this is *two* new systems (log + sink) | Poor — nothing on the stand today | Rejected — does not serve reads on its own, and doubles the new-infra count |
| Elasticsearch / OpenSearch | Good | Aggregations possible but memory-hungry; a search engine, not a columnar OLAP one | **High** — JVM heap tuning, shard management | Poor | Rejected — wrong shape, heaviest ops for the team size |
| Druid / Pinot | Excellent at real-time OLAP | Excellent | **Very high** — multi-component (coordinator/broker/historical/…) | Poor — many pods | Rejected — purpose-built for a scale and a team this project is nowhere near |
| DuckDB / Parquet on MinIO | Good in batch; awkward for concurrent streaming appends | Columnar Parquet, re-sliceable; **no incremental rollup, no server** | **Low infra** (no new pod, reuses MinIO) but **high code** — you build the query process, file compaction and the rollup source yourself | Reuses MinIO | Honourable mention — the lightest *infra*, but it moves the complexity into code we maintain and loses a real query server; revisit only if a new pod is genuinely unacceptable |

**Recommendation: ClickHouse, single node, for raw.** It is the classic events-analytics fit and it earns
its one new pod: a raw `MergeTree` table takes cheap batched inserts and columnar aggregation, retains raw
without pre-quantization, re-slices by any column for future reports, offers TTL for retention tiering,
carries the tz-aware date function the tenant-local-day rollup needs, and backs up natively to the MinIO
bucket already on the stand. Its honest cost is in `adr/0186`'s Consequences: a second stateful datastore,
a new secret, a new backup path. The runner-up worth naming is TimescaleDB on a *separate* instance
(declined for raw: a second Postgres flavour to operate buys tooling familiarity that the rollup store
already gets by being plain Postgres, and it loses ClickHouse's columnar fit for a wide append-only log),
and the lightest-infra idea worth naming is DuckDB/Parquet-on-MinIO (declined: it trades a pod for a pile
of code we would own).

## 6. The raw event schema (ClickHouse)

One wide, append-only table. Representative ClickHouse DDL — the column *set* is the design point, not
the exact types:

```sql
CREATE TABLE analytics_events
(
    event_id        UUID,                          -- = outbox MessageId; dedup key
    event_type      LowCardinality(String),        -- see the vocabulary below
    occurred_at     DateTime64(3, 'UTC'),          -- the UTC instant (rule 11)
    tenant_zone     LowCardinality(String),        -- tenant IANA zone as-of-event (§9)
    site_id         UUID,
    conversation_id Nullable(UUID),
    visitor_id      Nullable(UUID),
    operator_id     Nullable(UUID),
    channel         LowCardinality(String),        -- resolved channel label
    referrer_host   String,                        -- traffic attribution
    utm_campaign    String,
    outcome         LowCardinality(String),        -- for ConversationOutcomeRecorded
    tag_id          Nullable(UUID),                -- one event per tag add/remove
    module_key      LowCardinality(String),        -- for module-task events
    missed          Nullable(UInt8),               -- resolved at close
    schema_version  UInt16,
    correlation_id  UUID,
    ingested_at     DateTime DEFAULT now()         -- for lag observability
)
ENGINE = ReplacingMergeTree(ingested_at)
PARTITION BY toYYYYMM(occurred_at)
ORDER BY (site_id, event_type, occurred_at, event_id);   -- event_id in the key ⇒ dedup on merge
```

**Metrics are derived, not pre-stored, wherever the raw stream already carries the inputs.** First-response
seconds is not a column: it is `first-operator-message occurred_at − conversation-created occurred_at`,
computed per conversation by the aggregator from the `MessageAccepted` / `ConversationStarted` rows.
Duration is `closed_at − created_at`. Keeping these as derivations, not stored scalars, is what lets a
future report redefine "first response" (business hours only? excluding auto-replies?) by changing a query
rather than re-emitting events.

Event-type vocabulary (each a past-tense fact, one row per occurrence): `ConversationStarted`,
`VisitorMessageSent`, `OperatorMessageSent`, `ConversationEnded`, `ConversationOutcomeRecorded`,
`ConversationTagged`, `ConversationUntagged`, `ModuleTaskOpened`, `ModuleTaskClosed`, `WidgetLoaded`,
`WidgetOpened`. Phone reveals stay in `ago_chat` as a receipt list (§2); they are listed here only to note
they were considered and left where they are.

This schema covers every screen in §2: site/own analytics (started + message + ended + attribution),
conversion (outcome), tag breakdown (tag events + started for coverage), booking funnel (module-task
events), widget funnel (load/open/started). It deliberately holds more than today's reports need — that
is the point of a raw layer.

## 7. The aggregator — daily rollups per tenant-local day, written to `ago_analytics`

The aggregator reads the deduplicated raw from **ClickHouse** and writes the rollups into the **`ago_analytics`
Postgres database**. The rollup table generalises today's `GROUPING SETS` output into a narrow, long shape,
keyed by the **tenant-local day**. Postgres DDL (owned by the analytics migration path, §3.2):

```sql
CREATE TABLE analytics_daily_rollups
(
    site_id                    uuid        NOT NULL,
    local_day                  date        NOT NULL,   -- tenant-local calendar day (§9)
    dimension_type             text        NOT NULL,   -- total|channel|operator|referrer|campaign|tag
    dimension_key              text        NOT NULL,   -- label / id / host / '' for total
    conversation_count         bigint      NOT NULL DEFAULT 0,
    first_response_seconds_sum bigint      NOT NULL DEFAULT 0,  first_response_count bigint NOT NULL DEFAULT 0,
    duration_seconds_sum       bigint      NOT NULL DEFAULT 0,  duration_count       bigint NOT NULL DEFAULT 0,
    missed_count               bigint      NOT NULL DEFAULT 0,
    converted_count bigint NOT NULL DEFAULT 0, not_converted_count bigint NOT NULL DEFAULT 0,
    follow_up_count bigint NOT NULL DEFAULT 0, unset_count bigint NOT NULL DEFAULT 0, recorded_count bigint NOT NULL DEFAULT 0,
    rebuilt_at                 timestamptz NOT NULL,
    PRIMARY KEY (site_id, local_day, dimension_type, dimension_key)
);
```

Averages and rates are stored **decomposed** (sum + count, numerator + denominator) so they stay additive
and the read reconstitutes the ratio — never the store. A conversation contributes to five dimension rows
for its local day (`total` + channel + operator + referrer + campaign) plus one `tag` row per tag,
reproducing GROUPING SETS. The `dimension_key` holds an **id** (operator_id, tag_id) or a denormalized
**value** (channel label, referrer host, campaign) — never a joined display name; see §8 for why.

### 7.1 Why a scheduled recompute, not an insert-time view

| Option | How it works | Verdict |
|---|---|---|
| **(a) Insert-time incremental view** | Maintain rollup deltas as raw rows arrive (a ClickHouse MV into a `SummingMergeTree`, or a trigger) | Rejected: the view sees each inserted row, so a **redelivered** event (present until the raw `ReplacingMergeTree` merges it away) is summed **twice**; deduping before the view is what the view cannot do. It is also rigid about late events and tenant-zone/DST edges. And it would have to live in ClickHouse, whereas the rollups are decided to live in Postgres (§3.2) — an insert-time ClickHouse view cannot target a Postgres table anyway. |
| **(b) Scheduled recompute from deduplicated raw → Postgres** | An `AnalyticsRollupAggregator` `BackgroundService` in `Ago.Chat.Worker` periodically, per touched `(site, local_day)`: reads `SELECT … FROM analytics_events FINAL … WHERE toDate(occurred_at, tenant_zone) = @day GROUP BY dimension …` from ClickHouse, then **replaces** that day's rows in `ago_analytics` (`DELETE … WHERE site_id=@s AND local_day=@d; INSERT …`, or an equivalent upsert, in one Postgres transaction) | **Recommended.** Recompute from deduplicated (`FINAL`) raw is **idempotent**: running it twice yields the same rollup, so redelivery, out-of-order arrival and late events cannot corrupt a counter. Re-slicing one day is a bounded columnar scan of that day's partition on the read side and a small delete+insert on the write side. |

The aggregator *owns* the rollup definition and can rebuild any day idempotently from raw, which is what
makes adding a new report (a new dimension, a new metric) a change to the aggregator query plus a rebuild,
not an event re-emission. The per-day delete-then-insert into Postgres also naturally drops a `dimension_key`
that no longer has data on a recompute, which a blind upsert would leave stale.

### 7.2 Cadence, "today", and the resulting staleness

Because eventual consistency is accepted (§3.1), the aggregator is a **plain scheduled batch**, not a
near-real-time loop. **The cadence is a run every hour** (an ordinary `PeriodicTimer` `BackgroundService`) —
decided, configurable, loosenable to daily if even that proves more than needed. Hourly keeps the *maximum*
staleness a reader ever sees to about an hour while staying a trivially simple batch job. Whatever the
value, it is stated in the deployed configuration and surfaced through `computedAsOf`, so the reader never
has to guess.

**"Today" (the partial current tenant-local day)** needs no special read path and no live-union trick. Each
run recomputes every dirty day *including* the current local day from raw, so today's partial bucket is as
fresh as the last run — i.e. at most one cadence-interval stale, exactly like every other day. There is no
"combine live + rollup" path: the whole point of accepting eventual consistency is that the rollup *is* the
answer, and its currency is shown rather than hidden.

**Late events** need no reconcile machinery beyond the cadence either. The aggregator recomputes any
`(site, local_day)` that has seen inserts since its last run — a cheap `max(ingested_at)` watermark per day,
or a small "dirty days" set — so a late event whose `occurred_at` falls in an already-closed day simply
marks that day dirty and it is rebuilt on the next run. Because a rebuild is a full recompute of the day
from the deduplicated raw, there is never a delta to get wrong.

### 7.3 Where `computedAsOf` comes from

Each successful aggregator run records one metadata row in `ago_analytics` — an `analytics_rollup_runs`
entry holding the run's completion instant (`timestamptz`, UTC) and the newest `local_day` it covered. The
**freshness marker returned with every analytics response is the last successful run's completion instant**
(`SELECT max(completed_at) FROM analytics_rollup_runs`, rendered in the caller's zone, `date-and-time.md`),
optionally alongside the covered `local_day` for a human-friendly "data as of <yesterday>". If a run fails,
`computedAsOf` simply does not advance — the reader sees honestly older data, never silently-partial data,
because a failed run writes no metadata row and leaves the previous rollup in place. This is the one piece
of state the reads consult beyond the rollup itself (§8), and it lives in the same `ago_analytics` database
so the read path touches exactly one store.

## 8. Reads — behind the unchanged ports, on `ago_analytics` via Dapper

The Application read **ports keep their query signatures**: `IOperatorAnalyticsReadStore`,
`IConversionReportReadStore`, `ITagBreakdownReadStore` (and `IModuleFlowReadStore`,
`IWidgetActivityReadStore` if migrated). Only the implementations move — to **Dapper against the
`AnalyticsDb` connection** (§3.2), the same read-model shape `adr/0004` already governs. **No ClickHouse
dependency enters the report read path**: the report queries are ordinary Postgres SQL against
`analytics_daily_rollups`.

**The one intended contract change is the freshness marker** (§3.1). Every analytics response gains a
`computedAsOf` field — an **additive** change (`api-design.md` / `messaging.md` versioning: a new optional
field is compatible), so existing clients keep working and the Android screen adds a "data as of …" line.
The cleanest Clean-Architecture expression is a small dedicated port, `IAnalyticsFreshnessReadStore`
(`GetLastRollupRunAsync`), that the analytics endpoints call **once** alongside the aggregate read, rather
than threading a timestamp through every aggregate method — one query against `analytics_rollup_runs`
(§7.3), one place, injected into the endpoints that assemble analytics responses. Handlers'
aggregate-shaped logic is untouched; they gain one freshness read and one response field.

A read becomes a grouped range scan on the rollup PK:

```sql
SELECT dimension_type, dimension_key, sum(conversation_count), …
FROM analytics_daily_rollups
WHERE site_id = @s AND local_day >= @from AND local_day < @to
GROUP BY dimension_type, dimension_key
```

**O(days), independent of total history**, and it never touches `messages` — or `ago_chat` at all.

### 8.1 No cross-database joins — labels resolved in the app layer

The reports display operator names and tag labels; the old single-database query got these from a `JOIN
operators` / `JOIN tags`. Here those live in `ago_chat` and the rollups in `ago_analytics`, so a SQL join
would be **cross-database** — which is forbidden (§3.2), because it would weld the two databases to one
host and defeat `ago_analytics`'s relocation. Instead:

- The rollup read returns **id-keyed** aggregate rows (`dimension_key` = operator_id / tag_id).
- The handler resolves display labels by calling **`ago_chat`'s own existing read ports** (the operator and
  tag read stores it already uses elsewhere) and **merges in memory** — an application-layer join across
  two ports, never a SQL join across two databases.
- Dimensions whose value is intrinsic — channel label, referrer host, UTM campaign — are **denormalized
  onto the event** at publish time and carried straight through, so they need no resolution at all.

This costs a little handler-side merge code the `JOIN` gave for free; it is the price of keeping
`ago_analytics` a standalone, relocatable database.

### 8.2 How it fits Clean Architecture

| Layer | What goes here | Why |
|---|---|---|
| Domain | Nothing new | Analytics is a read concern; no new invariant |
| Application (`Abstractions`) | The read **ports' query signatures kept**; one new small port `IAnalyticsFreshnessReadStore`; new **event contracts** in `Ago.Chat.Contracts` | Dependency rule: Application declares the ports, knows neither ClickHouse nor which Postgres database backs them. Query signatures unchanged; the additive `computedAsOf` comes from the one new freshness port |
| Infrastructure — **new project `Ago.Chat.Infrastructure.Analytics`** | The ClickHouse client (ingest writer + the aggregator's raw source read); the Dapper rollup read-store implementations on the `AnalyticsDb` connection; the aggregator's rollup upsert into `ago_analytics`; the `AnalyticsRollupDbContext` EF migrations for the rollup schema | `adr/0004`'s read side, in its own adapter because the ClickHouse driver is new and the analytics connection strings are wired in one place. Keeps the ClickHouse dependency out of `Infrastructure.Postgres` and off the report read path |
| Host (`Ago.Chat.Worker`) | `AnalyticsIngestConsumer`, `AnalyticsRollupAggregator`, the backfill job, DI wiring, options — including the `AnalyticsDb` connection string | Consumers/BackgroundServices run in Worker (`messaging.md`); DI wiring lives only in hosts (rule 1) |

**Both external resources sit behind ports (rule 2)** — no ClickHouse client and no `AnalyticsDb`-specific
type leaks into Domain or Application. The one new NuGet is a ClickHouse ADO.NET provider (e.g.
`ClickHouse.Client`); it replaces hand-rolling the HTTP + RowBinary protocol, and hand-rolling is worse
because batched inserts, connection pooling and type mapping are exactly the fiddly, well-solved parts a
maintained provider gives — state the package and this reasoning in the slice that adds it. The
`AnalyticsDb` reads reuse the Dapper/Npgsql stack already present (`adr/0004`), so they add no package.

## 9. Tenant-local-day handling

**The day boundary is the tenant's IANA zone, not UTC.** This is a decided constraint, and it changes two
things from the earlier (UTC-day) draft.

- **Where the zone comes from.** AGO Chat's `sites` table has **no** IANA zone column today — the calendar
  product owns zones (`adr/0049`), chat has never needed one. So this design **adds `sites.time_zone`**
  (IANA string, e.g. `Europe/Moscow`), defaulting to **`Europe/Moscow`** for every existing row — the
  first clients are Russian, so MSK (UTC+03:00, no DST) is the sensible default; per-site editable later.
  The IANA name `Europe/Moscow` is stored, **not** a fixed `+03:00` offset, so it stays correct if policy
  ever reintroduces DST. The enriched `ConversationStarted` integration event carries `tenant_zone`
  resolved from the site at publish time, so every raw event self-describes its zone and the aggregator
  needs no lookup.
- **How the local day is computed.** `local_day = toDate(occurred_at, tenant_zone)` in the aggregator's
  ClickHouse source query. Storing the **UTC instant + the zone string** per event (never a pre-localised
  day) means the raw layer is zone-agnostic and any future re-slice — a different zone, an hourly bucket —
  is still possible.
- **DST** is handled by the engine's tz database: `toDate(instant, zone)` maps each instant to the correct
  local calendar day across a DST transition, and the at-least-one-DST-boundary test (`date-and-time.md`)
  covers it — meaningful for a non-`Europe/Moscow` tenant, since MSK itself has no DST.
- **A zone that changes** (a tenant edits `sites.time_zone`) re-labels *future* events; past raw events
  keep the zone they were stamped with, so historical days do not silently re-bucket. If a full re-label is
  ever wanted, it is a raw re-read (backfill, §10) — not a schema problem.

## 10. Backfill from existing Postgres

Both stores are empty for history that predates them. A one-time, **re-runnable** Worker backfill job reads
existing `conversations` / `messages` / `conversation_tags` / outcomes from the operational `ago_chat`
(read-only, off-peak — this is the one place the old O(N) read still runs, once, offline, never on the
request path), synthesises the corresponding raw events with their historical `occurred_at` and the site's
`tenant_zone`, and inserts them into ClickHouse `analytics_events`. The aggregator then builds the rollups
into `ago_analytics`.

It is idempotent by construction: each synthesised row's `event_id` is **derived deterministically** from
the source row id + event kind, so a second run inserts identical rows that the `ReplacingMergeTree`
collapses. It is also the **reconciliation tool** — if the rollups are ever suspected wrong, re-run
backfill for a window and let the aggregator rebuild that day's `ago_analytics` rows.

## 11. Retention, cost, backup

- **Raw retention (ClickHouse).** The author wants raw kept for future report development, with no lossy
  pre-quantization. At this product's volume ClickHouse's columnar compression makes raw cheap; the
  recommendation is to **keep raw indefinitely for now** and add a TTL (or an S3/MinIO cold-tier via a
  ClickHouse S3 disk) only when a measured size justifies it. Rollups in `ago_analytics` are tiny and kept
  indefinitely.
- **Backup — two surfaces now.**
  - **`ago_analytics` (Postgres): automatic.** `k8s/backup/backup.sh` no longer backs up a hardcoded list
    — since 2026-09-02 it **asks Postgres which databases exist** (`select datname from pg_database where
    datistemplate = false and datname <> 'postgres'`) and dumps each with `pg_dump -Fc`, and its manifest
    records row counts per dumped database. So the new `ago_analytics` database is **picked up
    automatically** the moment it exists — no `backup.sh` change is needed for it, and the restore drill's
    per-database row-count comparison covers it for free. (Confirmed against the current script; this is the
    "asks Postgres which databases exist" property from `take-a-backup`. If a future change ever reverts
    that to a hardcoded list, `ago_analytics` must be added — flagged here so the dependency is explicit.)
  - **ClickHouse (raw): a new explicit step.** ClickHouse is *not* Postgres, so `backup.sh` must gain a
    **ClickHouse step** — `BACKUP DATABASE analytics TO S3(<minio>/…)` (reusing the MinIO already backed
    up), or `clickhouse-backup` — added to the same GPG-encrypt-and-pull pipeline and **named in the backup
    manifest's enumeration** so a run that silently omits it is caught (`take-a-backup`, "the failure that
    looks like success").
  - **Restore priority.** Rollups (`ago_analytics`) are reconstructable from raw; raw (ClickHouse) is
    reconstructable from `ago_chat` by backfill for the window `ago_chat` still holds — so the genuinely
    irreplaceable data is raw events older than what `ago_chat` can reproduce (e.g. after a conversation is
    erased or pruned). That is what the ClickHouse backup protects; the `ago_analytics` dump is a
    convenience that saves a re-aggregation.
- **Secrets — two now.** `CLICKHOUSE_PASSWORD` (raw store) and `ANALYTICS_DB_PASSWORD` (the `ago_analytics`
  role) in `infra-credentials`, both read by `Ago.Chat.Worker` (ingest + aggregate) and `ANALYTICS_DB_PASSWORD`
  also by `Ago.Chat.Api` (reads). Each gets a row in `secrets.md` (rotation class **Restart** — the
  processes reconnect; stored data is not encrypted under either) and a key in each `.env.example`.
- **Personal data — two places now.** Both stores hold `visitor_id` / `conversation_id` / `operator_id` —
  identifiers that single out individuals — but **no message body, name or phone** (`messaging.md` /
  `personal-data.md`): ClickHouse in raw rows, `ago_analytics` in id-keyed rollup rows (`dimension_key` may
  be an operator_id). Both are **new places personal data lives**, and `personal-data.md` gets a row for
  each in the same change. Erasure: the ids may legitimately **dangle** after a single conversation is
  erased — the same decision `conversation_assignments` already makes ("erasing a conversation must not take
  last month's numbers with it"), since both stores hold counts and ids, not content. A **site-level**
  erasure (`SiteErased`, already published, `messaging.md`) is the one that should propagate: the analytics
  consumer subscribes to it and `ALTER TABLE analytics_events DELETE WHERE site_id = …` in ClickHouse **plus**
  `DELETE FROM analytics_daily_rollups WHERE site_id = …` in `ago_analytics`, so a wholly-erased tenant
  leaves no analytics trace in either store. Recommended, and called out as a consequence rather than
  silently assumed.

## 12. Performance — the load test to run (rule 7)

No numbers are invented here. This states the test that must produce them before any "it scales" claim,
following the `load/` convention (k6, honest reporting into `load/reports/`).

- **Seed** the operational `ago_chat` to realistic volume (e.g. 10k / 100k conversations across a 30-day
  window, with message histories and a mix of channels, operators, referrers, campaigns, tags, outcomes) —
  a seeding script, not the demo tenant.
- **Backfill:** run it at each volume; time it; run it **twice** and assert ClickHouse raw row count is
  stable (dedup) and `ago_analytics` rollups identical (idempotent/re-runnable).
- **Ingest throughput:** drive conversation-lifecycle events through outbox → broker → consumer; measure
  events/sec the `AnalyticsIngestConsumer` sustains, batch-flush latency, ClickHouse insert rate, consumer
  lag under a burst — and, the load-bearing check, that **operational-`ago_chat` write-path metrics are
  unchanged** (the entire point of moving the load off it).
- **Aggregator:** measure per-day recompute time for the busiest day at each volume (ClickHouse source scan
  + `ago_analytics` delete-insert), and confirm one full scheduled run completes well inside its hourly
  cadence at the top volume (so `computedAsOf` keeps advancing). Freshness here is the batch cadence by
  design (§7.2), not a near-real-time target — the test confirms the cadence is *achievable*.
- **Reads:** p50/p95/p99 for `/analytics`, `/analytics/me`, `/conversion-report`, `/tag-breakdown`
  against the **current** compute-on-read `ago_chat` stores (the baseline that regresses, expected to climb
  ~linearly with volume) and against the `ago_analytics` rollups (expected flat in total history, linear
  only in requested day count, plus the small app-layer label merge, §8.1). Report the crossover and the
  absolute p95.
- **Idempotency / late events:** replay a batch, assert counters unchanged; inject an out-of-order and a
  late event, assert the affected day reconciles.

Until those numbers exist the claim is "expected O(days)", not "measured".

## 13. Slice breakdown

Vertical slices, each landing one promise green (rule 15). Dependencies noted. Two schema paths are in
play and must not be conflated: the **`ago_chat` EF migration** (`sites.time_zone`) is the one that goes in
the **migration lane** (rule 13, one migration in flight at a time); the **`ago_analytics` rollup schema**
is its **own EF migration path** — a separate `AnalyticsRollupDbContext` with its own `__EFMigrationsHistory`
inside `ago_analytics`, run by a dedicated analytics-migrator job, not sharing `ago_chat`'s migrations
ledger — and the ClickHouse DDL is not an EF migration at all. As a matter of prudence only one schema
change is in flight at once. **`ago-deploy`/infra** is flagged where a slice touches it.

| # | Slice | Depends on | Size | Repo / lane |
|---|---|---|---|---|
| S1 | **`sites.time_zone` + event contracts + publishers.** Add `sites.time_zone` (IANA, default `Europe/Moscow`; EF migration). New integration events (`ConversationStarted` enriched with channel/referrer/campaign/**tenant_zone**; `ConversationOutcomeRecorded`; `ConversationTagged`/`Untagged`; confirm `ConversationEnded` carries `closed_at`), each staged to the outbox in the same transaction (rule 4), with mappers + contract tests. No consumer yet. | — | ago-chat · **migration lane** (`ago_chat` EF) |
| S2 | **Both analytics stores on the stand.** (a) **ClickHouse**: Deployment + Service + RWO PVC (rabbitmq/minio shape); `CLICKHOUSE_PASSWORD` in `infra-credentials` + `.env.example`; `secrets.md` row; `backup.sh` **ClickHouse** step + manifest enumeration. (b) **`ago_analytics` Postgres DB**: an idempotent bootstrap (Keycloak-pattern init/job) creating role `analytics` + `ANALYTICS_DB_PASSWORD` and `CREATE DATABASE ago_analytics OWNER analytics`; the `AnalyticsDb` connection string wired into Worker + Api; `ANALYTICS_DB_PASSWORD` in `infra-credentials` + `.env.example` + `secrets.md`. (c) `personal-data.md` rows for both stores. Confirm `backup.sh` picks up `ago_analytics` automatically (it enumerates databases — no script change) and names ClickHouse explicitly. Both come up healthy; a backup names both surfaces. | — | **ago-deploy + ago-root docs** |
| S3 | **Raw event schema + ClickHouse DDL runner.** `analytics_events` (`ReplacingMergeTree`, partitioning, ordering); a small idempotent ClickHouse DDL runner (`CREATE … IF NOT EXISTS`) in `Ago.Chat.Infrastructure.Analytics`; ClickHouse connection behind config. | S2 | ago-chat |
| S3b | **`ago_analytics` rollup schema migration.** `AnalyticsRollupDbContext` + first EF migration for `analytics_daily_rollups` and `analytics_rollup_runs`, its own `__EFMigrationsHistory` in `ago_analytics`; the analytics-migrator job runs it against `AnalyticsDb`. Separate migration path from `ago_chat` (its own DbContext + history table). | S2 | ago-chat · **its own migration path** (not the `ago_chat` lane) |
| S4 | **Ingestion consumer.** `AnalyticsIngestConsumer` (competing; batched ClickHouse inserts; `event_id` dedup; **no Postgres inbox**) subscribed to S1's topics + `MessageAccepted`. Testcontainers (ClickHouse) test: events in → raw rows correct; redelivery → deduped. | S1, S3 | ago-chat |
| S5 | **Scheduled aggregator (ClickHouse→`ago_analytics`).** `AnalyticsRollupAggregator` (`PeriodicTimer`, configurable cadence, **default hourly**) reads deduplicated raw from ClickHouse and writes rollups into `ago_analytics` via per-day delete-then-insert; `local_day = toDate(occurred_at, tenant_zone)`; records `analytics_rollup_runs`. Test (ClickHouse + Postgres Testcontainers): raw → rollups correct; a DST-boundary day (non-MSK tenant); a late event rebuilds its day; `computedAsOf` advances only on a successful run. | S3, S3b, S4 | ago-chat |
| S6 | **Backfill job.** Reads `ago_chat` history → synthesises raw events (deterministic `event_id`) → ClickHouse; re-runnable; is also the reconciliation tool. | S3 (S5 to verify parity) | ago-chat |
| S7a | **Switch site + own analytics reads + `computedAsOf`.** Reimplement `OperatorAnalyticsReadStore` as **Dapper on `AnalyticsDb`** (query signature unchanged); id-keyed rows with operator-name resolution merged from `ago_chat`'s existing read port in the handler (§8.1, no cross-DB join); add `IAnalyticsFreshnessReadStore` and the additive `computedAsOf` field (§8). Parity test: rollup read (+ app-layer merge) == old SQL on a fixture; response carries a freshness marker. | S5, S6 | ago-chat |
| S7b | **Switch conversion read.** Reimplement `ConversionReportReadStore` as Dapper on `AnalyticsDb` against the rollup conversion columns; keep ranking + `MinimumSampleForRate` in C#; operator names merged in the handler. | S5, S6 | ago-chat |
| S7c | **Switch tag-breakdown read.** Reimplement `TagBreakdownReadStore` as Dapper on `AnalyticsDb` against `tag` + `total` rows; tag labels merged from `ago_chat`'s tag read port in the handler. | S5, S6 | ago-chat |
| S8 | **Load test + report.** §12, into `load/scenarios/` + `load/reports/`. Gates the "it scales" claim. | S7a–c | ago-chat |
| S9 (optional) | **Module-flow rollup.** `ModuleTaskOpened`/`Closed` events + counters; simple additive; low priority. | S1, S4, S5 | ago-chat |
| — (deferred) | **Operator-load rollup.** Its `concurrent_load` overlap does not reduce to an additive daily counter and it was not the 499 culprit; leave compute-on-read until measured slow (`data-model.md`). Revisit as its own design. | — | — |

Ordering: **S1 and S2 first** (S1 in the `ago_chat` migration lane; S2 is pure infra, independent — and
provisions *both* stores). **S3** needs ClickHouse up; **S3b** needs `ago_analytics` up (its own migration
path, parallelisable with S3); **S4** needs contracts + ClickHouse schema; **S5** needs raw arriving *and*
the `ago_analytics` schema; **S6** unblocks the read switches with history. **S7a/b/c** switch one report
each — each deployable alone with the old `ago_chat` stores still correct behind their unchanged ports (a
genuine split, not "first breaks, second fixes"). **S8** last. Each read switch is one promise that lands
green independently.

## Decisions folded in (previously open)

Both former open questions are now decided by the author and reflected above; recorded here for traceability:

1. **`sites.time_zone` default = `Europe/Moscow`** (IANA name, not a fixed offset; first clients are
   Russian; per-site editable later; a zone change re-labels future events only, never historical days).
   Storage stays UTC (rule 11); the zone sets only the tenant-local-day boundary.
2. **Aggregator cadence = hourly** by default (configurable, loosenable to daily). Max staleness ~1 h;
   `computedAsOf` reflects the last successful hourly run.
3. **Module-flow (S9) and operator-load (deferred): in or out of this milestone?** Still the author's call
   at scheduling time — module-flow is a cheap additive add (include if capacity allows); operator-load
   genuinely does not fit the daily-counter shape and is not the timeout culprit, so it stays deferred as
   its own design. This is a scheduling choice, not a design gap.
