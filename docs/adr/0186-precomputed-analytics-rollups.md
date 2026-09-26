# ADR-0186: Analytics is served from pre-computed rollups, not computed on read

- **Status**: Proposed
- **Date**: 2026-09-26
- **Stage**: 18 (Operator productivity) — a scaling follow-up to `18-08`..`18-14`

## Context

AGO Chat's analytics reads (`IOperatorAnalyticsReadStore`, `IConversionReportReadStore`,
`ITagBreakdownReadStore`, `IOperatorLoadReportReadStore`) compute their aggregates on every request. The
site-analytics query runs a `LEFT JOIN LATERAL` per conversation over the 64-way-partitioned `messages`
table plus a `GROUP BY GROUPING SETS` across five dimensions; the own-analytics endpoint runs **three**
such site-wide aggregations concurrently to keep one operator's row.

The Android «Аналитика» screen timed out (client 499). The backend query measured **~0.5 ms** — but only
because the store holds 132 conversations and 50 messages, all test data, with no real tenants yet. The
cost is **O(conversations × messages-per-conversation) per request**, recomputed on every load, by every
operator, and the aggregate is unindexable because the aggregate is the answer. It is fast because there
is nothing to aggregate.

Forces this must live with:

- The platform already provides a transactional outbox (`adr/0005`), an `OutboxDispatcher`, competing
  idempotent consumers with an `inbox` ledger (`adr/0017`), and EF-for-writes / Dapper-for-reads
  (`adr/0004`). At-least-once delivery is assumed everywhere (rule 5).
- `data-model.md`: PostgreSQL is the only source of truth; everything else is a cache, a queue, or a
  projection. Rule 8 forbids caching what a *write decision* depends on — analytics counters are read by
  no write decision, so a projection of them is permitted.
- `site_widget_activity` (`23-07`) already maintains a per-`(site_id, day)` counter table with an
  increment upsert, read as an O(days) `SUM` — a working precedent inside this codebase.
- Time is UTC `DateTimeOffset` (rule 11); the current reads already window on raw instants with no zone.
- This is a portfolio project: the "obvious production" answer to this problem is a time-series store.

## Decision

Serve analytics from **pre-computed rollups maintained incrementally off the outbox**, in Postgres.

1. **A per-conversation fact projection** (`analytics_conversation_facts`) — one row per conversation
   holding its UTC `created_day`, resolved attribution dimensions (channel, operator, referrer, campaign),
   first-visitor/first-operator timestamps, close/outcome/missed state, and tags. It is the materialised
   current state that rollup deltas are computed against.
2. **Daily rollup buckets** (`analytics_daily_rollups`), keyed `(site_id, day, dimension_type,
   dimension_key)`, storing additive counters and **decomposed** averages/rates (sum + count,
   numerator + denominator). This is a long-table generalisation of the current `GROUPING SETS` output.
3. **A new competing, idempotent analytics consumer** in `Ago.Chat.Worker` (the `UnreadCounterConsumer`
   shape) that, per event, in one transaction: records the `inbox` key, recomputes the conversation's
   fact, derives the delta (`new − old`) across affected buckets, and applies it with an
   `ON CONFLICT … DO UPDATE SET metric = metric + excluded.metric` upsert. New integration events
   (`ConversationStarted` enriched with attribution, `ConversationOutcomeRecorded`, `ConversationTagged`/
   `ConversationUntagged`) are added where the input is not already on the broker, each staged in the same
   transaction as its state change (rule 4).
4. **A re-runnable backfill job** rebuilds facts and buckets from existing rows for history predating a
   rollup.

Reads are reimplemented as an O(days) grouped range scan over `analytics_daily_rollups`; the three
read-store **ports keep their signatures**, so handlers and endpoints are untouched. Buckets are keyed by
**UTC day** (§4.4 of the design), preserving today's instant/UTC read behaviour; minimum read granularity
becomes one UTC day. Operator-load is **deferred** — its concurrent-load overlap does not reduce to an
additive daily counter and it was not the timeout culprit.

Full design, schema and slice plan: [`docs/design/analytics-precompute.md`](../design/analytics-precompute.md).

## Consequences

Positive:

- Analytics reads become O(days), independent of total history — the 499's cause is removed.
- Reuses machinery already in production; no new deployable, no new source of truth.
- The delta-against-a-snapshot design makes redelivery, out-of-order arrival and later corrections
  (an edited outcome, a removed tag) the same operation — no special cases.

Negative / what gets harder:

- **A new write-path cost and a new consumer to operate.** Every conversation lifecycle event now also
  drives an analytics event, an outbox row, and consumer work; the outbox and a new consumer's lag are
  more load to watch.
- **Eventually consistent, not read-your-write.** A counter lags by outbox + consumer latency (sub-second
  to ~½ s on measured precedent). Acceptable for analytics, but it must be stated wherever a number could
  be mistaken for live.
- **New schema to maintain and migrate**, and new integration-event contracts that become public promises
  (`messaging.md` versioning) — including the discipline that they carry no personal data on the wire.
- **A projection that can drift** from the write model through a consumer bug; the backfill job is also
  the reconciliation tool, and needs to stay correct and re-runnable.
- **Read granularity drops to one UTC day** — exact for every window a screen requests, but sub-day
  windows are no longer served, and tenant-local-day boundaries are left as a future refinement.
- Two reporting shapes coexist for a while (rollup-backed reads and the deferred compute-on-read
  operator-load), which is more surface than one uniform mechanism.

## Alternatives considered

- **Periodic materialized views** (`REFRESH MATERIALIZED VIEW CONCURRENTLY` on a timer). Keeps the current
  SQL and moves it off the request path — the smallest change. Rejected: the refresh still runs the full
  O(N) aggregation every cycle, so the cost scales with total history rather than with change, and
  staleness is the whole refresh interval. It defers the scaling problem instead of solving it.
- **A dedicated time-series / event store (ClickHouse, TimescaleDB, or a Prometheus-style backend) with
  rollups on top** — the literal "like Grafana" answer, and the choice many teams would reach for in
  production for analytics at scale. Rejected here deliberately: it adds a stateful deployable to run,
  back up, secure and keep consistent with Postgres (a second source of truth), and it earns that cost
  only at metrics volumes — high-cardinality series, millions of points — this product is nowhere near.
  A Postgres rollup table serves these aggregate volumes from a bounded primary-key scan. The architecture
  the analogy points at (raw resolved facts + rollups) is adopted; only the separate engine is declined,
  and the read port stays engine-agnostic so that decision can be revisited if a measured Postgres rollup
  is itself the bottleneck.
- **Keep compute-on-read, add indexes.** Rejected: there is no index that turns "average first-response
  time across every conversation in 30 days" into a point read. The aggregate is the work.
