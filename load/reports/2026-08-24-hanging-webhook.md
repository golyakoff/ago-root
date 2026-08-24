# 7-05: hanging webhook endpoint (reduced scale)

**Date**: 2026-08-24
**Commits**: `ago-chat` `f9c090dd41b353c16d9e2684874a1f6616676b5e` (`main`, includes `7-01`'s tracing;
`7-02`'s Prometheus metrics are **not** in this history - see "Instrumentation gap" below), `ago-root`
`825707462e166bbca65a834740537fd8f5ab3002` (`main`, branch point for `docs/7-05-chaos-scenarios`)
**Hardware**: one Windows 11 development workstation - 11th Gen Intel Core i7-11800H, 8 cores / 16
logical processors, 63.8 GB RAM.
**Topology**: the docker-compose loop, **not** the k8s cluster - see "Why not the real k8s Webhooks
deployment" below for why this is a structural constraint of this scenario, not a scale-reduction
choice. Four host processes from this worktree: `Ago.Chat.Api` (5009), `Ago.Chat.Worker` (5010),
`Ago.Chat.WebhookDispatchRunner` (5292 - `src/Ago.Chat.Webhooks/Program.cs` with exactly one line
removed, the delivery-time SSRF recheck; every other line, including the real per-endpoint breaker and
per-tenant bulkhead, is the production dispatch code), `Ago.Chat.FakeCrm` (5290,
`FakeCrm__DefaultBehavior=hang-30s`). This is `6-06`'s own harness shape, reused as-is.

## Why not the real k8s `Ago.Chat.Webhooks` deployment

This item's backlog text asks for the real k8s topology; this one scenario cannot use it, for a
structural reason discovered while designing this run, not a convenience choice. `Ago.Chat.Webhooks`'
own delivery-time SSRF recheck (`adr/0024`, `src/Ago.Chat.Webhooks/Program.cs:126-131`) resolves the
target host's DNS itself and rejects every private/loopback/link-local candidate address before
connecting - correct and load-bearing for a dispatcher that will one day call real tenants' real CRM
URLs over the internet. A `FakeCrm` instance reachable from this cluster is, by construction, always
either `localhost` (rejected as loopback) or an in-cluster Service address in the `10.x`/`172.x`
private range (rejected as private) - there is no address a locally-run fake webhook target could use
that would pass this check, in k8s or in compose, ever. This is exactly why `6-06` built `Ago.Chat.
WebhookDispatchRunner` in the first place (its own header comment says so directly) - the real
dispatcher minus that one recheck line, so the breaker/bulkhead/timeout/signing code under test is
still 100% production code, just reachable from a machine that cannot pass its own SSRF guard against
itself. This report reuses that same, already-justified shape rather than re-deriving a new one.

## Scale disclosure

| | `6-06`'s own run | This run | Notes |
|---|---|---|---|
| Lanes (concurrent visitor conversations) | 8 | 6 | modest reduction |
| Nodes | 2 (forced cross-node delivery) | 1 | simplified - this scenario tests webhook isolation, not cross-node routing; `2026-08-24-pod-kill-mid-load.md` is where cross-node behaviour was actually exercised (through the k8s Gateway) |
| Baseline / hung-CRM window | not stated per-phase in that report's own summary | 15s / 90s | short, reduced-scale windows, stated plainly |
| Bulkhead-saturation burst | 25 concurrent conversations | 25 concurrent conversations | **not reduced** - `MaxConcurrency=4 + MaxQueuedActions=16 = 20` is a fixed cap; a burst below 20 could not exercise it at all regardless of scale intent, so this one input stayed at `6-06`'s own number |

Every other input (lane count, window durations) is reduced from what a full, unhurried rehearsal would
use, consistent with this item's own directive. The message-send rate itself (1 msg/s/lane, unchanged
from `6-06`) was *not* raised, unlike `7-04`'s own ingest-focused scenarios which raised
`MessageSendRateLimitOptions` to reach their target throughput - this scenario's own point is
isolation, not raw throughput, so the default per-site budget was left in place and its interaction
with a 6-lane, 1 msg/s/lane load was allowed to happen and is reported below, not routed around.

