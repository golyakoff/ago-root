# 7-04: steady ingest (reduced scale)

**Date**: 2026-08-24
**Commits**: `ago-chat` `f9c090dd41b353c16d9e2684874a1f6616676b5e` (`main`, includes `7-01`'s tracing and
this item's own `Ago.Chat.LoadDriver` scenario extension), `ago-root` `04ecf0e974c0f9e0f519fb8ded952e2db1885226`
(`main`, branch point for `docs/7-04-load-scenarios`)
**Hardware**: one Windows 11 development workstation - 11th Gen Intel Core i7-11800H, 8 cores / 16
logical processors, 63.8 GB RAM. **Not** the provisioned cluster `nfr.md` targets.

## Scale disclosure - read this before the numbers below

**This run is deliberately, explicitly NOT `nfr.md`'s own target.** The author decided, after being
asked, to run `7-04`'s six scenarios at a reduced scale overnight on their own development machine
rather than attempt `nfr.md`'s full numbers unsupervised - the same choice already made once for
`6-06` (`load/reports/2026-08-23-webhooks-load-proof.md`) and its own precedent this run follows.

| | `nfr.md` target | This run | Scale factor |
|---|---|---|---|
| Sustained message ingest | 3 000 msg/s | ~35 msg/s achieved (40 msg/s offered) | **~1.2%** |

This report proves the *scenario design and reporting method* work and produces one real, honestly
labeled measurement at this reduced scale. **It does not claim, and must not be read as implying,
that `nfr.md`'s 3 000 msg/s target would be met, or even approximately approached, at 100% scale.**
Extrapolating a pass/fail verdict from 1.2% scale to 100% scale is not something this run can
honestly do - the batch writer, connection pool, and channel behaviour that matter at 3 000 msg/s
are qualitatively different regimes this run never touches. What a real, full-scale run needs: the
provisioned `k8s-local.md` cluster (3 Api replicas, 2 Worker replicas, per `nfr.md`'s own stated
topology), k6 (or an equivalent generator proven not to be its own bottleneck) driving ~3 000
concurrent send loops, and the same percentile/warm-up discipline this report already follows.

## Topology and tooling deviations, stated plainly

- **Compose loop, not the k8s cluster.** `7-04`'s own backlog text prefers the k8s 3-replica topology
  for the real run; this run deliberately used `docker-compose`'s already-running infra (Postgres,
  RabbitMQ, Redis, MinIO, Keycloak) instead, for two reasons: the reduced-scale nature of this run
  makes the compose loop the honest, lower-overhead choice (matching `6-06`'s own precedent), and a
  k8s cluster was *already running concurrently on this machine* for an unrelated session (`7-02`,
  visible as `k8s_api`/`k8s_worker` pods) - reusing or restarting it was out of scope and risked that
  other session's work.
- **A second, live concurrent session was already running `Ago.Chat.Api` on this same machine**, from
  a different worktree (`ago-chat-7-02`), bound to the default port `5009`. This run's own two `Api`
  instances were deliberately placed on non-default ports (`5109` operator-node, `5110` visitor-node)
  and never touched that other process. One consequence: this compose loop's own Prometheus is
  pre-configured (`ago-deploy/docker/prometheus.yml`) to scrape only the default port `5009` - **not**
  this run's own instances - so no live Prometheus/Grafana dashboard was available for this run's own
  traffic (see "Server-side observations" below for what was used instead). Editing that shared
  scrape config while another session might depend on it was out of scope.
- **Real `.NET SignalR client` (`Ago.Chat.LoadDriver`), not k6** - the same deviation `6-06` already
  made and stated: k6 was not installed and installing new external tooling in an unsupervised
  background session is not this session's call to make; hand-rolling SignalR's own wire framing in
  k6 would measure a reimplementation, not the real system. This item extended `Ago.Chat.LoadDriver`
  (`ago-chat`, `tests/Ago.Chat.LoadDriver/Program.cs`) with a `LOADDRIVER_SCENARIO` dispatch covering
  all six of this item's scenarios, keeping `6-06`'s own original scenario reproducible under
  `LOADDRIVER_SCENARIO=webhook-isolation`.
- **Rate limiters raised via environment variables for the duration of this session, not code
  changes.** `MessageSendRateLimitOptions`' default per-site budget (100/min ≈ 1.67 msg/s sustained)
  and `VisitorSessionRateLimitOptions`' default (20/min) describe one tenant's abuse-prevention
  budget, not the platform-aggregate ingest capacity `nfr.md`'s target is actually about - at any
  scale above roughly 1.67 msg/s, the *default* per-site limiter, not the message pipeline, becomes
  the bottleneck being measured. `MessageSendRateLimit__PerSiteCapacity=5000`,
  `MessageSendRateLimit__PerSiteRefillPerSecond=200`, `VisitorSessionRateLimit__PerSiteCapacity=2000`,
  `VisitorSessionRateLimit__PerSiteRefillPerSecond=100` were set on both `Api` instances for this
  session only (process environment variables, never committed to any `appsettings*.json`). Default
  production values are unchanged by this run.
- Both `Api` instances share one fixed `Auth__SigningKey` (a throwaway local value, generated for this
  session, never a real secret) so a visitor token minted on one instance is valid on the other,
  matching `local-dev.md`'s own proven approach for genuine cross-node testing.
- **Two `Api` instances, one `Worker` instance**: operator connects to the "operator node" (`5109`),
  visitors connect to the "visitor node" (`5110`) - every message in this scenario therefore crosses
  nodes through the Redis-backed connection registry for the "delivered" measurement, matching
  `nfr.md`'s "delivered to a recipient on another node" row, not two copies of one process.

## What this scenario answers

Does the message-send pipeline (hub -> handler -> batch writer -> Postgres, plus the outbox ->
RabbitMQ -> fan-out -> cross-node delivery path) sustain a steady offered rate without the ack or
cross-node delivery latency drifting upward over a real plateau (not a warm-up blip)?

## Load shape

40 lanes (one visitor WebSocket connection each, manually assigned to the one seeded demo operator via
`OperatorHub.JoinConversationAsync` so every message crosses nodes deterministically), each sending one
message per second - offered aggregate ~40 msg/s. 60 s warm-up (discarded from every stat below, per
the `load-test` skill's own rule), then a 240 s (4 minute) measured plateau - long enough for the
.NET JIT, connection pools, and GC to reach steady state, not a 30 s blip. Total wall clock 300 s.

## Results

Source: `tests/Ago.Chat.LoadDriver/Program.cs` `RunSteadyIngestAsync`, this branch (`ago-chat`). Raw
per-message CSV: `load/output/raw/steady-ingest.csv` (gitignored, not committed - the percentiles
below are computed from it and are the actual reported numbers).

| Path | Phase | n | p50 | p95 | p99 | max |
|---|---|---|---|---|---|---|
| Send -> ack (persisted) | warm-up (discarded) | 2 179 | 95.9 ms | 106.6 ms | 112.7 ms | 123.3 ms |
| Send -> ack (persisted) | **measured** | **8 493** | **119.6 ms** | **159.9 ms** | **187.2 ms** | 247.3 ms |
| Send -> delivered, cross-node | warm-up (discarded) | 2 167 | 163.0 ms | 231.9 ms | 264.8 ms | 300.1 ms |
| Send -> delivered, cross-node | **measured** | **8 505** | **211.7 ms** | **319.0 ms** | **387.4 ms** | 499.3 ms |

**Throughput**: 8 493 acked sends over the 240 s measured window = **35.4 msg/s** actual, against
~40 msg/s offered (the ~11% shortfall is each lane's own `InvokeAsync` round trip - ~120 ms measured -
eating into its 1000 ms nominal interval, not a server-side limiter or rejection: **zero errors** across
10 672 total sends).

## Server-side observations

No live Prometheus/Grafana dashboard for this run's own instances (see "Topology deviations" above -
the compose Prometheus scrapes only the unrelated default-port instance). Process-level resource
sampling was not run continuously for this specific scenario (reserved for the connection-storm
scenario, where `nfr.md` explicitly ties the target to memory/GC pressure); a spot check partway
through the measured window showed the visitor-node `Api` process at 239 MB working set, the
operator-node at 157 MB, and `Worker` at 209 MB - all well under `nfr.md`'s 512 MB/pod budget (not a
claim that budget is met at cluster scale, just that nothing looked abnormal on this dev-loop process).

