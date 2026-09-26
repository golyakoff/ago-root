# Analytics: from compute-on-read to pre-computed rollups

**Status:** design proposal. Decision recorded in [`adr/0186`](../adr/0186-precomputed-analytics-rollups.md).
**Scope:** AGO Chat's operator/site analytics family (Stage 18 `18-08`..`18-14`, plus the calendar-side
phone-reveal and booking-funnel reports). No platform-shape change — a product-local read-model change
of the kind `adr/0004` already governs.

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
conversation started in the last 30 days" into a point read; the aggregate *is* the work.

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

Two of these are already the right shape and are the precedent this design generalises:

- **`site_widget_activity`** (`23-07`) is a per-`(site_id, day)` counter table, maintained by an
  `ON CONFLICT (site_id, day) DO UPDATE SET loads = loads + excluded.loads` incremental upsert
  (`WidgetActivityWriter`). Its read (`WidgetActivityReadStore`) is a trivial `SUM` over a day range —
  **O(days), instant.** This design says: do that for the rest of analytics, off the outbox rather than
  off a best-effort in-memory accumulator.
- **Phone reveals** are already a keyset list of individual receipt rows, not an aggregation — nothing to
  pre-compute. It stays as is.

## 3. Events available vs. events needed

The platform already has the machinery this design needs: a transactional **outbox** (state change + integration
event in one transaction, `adr/0005`), the **`OutboxDispatcher`** draining it to RabbitMQ, **competing idempotent
consumers** with an **`inbox` ledger** (`(message_id, consumer)`, `adr/0017`), and the exact precedent consumer —
**`UnreadCounterConsumer`**, which maintains a counter off `MessageAccepted` idempotently. A rollup consumer off
the outbox is the natural fit (see §5). But the current event set was built for delivery and fan-out, not for
analytics, so some inputs are not yet on the broker.

| Analytics input | Event today | Gap |
|---|---|---|
| Conversation started (+ site, visitor) | `ConversationStarted` **domain event only — no mapper, not published** | Needs an integration event, **enriched** with the read-time attribution dimensions: resolved channel label, `traffic_referrer_host`, `traffic_utm_campaign` |
| First visitor / first operator message | `MessageAccepted` (published; carries `conversation_id`, `author_kind`, `sequence`, `OccurredAt`) | **Sufficient** — the consumer derives first-of-kind timestamps from the stream |
| Operator attribution | `ConversationAssignedToOperator`, `ConversationTransferred` (both published) | Sufficient for the assigned-operator fallback; first-operator attribution comes from `MessageAccepted` |
| Conversation closed (+ duration, missed) | `ConversationClosed` → wire `ConversationEnded` (published) | **Needs to carry `closed_at`** (it may already; confirm) — duration and missed are resolved at close |
| Conversion outcome | `SetConversationOutcomeHandler` writes `conversations.outcome` — **no integration event** | Needs `ConversationOutcomeRecorded` (carries new outcome; supersedes prior) |
| Tags | `TagConversation` / `UntagConversation` — **no integration event** | Needs `ConversationTagged` / `ConversationUntagged` (carry `tag_id`) |
| Booking-funnel task | `module_tasks` open/close — **no integration event** | Needs `ModuleTaskOpened` / `ModuleTaskClosed` (carry `module_key`) — or leave module-flow compute-on-read (§9) |
| Phone reveals | `contact_reveals` row write — no event | **No change** — a receipt list, not an aggregate |

Every new event obeys the existing contract rules (`messaging.md`): past-tense fact, ids + immutable values
only, **no message body / no personal data on the wire** (`personal-data.md`), keyed by `conversation_id`,
`MessageId` as the idempotency key. Each is staged to the outbox **in the same transaction** as the state
change it reports (rule 4) — e.g. `ConversationOutcomeRecorded` beside the `outcome` column write.

## 4. The pre-computed model

