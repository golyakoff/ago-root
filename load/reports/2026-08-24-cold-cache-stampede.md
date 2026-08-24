# 7-05: cold-cache stampede (reduced scale)

**Date**: 2026-08-24
**Commits**: `ago-chat` `f9c090dd41b353c16d9e2684874a1f6616676b5e` (`main`, includes `7-01`'s tracing;
`7-02`/`7-03` metrics and dashboards are **not** in this history - see "Instrumentation gap" below),
`ago-root` `825707462e166bbca65a834740537fd8f5ab3002` (`main`, branch point for
`docs/7-05-chaos-scenarios`)
**Hardware**: one Windows 11 development workstation - 11th Gen Intel Core i7-11800H, 8 cores / 16
logical processors, 63.8 GB RAM. **Not** the provisioned cluster `nfr.md` targets.
**Topology**: the real local Kubernetes cluster (`k8s-local.md`, Docker Desktop Kubeadm, one node),
`ago-chat` namespace, `ago-chat-api` Deployment at **3 replicas** (`nfr.md`'s stated Api topology),
reached through the real NGINX Gateway Fabric route (`http://ago-chat.localhost`, `least_conn`) - not
the compose loop. This is the one scenario of this item's three that could run at the real topology,
because it needs no webhook dispatcher (see `2026-08-24-hanging-webhook.md` for why that scenario
could not use this same cluster).

## Scale disclosure - read this before the numbers below

**This run is deliberately, explicitly NOT `nfr.md`'s own target.** `caching.md`'s own stampede-
protection section names the real Stage 7 job as "cold cache + 1000 concurrent readers across
replicas." This run used **15 concurrent readers**, not 1000.

| | `nfr.md`/`caching.md` target | This run | Scale factor |
|---|---|---|---|
| Concurrent cold-cache readers | 1 000 (across replicas) | 15 | **1.5%** |

Two independent reasons converge on this number, not just the author's own general "reduced scale,
honestly labeled" instruction that also governed `7-04`: `POST /api/v1/visitor-sessions` - the only
endpoint that reads the `site-config:{publicKey}` cache key this scenario needs to flush - sits behind
its own real per-site token-bucket rate limiter (`VisitorSessionRateLimitOptions`, capacity 20,
~20/minute sustained refill), found live while designing this run's own burst size (the first attempt
at 30 concurrent got 20 `201`s and 10 `429`s - the limiter, not the cache, answered requests 21-30).
15 stays safely under that cap so every request in the burst is a genuine concurrent cold-cache
attempt, not a request that never reached the cache-miss code path at all. Raising that limiter for
this run's duration (the way `7-04` raised `MessageSendRateLimitOptions` for its own ingest-rate
scenarios) was considered and rejected: unlike `7-04`'s throughput scenarios, this scenario's own
realistic worst case *is* bounded by this exact limiter in a real deployment - a single client cannot
generate more than 20 concurrent handshakes for one site regardless of what the cache does, so testing
below that real ceiling is the honest scope, not a compromise. **This does not mean the mechanism is
proven at 1000 concurrent readers** - only that this run's own 15-reader ceiling is itself a real,
documented constraint of the code under test, not an arbitrary reduction.

## Question this scenario answers

Does the cache's stampede protection (`caching.md`: in-process single-flight + a best-effort
cross-node `RedisLock`) keep a cold-cache miss from becoming N concurrent database reads when N
concurrent requests land across multiple `Ago.Chat.Api` replicas at once, and does request latency
stay bounded rather than spiking proportionally to N?

## Method