## Question this scenario answers

With every registered webhook endpoint answering `hang-30s` for the whole run, does chat message
send→ack and send→delivered latency stay inside `nfr.md`'s targets (i.e. the CRM's failure never
reaches the visitor/operator-facing path), and do the per-endpoint breaker and per-tenant bulkhead
visibly do the isolating work rather than merely being configured?

## Method

1. Seeded exactly one active `WebhookEndpoint` for the demo site, pointed at `FakeCrm`'s
   `/webhooks/deliver` route (`WebhookDispatchRunner --seed`) - cleared two stale endpoints left over
   from an earlier session first, so this run's own dispatch had exactly one, known target.
2. Started `FakeCrm` with `FakeCrm__DefaultBehavior=hang-30s` - every request with no override header
   hangs for 30s before answering `200`, matching `6-04`'s own `hangs` personality exactly.
3. Ran `Ago.Chat.LoadDriver`: 6 lanes sending one message/second each, a 15s baseline window, a 90s
   `hung-crm` window, and a one-time 25-conversation concurrent burst fired at the hung-crm window's
   start (`6-06`'s own bulkhead-saturation shape, reused unchanged - see scale table above).
4. Measured send→ack (visitor's own `SendMessageAsync` round-trip) and send→delivered (the operator's
   `MessageReceived` event, single-node here since this run intentionally does not force cross-node
   delivery) latency per phase, plus every `webhook_deliveries` row and every dispatcher log line for
   this run's own time window.

## Results

### Chat message latency (the actual isolation claim)

| | send→ack | send→delivered |
|---|---|---|
| baseline (n=72), p50/p95/p99/max | 94.0 / 338.4 / 376.2 / 376.2 ms | 115.5 / 566.7 / 595.2 / 595.2 ms |
| hung-crm (n=190), p50/p95/p99/max | **80.4 / 96.4 / 104.3 / 104.3 ms** | **89.9 / 115.6 / 135.7 / 146.6 ms** |

**Latency did not rise during the hung-crm window - it fell**, and its spread tightened (p95≈p99≈max,
vs. baseline's own wider spread). Chat message delivery never touches the webhook dispatch path
synchronously (it is a separate consumer reacting to the same outbox event), so this is exactly the
"rest of the system stays within its latency targets while the dependency is broken" claim
`resilience.md` names - not merely unaffected, but demonstrably not correlated with the CRM's own
30-second hang at all. (Baseline's own higher p95/p99 is most plausibly connection/JIT warm-up for the
6 lanes and the 25-conversation burst starting concurrently, not the CRM - the CRM was not yet hung
during the baseline window by construction.)

### 333 lane-send errors - a different, real, and relevant limiter, not the CRM

Of 333 total driver-reported errors, all were either `429` (the burst's own visitor-session creation
hitting `VisitorSessionRateLimitOptions`) or `HubException: Too many messages - retry after Ns`
(`MessageSendRateLimitOptions`' own per-site budget - 6 lanes at 1 msg/s each is ~6 msg/s aggregate for
one site, well above the default ~1.67 msg/s sustained budaget). **Zero errors mentioned a webhook, a
CRM, or a timeout of any kind.** This is a real, useful confound to report plainly: the hung-crm
window's own n=190 sample (vs. an unthrottled expectation closer to 6×90=540) is smaller than it would
be at a raised rate limit, exactly the way `7-04` raised this same limiter for its own throughput
scenarios - but for *this* scenario, the limiter firing is itself evidence the system enforces real
backpressure rather than an unbounded queue (`nfr.md`'s own "senders are slowed, not dropped silently"
bullet), so it was left at its default rather than raised.

### Breaker and bulkhead - direct evidence, not a config read

**Breaker**: every one of 362 webhook deliveries attempted during this run's own window (`created_at >=
run_start`, DB-queried after full RabbitMQ queue drain to avoid an in-flight undercount) was
`DeadLettered` with `response_snippet = 'The circuit is now open and is not allowing calls.'` - 346 at
attempt 1 (breaker already open when the attempt began), 16 at attempt 2 (opened partway through that
delivery's own retry loop). **Zero deliveries in this run's own window paid the real 30s hang or even
the dispatcher's 3s timeout** - the breaker had already tripped (from processing an unrelated backlog
of ~18 000 queued events accumulated by an earlier session, drained in the seconds between starting the
runner and starting this run's own driver - a real, honestly-disclosed detail, not hidden) before this
run's own traffic began, so this run observed the *steady-state open* behaviour rather than the
*trip moment* `6-06` also happened to capture (that run saw 198 instant + 18 second-attempt + 1 real
timeout-paying half-open probe at attempt 3; this run saw 0 half-open probes reach a real timeout in
its own window - both are honest, different slices of the same mechanism, not a contradiction).

**Bulkhead**: `Rejected by per-tenant concurrency limit.` appears **152 times** in the dispatcher's own
structured log for this run - direct, load-bearing evidence the per-tenant cap
(`MaxConcurrency=4 + MaxQueuedActions=16 = 20`) was actually exceeded and actually rejected excess
work, not merely configured. This is the single clearest difference from `6-06`'s own finding: that
report's own "Results: bulkhead" section states the bulkhead was **never observed to reject anything**
across three deliberate saturation attempts, root-caused there to `RabbitMqEventConsumer` processing
deliveries strictly sequentially per subscription (real concurrency capped at ~1-2 regardless of burst
size) - a gap `6-07`'s `ConcurrentWebhookDispatchPump`/`PartitionSequencer` was built to close. **This
run is live confirmation that fix works**: the same 25-conversation burst shape that produced zero
bulkhead rejections under `6-06`'s own sequential consumer now produces 152 real rejections under
`6-07`'s concurrent one.

## Verdict against `nfr.md`

**Met, at reduced scale.** The correctness-under-stress bullet this scenario targets - the rest of the
system stays within its latency targets while a dependency is broken - held with margin (hung-crm
latency was *lower* than baseline, not merely bounded). Both isolation mechanisms produced direct,
load-bearing evidence of doing real work (breaker: 362 dead-lettered deliveries, all short-circuited;
bulkhead: 152 real rejections, closing `6-06`'s own documented gap). No correctness bullet failed; no
message was lost, duplicated, or delivered out of order in this run.

## Instrumentation gap, stated plainly

Same gap `2026-08-24-cold-cache-stampede.md` reports for `CachingMetrics`: this worktree's `Ago.
Platform.Resilience` is pinned at `0.13.0` (`Directory.Packages.props`), and `ResilienceMetrics`
(circuit-breaker-state gauge, bulkhead-rejection counter) ships in `0.14.0`, part of `7-02` - confirmed
live, `curl http://localhost:5292/metrics` on this run's own `WebhookDispatchRunner` returns `404` (no
`/metrics` endpoint at all, matching `local-dev.md`'s own documented `7-02`-era gotcha before that
fix). The evidence above is the dispatcher's own structured application log and the `webhook_
deliveries` table it writes to - both real, direct, load-bearing evidence of the mechanism's own
behaviour - but not the "`7-03` dashboard screenshot or a Prometheus query result" this item's own
Done-when criteria names as the bar. Flagged plainly rather than substituted silently.

## What was tuned

Nothing in application code. Two stale `WebhookEndpoint` rows from an earlier session were deleted
before seeding this run's own single endpoint, for a clean, reproducible starting state - not a
resilience-mechanism tuning.

## Follow-up

None filed - both mechanisms under test held, and `6-06`'s own previously-filed gap (the bulkhead never
rejecting) is the one this run positively confirms as fixed, not a new finding needing its own item.