## Interpretation

Against `nfr.md`'s own latency targets (send -> ack: 15/50/150 ms; send -> delivered cross-node:
40/120/300 ms, p50/p95/p99): this reduced-scale, single-unbatched-process run **misses every p50 and
p95 target on both paths**, and misses p99 too (187 ms vs 150 ms; 387 ms vs 300 ms) - expected and
stated up front, not a surprise. `nfr.md`'s numbers describe a 3-replica, resource-limited cluster
under a genuine 3 000 msg/s load; this is one `dotnet run`-launched process pair on a laptop at ~1% of
that offered rate, with none of the batching pressure that makes the batch writer's own multi-row
insert pay for itself. **This report does not claim `nfr.md`'s latency targets are met, nor that they
would be met at full scale** - only that the pipeline sustained a real, measured 35.4 msg/s for four
minutes with zero errors and no visible latency drift within the measured window (p50/p95/p99 stayed
essentially flat across the 240 s plateau; not separately tabulated here since the CSV's own
per-message timestamps are the source if that curve is wanted later).

## What was tuned

`MessageSendRateLimit`/`VisitorSessionRateLimit` per-site budgets raised via environment variables for
this session only (see "Topology deviations" above) - without this, the default 1.67 msg/s per-site
sustained cap would have been the measured bottleneck, not the message pipeline. No pipeline
batch-size, channel-capacity, or worker-count knob (`concurrency.md`'s own named tuning knobs) was
changed - default configuration throughout.

## What a real, full-scale run still needs

The provisioned `k8s-local.md` cluster (3 Api replicas, 2 Worker replicas), k6 or an equivalent
generator distributed across enough client processes/machines that the generator itself is not the
bottleneck (`load-test` skill's own warning), ~3 000 concurrent send loops, and the same
warm-up-discarded, percentile-not-average discipline this report already follows. This run's own
35.4 msg/s number says nothing, directly, about whether 3 000 msg/s is reachable - it only proves the
scenario and reporting method are sound and gives one honest, small-scale data point.