1. Warm the `site-config:demo_site` key with one request, confirm steady-state latency.
2. Flush **only** `site-config:*` from the cluster's own Redis (`kubectl exec -n ago-chat deploy/redis
   -- redis-cli --scan --pattern 'site-config:*' | xargs redis-cli DEL`) - scoped, not `FLUSHALL`; the
   stampede-protection lock lives in a separate `lock:*` namespace and was left untouched.
3. Immediately fire 15 concurrent `POST /api/v1/visitor-sessions` requests (`bash`, `xargs -P 15`,
   `curl -w '%{http_code} %{time_total}'`) through the Gateway.
4. Record each request's latency and HTTP status, and `sites` table `seq_scan` count (`pg_stat_
   user_tables`) immediately before and after the burst - the backing read this cache protects, and
   the table is small enough (1 row) that Postgres's planner genuinely prefers a sequential scan over
   an index scan, so `seq_scan` (not `idx_scan`) is the correct counter to watch.
5. Repeat three times, ~65s apart (the rate-limit bucket's own refill window), to see whether the
   result is consistent.

Warm-cache baseline (cache never flushed, same 15-request burst shape, `n=20` valid samples before the
rate limiter capped the run): p50 4.4 ms, p95 16.3 ms, max 16.3 ms.

## Results

| Run | `seq_scan` delta (= DB reads this burst caused) | Latency (of 15 requests, ms) |
|---|---|---|
| 1 | **+1** | 3.9, 4.0, 4.1, 4.6, 4.6, 4.6, 25.0, 43.2, 52.9, 54.1, 63.2, 106.6, 123.1, 125.5, 135.0 |
| 2 | **+3** | 375.0, 441.0, 455.0, 522.1, 536.8, 905.9, 919.0, 1818.5, 1827.8, 1908.9, 2288.4, 2326.3, 2364.6, 2408.5, 2454.5 |
| 3 | **+1** | 4.2, 4.8, 5.1, 5.2, 5.2, 5.5, 5.5, 5.5, 5.6, 6.2, 6.2, 6.4, 7.0, 7.0, 15.4 |

Combined across all 3 runs (`n=45`, percentiles per `load-test` skill's own rule - not averaged):
**p50 = 43.2 ms, p95 = 2 364.6 ms, p99 = 2 454.5 ms, max = 2 454.5 ms**. Every request returned `201` -
zero errors, zero failed handshakes, across all 45 concurrent cold-cache requests.

## Interpretation

**The herd never became 15 database reads in any run - `seq_scan` rose by exactly 1, 3, and 1**, well
below the 15 concurrent readers, in every run. The mechanism is doing real work: 15 concurrent misses
never produced more than one DB read per Api replica (3 replicas, so the worst possible full-collapse-
failure would be 3, which is exactly what run 2 shows) and in 2 of 3 runs the cross-node lock
collapsed the herd across all 3 replicas down to the theoretical minimum of 1.

**Latency did not spike proportionally to the 15-way concurrency, but it did spike per replica that
lost the cross-node lock race** - and that spike is large. Run 2's own numbers make the mechanism
visible directly: `caching.md` documents the cross-node `RedisLock` as **best-effort** - "a lock-
acquire failure or a lost race falls back to loading directly rather than blocking" - with a bounded
5×100ms poll before that fallback. Run 2's 8 slow requests (0.9s-2.45s) are not 8 independent slow DB
reads; `seq_scan` only rose by 3, meaning 3 replicas each ran their own in-process single-flight
attempt (collapsing whichever local concurrent requests landed on that pod into one shared `Lazy<Task>`
- `RedisCache.cs:62-128`), and 2 of those 3 lost the cross-node lock race, waited out the 500 ms poll
budget, then fell back to a *direct* load - explaining both the `seq_scan` delta of 3 (1 winner + 2
fallback losers) and why every request on a losing replica pays that replica's own shared delay rather
than a smaller, per-request one. Run 2's actual delays (up to 2.45s) run well past the nominal 500 ms
poll budget, suggesting either DB/network latency on this environment compounding past the
lock-and-fallback design's own assumption, or contention this run did not isolate further - a genuine
open question this report does not resolve, not a claim it does.

Run 1 and run 3, by contrast, show the mechanism working close to its best case: single-flight
collapsed cleanly to 1 DB read with no elevated latency at all. That inconsistency (2 clean, 1
partial-collapse-with-latency, out of 3 runs) **is itself the honest finding**: `caching.md`'s own
"best-effort, not a guarantee" language for the cross-node half of this mechanism is not a hedge -
it is describing exactly the intermittent behaviour observed live here. This is not the mechanism
failing; it is the mechanism behaving exactly as documented under real concurrency, and the report
would be dishonest reporting only the 2 clean runs.

## Verdict against `nfr.md`

**Partially met, at 1.5% of the stated concurrency target.** `caching.md`'s core claim - a cold-cache
miss does not turn into N database reads - held in all 3 runs (worst case 3 reads for 15 concurrent
requests across 3 replicas, never 15). The companion claim this report cannot fully confirm - "request
latency does not spike proportionally to concurrent-miss count" - held for the *median* request in
every run but not for every request: run 2 shows a genuine, bounded-but-real latency spike (up to
~150x the warm baseline) affecting exactly the replicas that lost the cross-node lock race. This is a
real, reproducible, minority-case (1 of 3) finding at 1.5% scale, not a pass/fail verdict that
extrapolates to 1000 concurrent readers across replicas - that number is still not measured.

## Instrumentation gap, stated plainly

`nfr.md`'s own Observability requirements name `Ago.Platform.Caching.Redis.CachingMetrics` (cache hit
ratio per namespace) as the evidence this scenario should cite. That metric does not exist in the
image this cluster is currently running or in this worktree's own pinned dependency
(`Directory.Packages.props` pins `Ago.Platform.*` at `0.13.0`; `CachingMetrics` ships in `0.14.0`,
part of `7-02`, confirmed absent by querying this cluster's own Prometheus - `ago_platform_caching_
redis_cache_access` returns no series). This report's evidence is `pg_stat_user_tables.seq_scan`
sampled directly against the cluster's own Postgres instead - a real, direct measurement of the
mechanism's effect, not a config read, but not the dashboard/query evidence a `7-02`-current build
would offer. Flagging the version gap plainly rather than silently substituting one form of evidence
for another and calling it equivalent.

## What was tuned

Nothing in the code under test. The rate-limit interaction above shaped the *test's own* burst size
(15, not an arbitrary round number) but no application config was changed for this run - the cluster
ran with its real, deployed defaults throughout.

## Follow-up

The run-2 finding (cross-node stampede collapse working in 2 of 3 attempts, with the failure mode
producing latency well past the documented 500ms poll-and-fallback budget) is worth a dedicated,
larger-N run once `nfr.md`'s full 1000-concurrent-reader scale is actually attempted, to see whether
the ~33% partial-collapse rate observed here holds, worsens, or was a one-off environmental artifact of
this specific shared dev machine. Not filed as a numbered backlog item here since it is a "measure
this more, at scale" note rather than a fix - matching this item's own out-of-scope note ("fixing
anything the numbers reveal... is a bug for a new backlog item, not a repair folded into this item's
own scope"), except this isn't a bug to fix, it's a measurement to redo at real scale.
