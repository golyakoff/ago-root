# Non-functional requirements and targets

These are **targets to validate**, not measurements. Nothing here may be quoted as an achievement
until Stage 7 produces a report with real numbers on named hardware. A portfolio project that claims
throughput it never measured is worse than one that claims nothing.

## Scale targets (single local cluster, 3 Api replicas, 2 Worker replicas)

| Metric | Target | Why this number |
|---|---|---|
| Concurrent WebSocket connections | 20 000 total | Enough to make per-connection memory and GC pressure visible |
| Sustained message ingest | 3 000 msg/s | Enough that per-row inserts fail and batching has to be real |
| Peak burst ingest | 10 000 msg/s for 30 s | Exercises channel backpressure instead of hiding it |
| Attachment uploads | 50/s | Presign + verify path only; bytes bypass the API entirely |
| Conversations in the waiting queue | 10 000 | Makes assignment contention measurable |

## Latency targets

| Path | p50 | p95 | p99 |
|---|---|---|---|
| Send -> ack (persisted) | 15 ms | 50 ms | 150 ms |
| Send -> delivered to a recipient on another node | 40 ms | 120 ms | 300 ms |
| History page (50 messages, keyset) | 5 ms | 20 ms | 60 ms |
| Widget handshake (cache hit) | 5 ms | 15 ms | 40 ms |
| Waiting -> assigned, queue non-empty | 100 ms | 500 ms | 2 s |

The end-to-end number carries one broker hop plus the outbox dispatch interval by design
(`realtime.md`, `messaging.md`). If it misses, the dispatcher's poll-with-notify latency is the first
suspect, not the database.

## Correctness under stress (binary, not statistical)

These either hold or the build is broken:

- Zero acknowledged-but-lost messages while killing an Api pod and a Worker pod mid-load.
- Zero out-of-order deliveries within a conversation, at any concurrency.
- Zero duplicate persisted messages despite at-least-once delivery and client retries.
- Zero operators above their configured capacity, at any assignment contention.
- Zero unbounded queues: memory stays flat under sustained overload; senders are slowed, not dropped
  silently.

## Resource budgets

- Api pod: 512 MB, 0.5 CPU at target load. Per-connection memory is a tracked metric, since it is
  what decides the connection ceiling.
- Worker pod: 512 MB, 1 CPU.
- Postgres connections: pooled, ceiling well below the server max, with the pool exhaustion path
  tested (it must queue and time out cleanly, not deadlock).

## Availability behaviour

Not an uptime SLA - this is a demo cluster. What matters is the documented degradation path in
`realtime.md`: which dependency failure degrades, which rejects, and which is allowed to lose data
(only Redis, and only ephemeral data).

Still not an SLA after `roadmap.md`'s Stage 15 (added 2026-08-24), which is deliberately about
*recoverability and noticing*, not availability: backup with a restore that has been performed,
alert rules that reach a person, bounded growth, and deliberate capacity. The distinction matters -
promising uptime would need a second node and a second of everything under it (`adr/0026`), whereas
being able to come back from a lost disk, and to find out that something broke, does not.

**The "finding out" half now exists** (`15-03`, 2026-08-25, `adr/0045`): five Prometheus rules
evaluated on the public deployment, delivered by Alertmanager as email through the node's own Postfix,
with `runbooks/alerting.md` carrying what each means and what to check first. Two things about it
matter to this document specifically:

- **No rule on this page's latency targets, and that is deliberate.** The numbers above are targets to
  validate under load, not promises to a user, and the demo carries no load. Alerting on a p99 nobody
  promised, measured on traffic that does not exist, produces noise rather than signal. Only two of
  the five rules derive a threshold from this file at all — the outbox-lag rule reads its 60 s from
  the 300 ms cross-node p99 the table above says the dispatch interval lives inside, and the
  dead-letter rule reads its zero from "Correctness under stress" being binary. The disk rule's 15% is
  labelled in `adr/0045` as a headroom *choice*, because this document states no disk target and
  inventing one to alert against would be exactly backwards.
- **Still not an SLA, and now demonstrably not an availability guarantee**: the alerting path runs on
  the node it watches, so it cannot report that the node is gone. An external check is a separate
  mechanism and is still an open question in `15-03`.

