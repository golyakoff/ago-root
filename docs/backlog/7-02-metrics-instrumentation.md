# Metrics: RED, pipeline internals, and resilience state, all in one Meter surface

- **Stage**: 7
- **Status**: done
- **Depends on**: `7-01` (shared OTel SDK bootstrap and resource attributes in `Ago.Platform.Hosting`
  — metrics reuse it rather than a second bootstrap), `6-01` (`Ago.Platform.Resilience` — breaker-state
  and bulkhead-rejection instruments live inside the shared pipeline builder, which does not exist
  without it)

## Goal

After this, every number `nfr.md`'s Observability requirements section demands is a real OTel metric,
ready to be scraped by Prometheus (deploy-side wiring is `7-03`): RED per REST endpoint/hub
method/consumer, queue depth and channel occupancy for the message pipeline, the batch-size histogram,
outbox lag, DLQ count, cache hit ratio per key namespace, breaker state and bulkhead rejections per
named resilience pipeline, connections per node, and assignment attempts vs. conflicts.

## Context to read first

`nfr.md`'s Observability requirements section verbatim — this item's own checklist. `concurrency.md`'s
pipeline diagram and its "Shipped in `4-05`" paragraph, which names the exact types to instrument
(`ChannelMessagePipeline`, `BatchAccumulator`, `MessageBatchWriter`) — queue depth, channel occupancy
and the batch histogram are literally these types' own internal state, not new concepts.
`messaging.md`'s outbox/DLQ sections. `caching.md` for the hit-ratio-per-namespace shape. `realtime.md`'s
connection registry for per-node connection counts. `concurrency.md`'s assignment section — a
`TryClaimAsync` row-count-0 is already "a normal outcome to retry, not an error to log at `Error`
level"; this item counts it instead of only logging it at `Debug`. `6-01`'s own resilience-package
scope (breaker/bulkhead exist as named pipelines, e.g. `Redis`, `S3` — this item adds the instrument
to the pipeline builder itself, not a new pipeline per boundary).

## Scope

- `Ago.Platform.Hosting`: `AddPlatformMetrics(...)` (or folded into `7-01`'s `AddPlatformObservability`)
  wiring an OTel `MeterProvider`, plus ASP.NET Core and `HttpClient` instrumentation for the RED
  numbers those packages already know how to produce.
- Manual instruments where nothing off-the-shelf sees the internals:
  - Hub methods and broker consumers: a RED triad (duration histogram, count split success/error) at
    the same span boundaries `7-01` already named — "per hub method" and "per consumer" are not things
    ASP.NET Core's own instrumentation knows about.
  - `ChannelMessagePipeline`/`BatchAccumulator` (`Ago.Chat.Module.Pipeline`): channel-occupancy
    `ObservableGauge` (reader count against configured capacity), batch-size histogram, enqueue-wait
    histogram.
  - Outbox dispatcher (`2-04`): a lag gauge (`now - oldest unpublished outbox row's created_at`), and a
    publish-failure counter feeding DLQ.
  - Every broker consumer: a DLQ counter on dead-letter, tagged by event type.
  - `Ago.Platform.Caching.Redis`: cache hit/miss counter tagged by key namespace (`caching.md`'s
    namespace list).
  - `Ago.Platform.Resilience`: breaker-state `ObservableGauge` (closed/open/half-open) and a
    bulkhead-rejection counter, both tagged by pipeline name — the hook this item's dependency on
    `6-01` exists for.
  - `Ago.Platform.Realtime`'s connection registry: a connections-per-node `ObservableGauge`.
  - `IOperatorCapacity`/the assignment loop: attempts-vs-conflicts counters.
- Every instrument named and tagged consistently, documented in one place (a metric-name table in the
  PR description, reviewer-facing) so `7-03`'s Grafana panels can be built without reading source first.

## Out of scope

- Traces — `7-01`, already landed by the time this item starts.
- Grafana panels and the Prometheus scrape config — `7-03`. This item's Done-when is provable against
  an in-memory metric reader, not a running Prometheus.
- Alerting rules — not asked for anywhere in `nfr.md` or `roadmap.md`; a demo cluster, not an on-call
  system. **True when written, superseded 2026-08-24**: `roadmap.md`'s Stage 15 asks for exactly this,
  and `15-03-alerting-and-notification.md` builds it on top of the instruments this item ships.
- Instrumenting `6-05`'s webhook dispatcher specifically — the generic pipeline-name-tagged instrument
  this item ships covers it automatically the moment `6-05` registers a `Webhooks` named pipeline; no
  extra work is needed here, and none should be added speculatively before `6-05` exists.

## Done when

- [x] Every metric in `nfr.md`'s Observability requirements section (RED per endpoint/hub/consumer;
      queue depth; channel occupancy; batch histogram; outbox lag; DLQ count; cache hit ratio; breaker
      state; connections per node; assignment attempts vs. conflicts) has a named instrument, listed in
      the PR description with its exact name and tags. 18 custom instruments, see `Shipped in` below.
- [x] Unit/integration tests proving at least one real value change per instrument (enqueue N messages
      and assert the channel-occupancy gauge moves; force a cache miss then a hit and assert the ratio
      counter moves; etc.) — not just "the instrument was registered." Every instrument has at least
      one test reading a real recorded value back via OTel's own in-memory exporter.
- [x] `CHANGELOG.md` entry and version bump in `ago-platform` — `[0.14.0]`.
- [x] `nfr.md`'s Observability requirements section gets a one-line pointer to where the metric
      catalogue is documented, so the doc does not go stale the moment a metric is renamed.

## Shipped in

`feat/7-02-metrics-instrumentation` (`ago-platform` `0.14.0` + `ago-chat`). Metrics fold into the same
`AddPlatformObservability` call `7-01` already wired per host (one `MeterProvider`, not a second method
to remember). `Ago.Platform.Resilience`'s per-pipeline breaker-state/bulkhead-rejection instruments
cover `6-05`'s `Webhooks` pipeline automatically, no per-consumer change needed — same "generic adapter
boundary" shape used for RabbitMQ's own per-consumer RED/DLQ counters. `Ago.Chat.Contracts.ChatMetrics`
mirrors `ChatTracing`'s placement exactly. Full metric-name/tag table lives in the PR description (both
repos) and in the source files themselves (`ChatMetrics`, `ResilienceMetrics`, `CachingMetrics`,
`RealtimeMetrics`, `RabbitMqMetrics`) — `7-03` gives it a Grafana home. Full test suites: `ago-platform`
76/76, `ago-chat` 385/385.

**Real gap found and fixed before merge, live while verifying `7-03`**: the first draft above wired
metrics through the same `AddOtlpExporter` push call tracing uses, pointed at the same
`Otel:Exporter:Endpoint` (Jaeger) — but Jaeger's OTLP receiver only implements the trace collector
service, and Prometheus's own model is pull/scrape, not push, so every metric silently went nowhere
either way. Fixed with `AddPrometheusExporter()` (`OpenTelemetry.Exporter.Prometheus.AspNetCore`,
pinned `1.18.0-beta.1` — this package has never shipped a stable release, tracking the SDK's own
1.18.0 line) plus one `app.MapPrometheusScrapingEndpoint()` line per host's own `Program.cs`. Verified
live after the fix: a running `Ago.Chat.Api`'s own `/metrics` returns real Prometheus-format output,
and Prometheus's targets page shows `ago-chat-api` `up` with real, non-empty metric data.

## Open questions

None.