Two layers, matching the "raw events + rollups layered on top" (the author's Grafana analogy), realised in
Postgres rather than a separate store (§5 argues why Postgres earns it here):

### 4.1 Layer 1 — a per-conversation fact projection

`analytics_conversation_facts` — **one row per conversation**, the materialised current state the rollup deltas
are computed against. This is what makes incremental maintenance both *correct under change* (an edited outcome,
a removed tag) and *naturally idempotent* (reprocessing recomputes the same state).

| Column | Notes |
|---|---|
| `conversation_id` (PK) | |
| `site_id`, `created_at` (timestamptz), `created_day` (date) | `created_day` = `created_at` at **UTC** (§4.4) — the bucket this conversation belongs to, fixed for life |
| `channel_label`, `attributed_operator_id`, `referrer_label`, `utm_campaign` | the resolved attribution dimensions — the same values the current `SiteAnalyticsSql` computes at read time, resolved once here |
| `first_visitor_at`, `first_operator_at` (nullable) | `min()` folded from the `MessageAccepted` stream |
| `closed_at` (nullable), `state`, `outcome`, `missed` (bool) | resolved at close / outcome events |
| `applied_hash` or per-metric "last contributed" snapshot | what this row last added to the rollup, so a delta is `new − old` |

Tags are a child table `analytics_conversation_fact_tags (conversation_id, tag_id)` because a conversation holds
zero-to-many — the same reason `TagBreakdownReadStore` runs a separate fan-out query today.

This layer is bounded (one row per conversation, indexed by `(site_id, created_day)`), and it replaces the
expensive `LEFT JOIN LATERAL` over the 64-partition `messages` table with an **incremental fold** done once per
message as it happens, instead of re-scanning history on every read.

### 4.2 Layer 2 — daily rollup buckets

`analytics_daily_rollups` — a **narrow, long** table generalising the current `GROUPING SETS` output:

| Column | Notes |
|---|---|
| `site_id`, `day` (date, UTC), `dimension_type`, `dimension_key` | PK. `dimension_type` ∈ {`total`, `channel`, `operator`, `referrer`, `campaign`, `tag`}. `dimension_key` = the channel label / operator id / host / campaign / tag id, or `''` for `total` |
| `conversation_count` (bigint) | |
| `first_response_seconds_sum`, `first_response_count` | avg first-response = sum / count (decomposed, per `date-and-time.md` "ordering never depends on a clock" and `OperatorLoadReport`'s own sum-of-sums fold) |
| `duration_seconds_sum`, `duration_count` | avg duration = sum / count |
| `missed_count` | |
| `converted_count`, `not_converted_count`, `follow_up_count`, `unset_count`, `recorded_count` | conversion metrics (meaningful at `total` and `operator` scope; zero elsewhere). Rate = converted / recorded, computed at read |

A single conversation contributes to **five rows for its `created_day`** — `total` + its channel + operator +
referrer + campaign — exactly reproducing GROUPING SETS, plus one `tag` row per tag it holds. Storing rates and
averages **decomposed** (numerator/denominator, sum/count) is load-bearing: counters must be additive to be
maintainable incrementally, and the read reconstitutes the rate — never the store.

Reads become: `SELECT … WHERE site_id = @s AND day >= @from AND day < @to GROUP BY dimension_type, dimension_key`
— **O(days), a bounded scan on the PK**, no `messages` touch at all.

### 4.3 The rollup consumer (Infrastructure, in `Ago.Chat.Worker`)

A new **competing, idempotent** consumer — the shape `UnreadCounterConsumer` already proves — subscribed to the
analytics-relevant topics. Per message, in **one transaction**:

1. Record `(message_id, consumer)` in the `inbox` ledger; a duplicate is detected, skipped, acked (rule 5).
2. Load (or create) the `analytics_conversation_facts` row for the conversation.
3. Compute the **new** resolved fact from the event; compute the **delta** = new − old across every affected
   `(dimension_type, dimension_key, metric)`.
4. Apply the delta to `analytics_daily_rollups` with `ON CONFLICT (site_id, day, dimension_type, dimension_key)
   DO UPDATE SET metric = metric + excluded.metric` — the identical increment-upsert `WidgetActivityWriter` uses,
   made **idempotent** here by the fact-snapshot delta (re-applying a settled fact yields delta 0) and the inbox
   ledger, where `WidgetActivityWriter`'s best-effort accumulator tolerated loss instead.
5. Persist the updated fact row.

Because the contribution is `new − old` against a stored snapshot, **at-least-once redelivery, out-of-order
arrival, and later corrections are all the same operation**: recompute the fact, re-derive the delta. A
`ConversationOutcomeRecorded` that flips Converted→NotConverted emits `−1 converted, +1 not_converted` with no
special case.

### 4.4 The UTC day boundary, and the one honest tension

Rule 11 stores `timestamptz` and the bucket key is `created_at` **at UTC**. This matches current behaviour: the
existing stores window on raw `DateTimeOffset` comparisons with **no zone applied at all**, and the default
window is `clock.UtcNow.AddDays(-30)` — already instant/UTC-based.

`date-and-time.md` says "any daily aggregation takes an explicit zone parameter." The current endpoints are not
daily aggregations in that sense — they take instant `from`/`to`. Pre-computing to **UTC-day** buckets means the
minimum read granularity becomes one UTC day: a `from`/`to` is snapped to UTC-day boundaries. For the 30-day and
7-day windows every screen actually uses this is exact; sub-day windows (which no screen requests) are no longer
served. A future tenant-local-day refinement — bucketing by the tenant's IANA zone, or keeping UTC buckets and
re-summing with a zone offset — is a separate decision, flagged as an **open question** below, not built in blindly.

### 4.5 Backfill

A new rollup table is empty for history that predates it. A one-time, **idempotent** Worker backfill job replays
existing state directly with SQL: it runs essentially the current aggregation SQL, but `GROUP BY created_day`
(and the dimensions), and `INSERT … ON CONFLICT DO NOTHING` (or a from-scratch rebuild guarded by a marker) into
the rollup tables and fact projection. This is the one place the old O(N) query is still allowed to run — once,
offline, not on the request path. It is re-runnable (a `SELECT DISTINCT day` existence guard, the same shape the
calendar's daily projection uses) and lands in the migration lane's wake, not inside the migration.

## 5. Options considered

| Option | What it is | Verdict |
|---|---|---|
| **(a) Outbox-driven rollup tables + per-conversation fact projection, maintained by a new analytics consumer** | §4. Postgres tables, the platform's own outbox/inbox/consumer machinery | **Recommended** |
| (b) Periodic materialized views (`REFRESH MATERIALIZED VIEW CONCURRENTLY` on a timer) | Keep the current SQL, refresh it every N minutes into a matview read by the endpoints | Rejected: the refresh still runs the full O(N) aggregation every cycle — it moves the cost off the request path but does not remove it, and it scales with total history, not with change. Staleness is the whole refresh interval. No incremental path. |
| (c) Dedicated time-series / event store (ClickHouse, TimescaleDB, Prometheus-style) + rollups | The literal Grafana analogy — a separate columnar/TSDB engine | Rejected **for now**: it earns its keep at metrics volumes (millions of points/sec, high-cardinality time series) this product is nowhere near, and it violates the platform's own shape — a new stateful dependency to run, back up, secure and reason about (`secrets.md`, `personal-data.md`), a second source of truth to keep consistent, for aggregate volumes a Postgres rollup table serves from a bounded PK scan. `data-model.md`'s "PostgreSQL is the only source of truth; everything else is a cache, a queue, or a projection" is the rule this would break. Revisit only if a measured Postgres rollup is itself the bottleneck. |
| (d) Hybrid — rollups in Postgres now, keep the door open to (c) | (a) plus a note | This is what (a) *is*: the consumer and the read port are engine-agnostic; moving the rollup store later is an Infrastructure swap, not a contract change |

**Recommendation: (a).** It reuses machinery that already exists and is already proven in production
(`OutboxDispatcher`, the inbox ledger, `UnreadCounterConsumer`, `site_widget_activity`'s increment-upsert),
introduces no new operational dependency, keeps Postgres the single source of truth, and turns every analytics
read into a bounded O(days) scan. The "Grafana" instinct is right about the *architecture* (raw resolved facts +
rollups) and wrong only about the *engine* — at this product's volume Postgres is the engine.

## 6. How it fits Clean Architecture

| Layer | What goes here | Why |
|---|---|---|
| Domain | Nothing new | Analytics is a read concern; no new invariant |
| Application (`Abstractions`) | The **rollup read ports** — either the existing `IOperatorAnalyticsReadStore` / `IConversionReportReadStore` / `ITagBreakdownReadStore` interfaces kept **unchanged** (only their implementation swapped), or narrower rollup-shaped ports if the response DTOs change. New **event contracts** in `Ago.Chat.Contracts`. The consumer's work, if it invokes a use case, is an Application handler (the `RecordUnreadMessageHandler` shape) | Dependency rule: Application declares the port, knows no Npgsql. Keeping the read ports' signatures means the endpoints and handlers (`GetOwnAnalyticsForOperatorHandler`) are untouched — the swap is invisible above Infrastructure |
| Infrastructure (`Infrastructure.Postgres`) | The rollup read-store implementations (Dapper over `analytics_daily_rollups`), the fact-projection writer, the migration | `adr/0004`: Dapper for read models. Same place `WidgetActivityReadStore` already lives |
| Host (`Ago.Chat.Worker`) | The new analytics **consumer** (`BackgroundService`, competing, idempotent), its options, DI wiring; the backfill job | Consumers run in Worker (`messaging.md`); DI wiring lives only in hosts (rule 1) |

**What stays vs. changes in the three current read stores:**

| Store | Change |
|---|---|
| `OperatorAnalyticsReadStore` | **Reimplemented** against `analytics_daily_rollups`. The `LEFT JOIN LATERAL` over `messages` and the `GROUPING SETS` pass are deleted; the read becomes a grouped range scan. The `GROUPING SETS` *semantics* (total + per-dimension, the `grouping()` disambiguation, the "no manufactured zero row" rules) move into how rollup rows are selected. The zero-conversation → explicit-zero-bucket special case is preserved. |
| `ConversionReportReadStore` | **Reimplemented** against the conversion columns of the rollup table. The `MinimumSampleForRate` ranking stays in C# (it reads `recorded_count` from the bucket). |
| `TagBreakdownReadStore` | **Reimplemented** against the `tag` dimension rows + a `total` row for coverage. The "counts once per tag, sum ≠ total" property is naturally preserved (tag rows are independent of the total). |
| `OperatorLoadReportReadStore` | **Deferred / possibly unchanged** — see §9. Its `concurrent_load` overlap computation does not reduce to an additive daily counter, and `data-model.md` explicitly calls interval-overlap aggregation "a read concern for whenever a report is measurably slow, not before." Not the 499 culprit. |
| `ModuleFlowReadStore` | Optional rollup (started/closed are simple additive counters); low priority. |

## 7. Consistency and latency contract

- **Eventually consistent.** A counter reflects an event once the outbox has dispatched it and the consumer has
  applied it. Bound = outbox lag + consumer processing. Measured precedents on this stack: outbox publish lag is
  a live gauge (`nfr.md`), and a cross-product outbox→consumer round trip was measured at **~450–490 ms**
  end-to-end (`messaging.md`, `22-08`); a same-process consumer is faster. Analytics tolerates this by nature —
  a 30-day report does not need the last two seconds.
- **No read-your-write guarantee, and that is allowed here.** Rule 8 forbids caching *what a write decision
  depends on* (capacity, sequences, compare-and-set reads). Analytics counters are **not** such a read — no write
  decision consults them — so serving them from a projection is not a rule-8 violation. This is the distinction
  that makes the whole design legal.
- **"Today" (the partial current day)** is served identically to any other day: today's `(site_id, today)` bucket
  rows are updated continuously as events arrive, so a `[from, today]` read includes today's partial bucket as
  fresh as the last consumed event. No special "combine live + rollup" read path is needed — the difference from
  `site_widget_activity` is only that this consumer is outbox-driven and idempotent rather than a periodic flush.

## 8. Performance — the load test to run (rule 7)

No numbers are invented here. This section states the test that must produce them before any "it scales" claim,
following the `load/` convention (`load/scenarios/`, k6, honest reporting).

- **Seed** a site to realistic volume — e.g. 10k / 100k conversations across a 30-day window, each with a message
  history and a mix of channels, operators, referrers, campaigns, tags and outcomes (a seeding script, not the
  demo tenant).
- **Baseline:** measure `GET /conversations/analytics/me` and `/conversations/analytics` p50/p95/p99 against the
  **current** compute-on-read stores at each volume — this is the number that regresses today and the reason for
  the change. Expect it to climb roughly linearly with conversation × message volume.
- **After:** same requests against the rollup stores. Expected shape: **flat in total history, linear only in the
  requested day count** (≤ 30 rows-worth of buckets per dimension). Report the crossover and the absolute p95.
- **Consumer:** measure sustained ingest — events/sec the analytics consumer keeps up with, its lag under a
  message burst, and that the outbox lag gauge stays bounded. Confirm idempotency by replaying a batch and
  asserting counters are unchanged.
- **Backfill:** time the backfill job at each volume; confirm it is re-runnable without double-counting.

Report the real numbers in the load run's `load/reports/` entry. Until then the claim is "expected O(days)", not
"measured".

## 9. Slice breakdown

Vertical slices, each landing one promise green (rule 15). Dependencies noted; **M** marks the migration-lane
slices (one migration in flight at a time, rule 13).

| # | Slice | Depends on | Size | Lane |
|---|---|---|---|---|
| S1 | **Event contracts + publishers.** New integration events (`ConversationStarted` enriched with channel/referrer/campaign; `ConversationOutcomeRecorded`; `ConversationTagged`/`ConversationUntagged`; confirm `ConversationEnded` carries `closed_at`), each staged to the outbox in the same transaction as its state change (rule 4), with mappers and contract tests. No consumer yet. | — | M–L | — |
| S2 | **Rollup + fact schema migration.** `analytics_conversation_facts` (+ `_fact_tags`), `analytics_daily_rollups`, indexes/PKs. EF migration; `down` drops cleanly. Backup before applying (`take-a-backup`). | — | M | **migration** |
| S3 | **The analytics consumer.** Competing, idempotent (inbox ledger), fact-projection + delta upsert, subscribed to S1's topics + `MessageAccepted`. Testcontainers integration test: events in → buckets correct; redelivery → unchanged; out-of-order → correct. | S1, S2 | L | — |
| S4 | **Backfill job.** Worker job that rebuilds facts + buckets from existing `conversations`/`messages`/`conversation_tags` in `created_day` groups; idempotent, re-runnable. | S2, (S3 for parity) | M | — |
| S5 | **Switch site + own analytics reads.** Reimplement `OperatorAnalyticsReadStore` against the rollup; keep `IOperatorAnalyticsReadStore` signature so `GetOwnAnalyticsForOperatorHandler` is untouched. Parity test: rollup read == old SQL on a fixture. | S3, S4 | M | — |
| S6 | **Switch conversion read.** Reimplement `ConversionReportReadStore` against rollup conversion columns; keep ranking + `MinimumSampleForRate` in C#. | S3, S4 | S–M | — |
| S7 | **Switch tag-breakdown read.** Reimplement `TagBreakdownReadStore` against `tag` + `total` rows. | S3, S4 | S–M | — |
| S8 | **Load test + report.** §8, into `load/scenarios/` + `load/reports/`. Gates the "it scales" claim. | S5–S7 | M | — |
| S9 (optional) | **Module-flow rollup** (`ModuleTaskOpened`/`Closed` events + counters). Simple additive; low priority. | S1–S3 | S–M | — |
| — (deferred) | **Operator-load rollup.** The `concurrent_load` overlap does not reduce to an additive daily counter; leave compute-on-read until measured slow (`data-model.md`). Revisit as its own design if a load test flags it. | — | — | — |

Ordering: **S1 and S2 first** (contracts and schema, independent, S2 in the migration lane). **S3** needs both.
**S4** unblocks the read switches with historical data. **S5–S7** switch one report each — each is one promise
that lands green independently. **S8** last. This is a genuine split (each read switch is deployable alone with
the old stores still correct behind their unchanged ports), not a "first breaks, second fixes" cut.

## Open questions for the author

1. **UTC-day vs tenant-local-day buckets.** The design buckets by UTC day (preserves today's instant/UTC
   behaviour; §4.4). `date-and-time.md` anticipates a per-zone daily aggregation. Serve reports on UTC-day
   boundaries for now, and treat tenant-local-day as a later refinement — or bake the tenant's IANA zone into the
   bucket key from the start? (Recommendation: UTC now, refine later — no real tenants yet to need it.)
2. **Operator-load: deferred, or in scope?** It is the one report that does not reduce to an additive counter and
   was not the 499 culprit. Recommendation: defer it (S-deferred) rather than force a rollup shape that fights the
   overlap computation.