**The "coming back" half exists too** (`15-02`, 2026-08-25, `adr/0050`), and it produced the first
recovery numbers this project has that are measurements rather than estimates. Restoring both Postgres
databases and the object store from one encrypted artifact into an empty target took **14–17 s** end to
end, over two complete runs; the artifact is **1.08 MB** and takes **4–5 s** to produce. Two readings of that, both of which
belong here rather than in the runbook:

- **Recovery time on this deployment is not bounded by moving data.** At this size the data is
  seconds. What a real recovery costs is rebuilding the cluster and getting images onto it — `15-06`'s
  subject. Any future effort to shorten recovery belongs there, not in faster backups.
- **This is still not an RPO, and the reason is not the schedule.** The node backs up daily, but the
  copy that survives losing the node is the one collected onto a personal machine, so the honest
  recovery point is "since that machine was last on and ran the pull". `adr/0050` states that plainly
  as the cost of the destination the author chose. Writing a number here instead would be inventing
  one.

## Observability requirements

Everything above must be visible without attaching a debugger:

- RED metrics per endpoint, hub method, and consumer.
- Queue depth, channel occupancy, batch size histogram, outbox lag, DLQ count.
- Cache hit ratio per key namespace, breaker state.
- Connection count per node, assignment attempts vs conflicts.
- Fan-out delivery: recipients resolved and how many of them the connection registry believed
  present, and how many dispatches met a connection the target node still held (`7-08`,
  `adr/0044` for why those dimensions and not a raw count). Without it, a message that reached
  nobody is indistinguishable from one that reached everybody - which is what made a real incident
  take an hour instead of a minute.
  (`7-02` — every bullet above is a real, tagged, tested OTel instrument; queue depth and channel
  occupancy are the same metric, `concurrency.md`'s pipeline has exactly one bounded channel. Full
  metric-name/tag catalogue: `Ago.Chat.Contracts.ChatMetrics` and `Ago.Platform.*.{ResilienceMetrics,
  CachingMetrics, RealtimeMetrics, RabbitMqMetrics}` are the source of truth; `7-03` gives them a
  Grafana home.)
- Traces spanning hub -> handler -> DB -> outbox -> broker -> consumer -> delivery, one trace id
  end to end (`7-01`, proven by `Ago.Chat.Integration.Tests.TracingEndToEndTests` against an
  in-memory exporter — a live Jaeger is `7-03`'s job). This is what makes the p95 numbers
  explainable instead of merely reportable.

## Reporting thresholds

Not a scale or latency target - a correctness-of-presentation rule with one number in it, recorded
here because `23-16`'s own Done-when asks that the number's home be named explicitly rather than left
implicit in the code that reads it.

- **`Analytics:MinimumSampleForRate`** (default **10**) is the line below which a report may not
  *rank* rows on a rate. `docs/design/decisions.md` §7's amendment: a rate is never refused for a
  thin sample - "50% (1 of 2)" prints in full, with its own fraction, no matter how small the
  denominator - but a row whose own sample is thinner than this threshold is never sorted ahead of
  another row on the strength of that rate. `ConversionReportReadStore.byOperator` and
  `TagBreakdownReadStore.byTag` are the only two lists in this codebase's analytics family that rank
  on a rate at all; see `adr/0103` for the full design and why `OperatorAnalyticsReadStore`/
  `ModuleFlowReadStore` take no dependency on this value.
- **This is configuration, not a constant.** Bound from `Analytics:MinimumSampleForRate`
  (`Ago.Chat.Application.Abstractions.AnalyticsOptions`), validated at startup
  (`.AddOptions<AnalyticsOptions>().Validate(...).ValidateOnStart()` in `ChatModule.cs`, the same
  shape every sibling options class in this codebase already uses) so a malformed value fails the pod
  at boot rather than silently ranking every report by an unintended number. `10` is stated as an
  unmeasured, deliberately round operational default - the same "hardcode a sane unmeasured default"
  precedent `RegisterSiteRateLimitOptions` already sets, contrasted with `BillingOptions.PricePerSeatRub`'s
  own no-default rule for a figure that charges a card: a wrong guess here costs a reordered table
  row a site owner can see and mentally correct for, never money or lost data.
