# Stage 7 capstone: nfr.md, answered with numbers

**Date**: 2026-08-24
**Type**: synthesis, not a new measurement — this document runs no load test of its own. Every number
below is copied from one of the nine `load/reports/2026-08-24-*.md` files `7-04`/`7-05` produced and
cited by filename.
**This document's own base**: `ago-root` `521d750ec7b8c2eca75599810abfa7ddfbd49e05` (`main`, includes
`7-01`-`7-05` merged). Source reports were produced against `ago-chat` `f9c090dd41b353c16d9e2684874a
1f6616676b5e` (all nine) and `ago-root` `04ecf0e974c0f9e0f519fb8ded952e2db1885226` (`7-04`'s branch
point) / `825707462e166bbca65a834740537fd8f5ab3002` (`7-05`'s branch point).

## Read this before any number below

**Every one of the nine source reports measured at roughly 1-3% of `nfr.md`'s stated scale**, run
unsupervised overnight on one Windows 11 development workstation (11th Gen Intel Core i7-11800H, 8
cores/16 logical processors, 63.8 GB RAM), **not** the provisioned Kubernetes cluster `nfr.md` actually
targets (3 Api replicas, 2 Worker replicas). Six of the nine ran against the docker-compose loop, not
the cluster, for reasons stated in each report (a concurrent unrelated session already had the k8s
cluster and the default Api port in use). Only `cold-cache-stampede` ran against the real 3-replica k8s
cluster; `pod-kill-mid-load` did not run at all.

Every scale/latency table below carries a **Scale** column stating the real fraction measured. A
checkmark in these tables means "held at this reduced scale," never "meets `nfr.md` at full scale" —
extrapolating a
pass/fail verdict from ~1% scale to 100% scale is exactly what the `load-test` skill's percentile
discipline and every one of the nine source reports explicitly refuse to do, and this document refuses
it too. A reader who only reads this page, never the nine source reports, should come away with the
same picture as someone who read all nine: real pipeline code exercised, real numbers at small scale,
one real bug found, one real regression confirmed fixed, one scenario not run, and several gaps in the
evidence base named rather than smoothed over.

Tooling note that applies to every row below: none of the nine reports used k6 (uninstallable in every
unsupervised session that attempted it — the same constraint `6-06` already hit). All nine used
`Ago.Chat.LoadDriver`, a real `.NET SignalR client` extended across this batch, not a simulation of the
wire protocol.

---

## Scale targets

`nfr.md`'s own table: single local cluster, 3 Api replicas, 2 Worker replicas.

| Metric | `nfr.md` target | Measured | Scale | Source |
|---|---|---|---|---|
| Concurrent WebSocket connections | 20 000 total | 300/300 connected, 0 failures, 0 unexpected drops across a 90 s hold; ~37 KB/connection memory growth, no leak signature | **1.5%** | `2026-08-24-connection-storm.md` |
| Sustained message ingest | 3 000 msg/s | 35.4 msg/s achieved (~40 msg/s offered), zero errors across 10 672 sends, 240 s plateau | **~1.2%** | `2026-08-24-steady-ingest.md` |
| Peak burst ingest | 10 000 msg/s for 30 s | 93.6 msg/s achieved (~133 msg/s offered), 30 s burst window, zero errors across 3 609 sends | **~0.9%** | `2026-08-24-burst-ingest.md` |
| Attachment uploads | 50/s | 1.51 ops/s achieved (1.54/s offered), zero errors across 136 full presign+PUT+verify cycles | **~3%** | `2026-08-24-attachment-presign.md` |
| Conversations in the waiting queue | 10 000 | 150 created; **only 51/150 (34%) ever assigned within a 240 s window** — not a throughput ceiling, a real capacity-accounting bug (see "What regressed" below) | **1.5%** | `2026-08-24-assignment-contention.md` |

Every row: zero errors at the offered rate except the queue row, where the "error" is a real product
bug, not a scale artifact. None of these numbers say anything about whether the full target is
reachable — each source report says so explicitly and this synthesis repeats that rather than rounding
it away.

---

## Latency targets

`nfr.md`'s own table, p50/p95/p99, target vs. measured. **Bold** measured cells miss the corresponding
target; plain cells meet it. Every row is reduced-scale — see the Scale column.

### Send → ack (persisted) — target 15 / 50 / 150 ms

| Scenario | Phase | n | p50 | p95 | p99 | Scale | Source |
|---|---|---|---|---|---|---|---|
| steady-ingest | measured plateau | 8 493 | **119.6 ms** | **159.9 ms** | **187.2 ms** | ~1.2% | `2026-08-24-steady-ingest.md` |
| burst-ingest | baseline | 400 | **84.6 ms** | **101.6 ms** | 107.3 ms | ~0.9% (burst rate) | `2026-08-24-burst-ingest.md` |
| burst-ingest | burst | 2 809 | **100.5 ms** | **117.1 ms** | 133.5 ms | ~0.9% | `2026-08-24-burst-ingest.md` |
| burst-ingest | cooldown | 400 | **111.4 ms** | **145.1 ms** | 148.1 ms | ~0.9% | `2026-08-24-burst-ingest.md` |
| reconnect-storm | outside outage window | 3 460 | **129.6 ms** | **175.0 ms** | **240.7 ms** (max 4 195.9 ms) | ~0.67% (20 lanes) | `2026-08-24-reconnect-storm.md` |
| hanging-webhook | baseline | 72 | **94.0 ms** | **338.4 ms** | **376.2 ms** | ~0.2% (6 lanes) | `2026-08-24-hanging-webhook.md` |
| hanging-webhook | hung-crm window | 190 | **80.4 ms** | **96.4 ms** | 104.3 ms | ~0.2% | `2026-08-24-hanging-webhook.md` |

**Every p50 and every p95 misses at this scale, in every scenario, without exception.** p99 comes in
under the 150 ms target in three of seven rows (burst-ingest's burst and cooldown phases, and
hanging-webhook's hung-crm window) — low-concurrency dev-process latency has a tighter distribution
than the 3 000 msg/s target regime does, not evidence the target is close to being met.

### Send → delivered to a recipient on another node — target 40 / 120 / 300 ms

| Scenario | Phase | n | p50 | p95 | p99 | Scale | Source |
|---|---|---|---|---|---|---|---|
| steady-ingest | measured plateau (genuinely cross-node) | 8 505 | **211.7 ms** | **319.0 ms** | **387.4 ms** | ~1.2% | `2026-08-24-steady-ingest.md` |
| burst-ingest | baseline (cross-node) | 400 | **127.4 ms** | **189.8 ms** | 207.6 ms | ~0.9% | `2026-08-24-burst-ingest.md` |
| burst-ingest | burst (cross-node) | 2 699 | **566.9 ms** | **1 093.5 ms** | **1 161.2 ms** | ~0.9% | `2026-08-24-burst-ingest.md` |
| burst-ingest | cooldown (cross-node) | 510 | **271.3 ms** | **1 237.0 ms** | **1 270.0 ms** | ~0.9% | `2026-08-24-burst-ingest.md` |
| hanging-webhook | baseline — **single-node, not cross-node** | 72 | **115.5 ms** | **566.7 ms** | **595.2 ms** | ~0.2% | `2026-08-24-hanging-webhook.md` |
| hanging-webhook | hung-crm — **single-node, not cross-node** | 190 | **89.9 ms** | 115.6 ms | 135.7 ms | ~0.2% | `2026-08-24-hanging-webhook.md` |

The hanging-webhook rows are flagged single-node because that scenario deliberately did not force
cross-node delivery (it tests webhook isolation, not routing) — they are same-process delivery latency,
an easier path than the `nfr.md` row they are placed under, and are included only as the closest
available data point, not as a cross-node result.

**Misses at every percentile on every genuinely cross-node row.** The one real finding here (not just a
scale gap): burst-ingest's cross-node p50 rose ~4.4x from baseline to burst (127.4 → 566.9 ms) while
ack latency in the same burst rose only ~1.2x (84.6 → 100.5 ms) — the mismatch the `load-test` skill's
own Interpreting section calls the interesting result. `2026-08-24-burst-ingest.md` names the suspect:
`Ago.Chat.Worker`'s `OutboxDispatcher:PollInterval` (5 s in `appsettings.Development.json`) becoming a
real queueing point once ~4 000 outbox rows land in 30 s. **This is an architectural hypothesis from
client-side timing, not confirmed with a live outbox-lag or channel-occupancy metric** — no Prometheus
dashboard was reachable for this run's own non-default-port instances (see Observability gaps below).

### History page (50 messages, keyset) — target 5 / 20 / 60 ms

**Not measured by any of the nine scenarios.** No source report exercises the history-page read path at
all. This is a real gap in the evidence base, not a missed target — flagged as a candidate for a new
load scenario, not filled in here (out of scope for this synthesis to run anything new).

### Widget handshake (cache hit) — target 5 / 15 / 40 ms

| Scenario | Phase | n | p50 | p95 | max | Scale | Source |
|---|---|---|---|---|---|---|---|
| cold-cache-stampede | warm-cache baseline, `POST /api/v1/visitor-sessions` | 20 | 4.4 ms | **16.3 ms** | 16.3 ms | n/a (this is the reads-the-cache path, not a connection-count scale) | `2026-08-24-cold-cache-stampede.md` |

**Approximate proxy, not an exact match**: `nfr.md`'s "widget handshake" is not a named endpoint
anywhere in the nine reports; `POST /api/v1/visitor-sessions` is the call that reads the
`site-config:{publicKey}` cache key this scenario's own warm-cache baseline exercises, so it is the
closest real data point available, cited as such rather than silently presented as an exact match. p50
meets the 5 ms target (4.4 ms); p95 narrowly misses (16.3 ms vs. 15 ms). No p99 was reported for this
20-sample baseline (the rate limiter capped the sample before a clean p99 could be computed — see the
source report's own method section).

### Waiting → assigned, queue non-empty — target 100 ms / 500 ms / 2 s

| Scenario | n | p50 | p95 | p99 | Scale | Source |
|---|---|---|---|---|---|---|
| assignment-contention | 51 (of 150 created — see Scale targets above) | **2 492.5 ms** | **4 561.7 ms** | **4 802.2 ms** | 1.5% | `2026-08-24-assignment-contention.md` |

**Misses at every percentile**, expected at this scale (a 2 s poll-tick assignment job is itself a
meaningful fraction of the 100 ms p50 target). **Not the interesting result of this row**: 99/150 (66%)
never got assigned at all inside the 240 s window, for a reason unrelated to `nfr.md`'s scale target —
see "What regressed" below.

---

## Correctness under stress

`nfr.md`'s five bullets, binary per the source document's own framing.

| # | Bullet | Verdict | Evidence | Source |
|---|---|---|---|---|
| 1 | Zero acknowledged-but-lost messages while killing an Api pod and a Worker pod mid-load | **NOT RUN** | Every prerequisite verified live (cluster health, a 6-migration schema gap found and fixed, a Keycloak issuer gotcha worked around, WebSocket connectivity through the real Gateway proven for the first time) — but the one destructive step, `kubectl delete pod`, was denied twice by the session's own tool permission system before reaching the cluster. Not a missed/failed target — a scenario that never executed. | `2026-08-24-pod-kill-mid-load.md` |
| 2 | Zero out-of-order deliveries within a conversation, at any concurrency | **NOT MEASURED** | No source report asserts message ordering under concurrent senders explicitly; reconnect-storm's reconciliation checks presence/duplication of sequence numbers, not their delivery order. A real gap in the evidence base. | — |
| 3 | Zero duplicate persisted messages despite at-least-once delivery and client retries | **PASS, reduced scale** | 20/20 lanes, 173 acknowledged messages, each present exactly once — no gap, no duplicate — through a real process kill-and-restart. Not a test that forces client retries specifically; the check is a reconciliation against sequence numbers, at 20 lanes / 173 messages, single-instance restart (not a k8s rolling restart across 3 replicas). | `2026-08-24-reconnect-storm.md` |
| 4 | Zero operators above their configured capacity, at any assignment contention | **PASS, reduced scale** | `operators.active_chats` never exceeded `capacity` in the run; the compare-and-set (`WHERE active_chats < capacity`) held throughout, confirmed directly against Postgres. (A separate, real bug in the *release* half of capacity accounting was found in the same run — see "What regressed" — but it is not a capacity-exceeded failure.) | `2026-08-24-assignment-contention.md` |
| 5 | Zero unbounded queues: memory stays flat under sustained overload; senders slowed, not dropped silently | **PASS, reduced scale** | Connection-storm: ~37 KB/connection growth, flat (not climbing) across a 90 s hold, no leak signature. Burst-ingest: zero errors across a ~10x offered-rate jump — the pipeline slowed acks rather than dropping sends. Hanging-webhook: 333 rate-limiter-driven `429`/`HubException` errors during the burst window are cited as evidence of enforced backpressure, not silent drops — "senders are slowed" via a real limiter, not an unbounded queue. | `2026-08-24-connection-storm.md`, `2026-08-24-burst-ingest.md`, `2026-08-24-hanging-webhook.md` |

**1 of 5 bullets not run at all; 1 of 5 not measured by any scenario; 3 of 5 pass at reduced scale.**
None of the three passes were scale-tested anywhere near `nfr.md`'s own concurrency — "pass" here means
"held in the regime actually tested," stated per the constraint at the top of this document.

---

## Resource budgets

`nfr.md`: Api pod 512 MB / 0.5 CPU at target load; Worker pod 512 MB / 1 CPU; Postgres connections
pooled with a tested exhaustion path.

| Process | Working set observed | Threads/handles | Source |
|---|---|---|---|
| Visitor-node Api, mid steady-ingest run | 239 MB | not sampled | `2026-08-24-steady-ingest.md` |
| Operator-node Api, mid steady-ingest run | 157 MB | not sampled | `2026-08-24-steady-ingest.md` |
| Worker, mid steady-ingest run | 209 MB | not sampled | `2026-08-24-steady-ingest.md` |
| Visitor-node Api, connection-storm pre-ramp baseline | 306.5 MB | 84 threads, 995 handles | `2026-08-24-connection-storm.md` |
| Visitor-node Api, connection-storm, 300 connections settled | 316.6-317.9 MB | 42-55 threads, 1 061-1 296 handles | `2026-08-24-connection-storm.md` |
| Worker / operator-node Api, connection-storm (untouched control) | 180.0-190.4 MB / 184.3-184.4 MB | flat throughout | `2026-08-24-connection-storm.md` |
| Visitor-node Api, post burst-ingest (spot check) | ~250-310 MB across session, no elevation vs. steady-ingest | not sampled | `2026-08-24-burst-ingest.md` |

Every sampled number stays under the 512 MB budget, and connection-storm's own repeated 5 s samples
show no growth during a 90 s idle hold (no leak signature at this scale). Three real caveats, stated
plainly rather than rounded into a pass:

- **These are Windows dev-process working-set numbers** (`resource-monitor.ps1`, `Get-Process`-based,
  `6-06`'s own tool reused unmodified), not a pod's cgroup memory usage on the provisioned cluster —
  a different measurement mechanism than `nfr.md`'s own budget, at a process running one un-replicated
  `dotnet run` instance rather than a resource-limited container.
- **CPU was never measured in any of the nine reports.** `resource-monitor.ps1` samples working set,
  thread count, and handle count — no CPU percentage appears anywhere in the raw data or any report.
  `nfr.md`'s 0.5/1.0 CPU budgets are unaddressed by this evidence base entirely.
- **The Postgres connection-pool exhaustion path (queue and time out cleanly, not deadlock) was not
  tested by any of the nine scenarios.** No report drives concurrent load past pool capacity or
  observes pool-wait behaviour.

---

## Availability behaviour

`nfr.md` asks what `7-05` actually observed, not what `realtime.md` predicted in advance. Only two of
the three planned failure-injection scenarios ran, and only one of those two ran against the real
cluster.

**Webhook/CRM dependency hanging** (`2026-08-24-hanging-webhook.md`, compose loop, not k8s — see that
report's own "Why not the real k8s Webhooks deployment" for the structural SSRF-recheck reason): the
chat message path stayed completely unaffected while every registered webhook target hung 30 s on every
call for a 90 s window — hung-crm-window latency was *lower* than baseline, not merely bounded. The
breaker dead-lettered all 362 webhook deliveries attempted in-window without a single one paying the
real hang; the per-tenant bulkhead rejected 152 excess deliveries with `Rejected by per-tenant
concurrency limit.` in the dispatcher's own log. This is a real "degrades without touching the rest of
the system" result, at reduced scale (6 lanes vs. `6-06`'s own 8, single-node not cross-node).

**Redis cold-cache flush** (`2026-08-24-cold-cache-stampede.md`, the real 3-replica k8s cluster through
the actual Gateway — the one scenario that ran at the intended topology): flushing the `site-config:*`
cache namespace and firing 15 concurrent requests across 3 replicas did not turn into 15 database reads
in any of 3 repeated runs (`seq_scan` rose by 1, 3, and 1) — the in-process single-flight held every
time. The cross-node lock that is supposed to collapse the herd *across* replicas, not just within one,
held cleanly in 2 of 3 runs (collapsing to exactly 1 DB read) but only partially in the third (3 reads,
with request latency on the losing replicas spiking to ~150x the warm baseline, up to 2.45 s — well past
the documented 500 ms poll-and-fallback budget). `caching.md` documents this exact mechanism as
best-effort, not a guarantee, and this run's own 1-of-3 partial-collapse result is that documented
behaviour observed live, not a failure of anything — but it is a real, reproducible minority-case
finding, not a clean pass.

**Api/Worker pod death** — `nfr.md`'s and `realtime.md`'s central availability claim — **was not
observed at the real cluster at all.** `pod-kill-mid-load` did not run (see Correctness under stress
above). The closest available evidence is `reconnect-storm`'s single-instance-restart analog (not a
k8s pod kill, not a rolling restart across replicas): 20/20 client lanes recovered automatically within
a ~2.53 s outage window via SignalR's own automatic reconnect, with zero acknowledged-but-lost messages.
That report's own Interpretation section is explicit that this says nothing about the *shape* of a real
rolling restart (which, by design, should never take a whole node offline the way a single-process kill
necessarily does) — only that the resume protocol recovers correctly when tested this way.

Net: one of `realtime.md`'s three degradation paths (webhook/CRM) is directly confirmed at reduced
scale; one (Redis cache) is confirmed at real topology but reduced concurrency, with an honest partial
failure noted; the third and most central (Api/Worker pod death) has no direct evidence at all — only
an adjacent, structurally different single-instance-restart proxy.

---

## Observability requirements — what this report's own evidence base is missing

`nfr.md` asks for RED metrics, queue depth/channel occupancy, batch histograms, outbox lag, DLQ count,
cache hit ratio, breaker state, and connection/assignment counts — all visible without a debugger, per
`7-02`'s instrumentation. This capstone's own evidence base falls short of that bar in two concrete,
named ways:

- **`Ago.Platform.Caching.Redis.CachingMetrics` and `Ago.Platform.Resilience.ResilienceMetrics`
  (`0.14.0`, part of `7-02`) are not present** in the `0.13.0`-pinned dependency this batch's worktree
  used, confirmed live by both `cold-cache-stampede` (`ago_platform_caching_redis_cache_access` returns
  no series on the real cluster's own Prometheus) and `hanging-webhook` (`curl .../metrics` on the
  dispatcher returns `404`). Evidence for those two scenarios came from direct Postgres queries
  (`pg_stat_user_tables.seq_scan`) and the dispatcher's own structured application log plus the
  `webhook_deliveries` table — real, direct evidence of the mechanisms' own behaviour, but not the
  dashboard/query bar `nfr.md`'s own Observability section names.
- **No live Prometheus/Grafana dashboard was reachable at all for any of `7-04`'s six scenarios.** The
  compose loop's Prometheus is pre-configured to scrape only the default port (`5009`), and this
  batch's own Api instances ran on non-default ports (`5109`/`5110`) to avoid colliding with a
  concurrent unrelated session. This is why burst-ingest's own outbox-lag finding (above) is an
  inference from architecture and client-side timing, not a captured channel-occupancy or outbox-lag
  number — a real, stated limitation of this specific batch's evidence, not a silently worked-around
  gap.

Tracing (`7-01`) and the k8s cluster's own breaker-state gauge (confirmed live and scraping during
`pod-kill-mid-load`'s prep work, per that report) are the two pieces of `7-02`/`7-03`'s instrumentation
this batch actually had working end to end; the rest of the catalogue remains unverified against a live
dashboard by this specific set of nine reports.

---

## What was tuned

Aggregated across all nine reports — every config knob any of them changed, in one place:

- **`MessageSendRateLimitOptions`** (`PerSiteCapacity=5000`, `PerSiteRefillPerSecond=200`) and
  **`VisitorSessionRateLimitOptions`** (`PerSiteCapacity=2000`, `PerSiteRefillPerSecond=100`) — raised
  via process environment variables, session-only, never committed to `appsettings*.json`. Without
  this, the default per-site abuse-prevention budget (~1.67 msg/s sustained) would have been the
  measured bottleneck instead of the message pipeline. Used by `steady-ingest`, `burst-ingest`, and
  (session carried over) `connection-storm`.
- **`AttachmentRateLimitOptions`** (`PerVisitorCapacity=1000`/`PerVisitorRefillPerSecond=50`,
  `PerOperatorCapacity=1000`/`50`, `PerSiteCapacity=1000`/`50`) — same reasoning, same mechanism, raised
  for `attachment-presign` only; the default `PerVisitorCapacity=5` produced an immediate `429` after
  the first burst of 5 calls.
- **A fixed, throwaway `Auth__SigningKey`** shared across both Api instances for the session — not a
  tuning change to the system under test, but a test-harness necessity so a visitor token minted on one
  node stays valid on the other (cross-node delivery) and stays valid across a process restart
  (`reconnect-storm`). Used by `steady-ingest`, `burst-ingest`, `connection-storm`, `reconnect-storm`,
  `assignment-contention`.
- **Direct database reset** (`DELETE FROM messages/conversations WHERE state='Waiting'`,
  `UPDATE operators SET active_chats = 0`) immediately before `assignment-contention`, to get a clean
  baseline on a Postgres instance shared with a concurrent unrelated session. Not a tuning change to
  the system — a starting-state reset, and the reason it was needed at all is that scenario's own
  headline finding (capacity never releasing on ordinary close).
- **Rate limits deliberately left at default in `hanging-webhook`**: unlike every ingest-throughput
  scenario, this scenario's own point is isolation, not raw throughput, so `MessageSendRateLimitOptions`
  stayed at its default and its 333 resulting `429`/`HubException` errors are reported as evidence of
  real backpressure, not routed around.

**No `concurrency.md`-named pipeline knob — batch size, channel capacity, pipeline worker count, or
`OutboxDispatcher:PollInterval` — was changed in any of the nine reports.** Every latency and throughput
number in this document reflects the pipeline's default configuration; the only tuning that happened
anywhere in this batch was raising abuse-prevention rate limiters so the pipeline itself, rather than a
per-tenant limiter, would be the thing actually measured. At none of these reduced scales did any
scenario get close enough to default pipeline capacity to make a pipeline-level tuning decision
meaningful.

---

## What regressed or fell short

Every missed target and every real finding, named, with a suspect and a linked follow-up where one
exists.

1. **Steady-ingest and burst-ingest latency miss every p50/p95 target, and most p99 targets, at
   ~1%/~0.9% scale.** Suspect: regime mismatch, not a bug — a single unbatched `dotnet run` process pair
   at ~1% of offered load never exercises the batch writer or connection pool the way 3 000 msg/s would;
   both reports show no latency drift across their own measured plateau, i.e. no queueing signature
   within the window actually tested. No follow-up item — the fix is a full-scale rerun on the
   provisioned cluster, not a code change.
2. **Burst-ingest cross-node delivery latency rises ~4.4x p50 (and worse at p95/p99) during a 10x
   offered-rate burst, staying elevated into the cooldown window.** Suspect, named per the `load-test`
   skill's own diagnostic rule: `Ago.Chat.Worker`'s 5 s `OutboxDispatcher:PollInterval` becoming a
   real queueing point under a burst of outbox rows. **Not confirmed with a live outbox-lag or
   channel-occupancy metric** — inferred from architecture and client-side timing only, because no
   Prometheus dashboard was reachable for this run's own instances (see Observability gaps above). No
   backlog item filed yet; `2026-08-24-burst-ingest.md`'s own "what a real run still needs" section
   names the fix: a working live dashboard scraping the actual instances under test, at the next
   full-scale attempt.
3. **Assignment-contention: 99/150 (66%) of conversations never got assigned within a 240 s window.**
   Root cause, confirmed directly against the running system: `CloseConversationHandler` never calls
   `IOperatorCapacity.ReleaseAsync` — `active_chats` only ever decrements via the bulk
   operator-disconnect sweep, never on an ordinary conversation close, so capacity ratchets down to zero
   under any normal "close one, move to the next" traffic pattern. **Filed as `6-09` ("Release operator
   capacity on conversation close, not only on operator disconnect")** — confirmed by re-reading
   `docs/backlog/6-09-release-operator-capacity-on-close.md` on `main` as part of writing this synthesis:
   **`Status: ready`, Done-when boxes unchecked — not yet merged.** The assignment-contention scenario
   has not been re-run since, and won't confirm the fix until `6-09` lands and that item's own Done-when
   (a re-run showing the queue draining past its first capacity's worth) is satisfied.
4. **`pod-kill-mid-load` did not run.** Not a missed target — a tool permission denial on the one
   destructive command (`kubectl delete pod`) after every prerequisite was verified and prepared live.
   No suspect to name because no code path was exercised. `2026-08-24-pod-kill-mid-load.md` states
   exactly what a supervised rerun needs: two commands and the already-prepared driver, nothing else
   blocking.
5. **History page (keyset) latency and out-of-order-delivery correctness are not measured by any of the
   nine scenarios.** Real gaps in the evidence base, not misses — no scenario currently exercises either
   path. Candidate follow-up: a load scenario is missing for both; not run ad hoc here per this item's
   own out-of-scope note.
6. **CPU usage (Api 0.5, Worker 1.0 target) and the Postgres pool-exhaustion path are not measured by
   any of the nine scenarios.** `resource-monitor.ps1` captures working set/threads/handles only. A real
   gap, not a missed number.
7. **Cold-cache-stampede's cross-node lock partially failed in 1 of 3 runs** (3 `seq_scan` instead of
   the theoretical minimum of 1, with request latency on the losing replicas up to ~2.45 s — past the
   documented 500 ms poll-and-fallback budget). Not a bug — `caching.md` documents the cross-node lock
   as best-effort — but a real, reproducible minority-case result worth a larger-N rerun once `nfr.md`'s
   full 1 000-reader scale is actually attempted, to see whether the ~33% partial-collapse rate observed
   here holds, worsens, or was a one-off environmental artifact. Not filed as a numbered item (that
   report's own words: "a measurement to redo at real scale," not a fix).

**One real regression positively confirmed fixed, for balance**: `hanging-webhook`'s bulkhead result is
a genuine positive, not just a checkbox. `6-06` found the per-tenant bulkhead never rejecting anything
across three deliberate saturation attempts, root-caused to `RabbitMqEventConsumer` processing
deliveries strictly sequentially (real concurrency capped at ~1-2 regardless of burst size) — a gap
`6-07`'s `ConcurrentWebhookDispatchPump`/`PartitionSequencer` was built to close. This batch's own
`hanging-webhook` report re-ran the identical 25-conversation saturation burst and got 152 real
`Rejected by per-tenant concurrency limit.` rejections — live confirmation `6-07`'s fix works, not an
assertion.

---

## Summary

Nine scenarios ran (six `7-04`, three `7-05`); one of the nine (`pod-kill-mid-load`) did not execute at
all. Every scenario that did run stayed inside its stated, honestly-labeled 1-3% scale envelope, with
zero errors at the offered rate except where a real product bug (assignment capacity, `6-09`) capped
throughput below what the offered load could otherwise reach. Of `nfr.md`'s five correctness bullets:
one was not run, one was not measured by any scenario, three passed at the reduced scale actually
tested. Of `nfr.md`'s five latency-target rows, one (history page) has no data at all; every other row misses
at p50/p95 in every scenario, with p99 occasionally meeting target at low concurrency — never
interpreted here as evidence the full-scale target is close. One real regression (bulkhead) was
confirmed fixed; one real bug (capacity release) was found, root-caused, and filed as `6-09`, still
open as of this report. The instrumentation this report needed most — live dashboards for the
non-default-port compose instances, and the `0.14.0` caching/resilience metrics on the images actually
under test — was not available for roughly two-thirds of the nine runs, named as a real, current
limitation rather than substituted silently.

**What a full-scale run still needs**, aggregated from all nine reports: the provisioned `k8s-local.md`
cluster with nobody else using it concurrently, a load generator proven not to be its own bottleneck at
`nfr.md`'s real numbers (k6 remained uninstallable in every unsupervised session that tried), `6-09`
merged before `assignment-contention` is re-run (otherwise the queue will hit the identical capacity
ceiling regardless of scale), working Prometheus scrape targets for whatever ports the real instances
use, and a second, supervised attempt at `pod-kill-mid-load` — the two commands and prepared driver
`2026-08-24-pod-kill-mid-load.md` already describes.
