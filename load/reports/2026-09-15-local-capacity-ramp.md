# Local capacity ramp: how many open conversations before something breaks

**Date**: 2026-09-15
**Commits**: `ago-chat` `39e425e903bf11665d4c5557742ad4fe0dec499a` (`main`, carries `capacity-ramp`
itself and `25-107`'s fix, both landed same day - Run 3 below is the first of the three run against
`25-107`'s fixed `JoinAsync`), `ago-deploy` `83074409a8244d92318c21b046dc8d3c0495ec57` (`main`, carries
`k8s/overlays/local-capacity-ramp` through all three runs below - three rate-limit fixes after Run 1,
the `postgres` 4x memory/CPU bump after Run 1's own finding before Run 2, `max_connections=300` after
Run 2's own finding before Run 3).
**Hardware**: one Windows 11 development workstation - 11th Gen Intel Core i7-11800H, 8 cores / 16
logical processors, allocated to Docker Desktop as 16 CPUs / ~31.2 GiB. Same CPU model as `7-04`/`7-05`'s
own workstation, different machine.
**Type**: a real measurement, not a synthesis - every number below comes from this run's own CSV/console
output, not copied from another report.

## What this run answers, and what it does not

The author's own question: for AGO Chat's real per-pod resource *shape* (the same memory/CPU limits
`k8s/base/*.yaml` gives every host in production - this is not a scaled-down toy), how many
simultaneously open visitor conversations survive before something breaks, and what breaks first -
with three replicas each of `ago-chat-api`/`ago-chat-worker` (`overlays/local-capacity-ramp`'s own
premise: does replicating the stateless hosts help, and where does that stop being the limiting
factor).

**This is not `nfr.md`'s own 20 000-connection target, run for real** - it is a first, honest look at
where the curve bends on hardware nobody has scaled out yet. It answers "what happens today", not
"is the target reachable."

## Method, including four failed attempts - each one is itself a finding

`load-test` skill's own discipline: report what did not work, not only what did. Four setup problems
were found and fixed before a single valid data point existed, and each is worth recording on its own:

1. **The local cluster's images were stale relative to `main`.** `ago-chat-api`'s options validation
   demanded `Billing:PricePerSeatRub`, a flat key `25-29` had already split into
   `Billing__BaseSeatPriceRub`/`Billing__PricePerExtraSeatRub` in the manifest weeks earlier - the
   `:local` image tag had not been rebuilt since. Fixed: `bash k8s/build-images.sh` against current
   `main`. Not this run's own finding about the *system*; a finding about how easily a long-lived local
   dev cluster drifts from the manifest it is fed.
2. **`kubectl port-forward` cannot carry this load.** The first real attempt (300+ concurrent
   connections) killed the tunnel outright - `socat[...] E write(6, ...): Broken pipe`, `error: lost
   connection to pod`. Not a server-side signal at all; `kubectl port-forward` is a debug tool, not a
   load path. Fixed: a temporary `NodePort` Service (`ago-chat-api-loadtest-nodeport`, not checked in -
   local-only, deleted after this run) routed by `kube-proxy` instead.
3. **Three separate per-site rate limiters, found one at a time by actually hitting each.**
   `VisitorSessionRateLimitOptions` (handshake), `ConversationCreateRateLimitOptions` (new
   conversation), `MessageSendRateLimitOptions` (message send) - each defaults to a low, explicitly
   "not measured or load-tested" per-site bucket (20-100 capacity), each sits behind a different
   handler, and each one only surfaced once the ramp got far enough to hit it. All three raised, this
   overlay only (`k8s/overlays/local-capacity-ramp`).
4. **`localhost` cost every connection an IPv6-then-IPv4 fallback.** The `NodePort` above listens on
   IPv4 only; `curl -6` against it hangs to a timeout. `LOADDRIVER_VISITOR_API=http://localhost:30510`
   made every one of .NET's own connection attempts try `[::1]` first and fall back - **p50 connect
   time of 21.1 s**, entirely a client-side artifact, not the server. Switching to
   `http://127.0.0.1:30510` explicitly dropped step 1's own p50 to 589 ms on an otherwise identical
   run. This is the `load-test` skill's own "watch for the load generator being the bottleneck" warning
   in a form specific to Windows/`localhost` dual-stack resolution, worth naming for the next person who
   points a driver at `localhost`.

Every one of the four is real and reproducible, and none of them is a claim about AGO Chat's own
capacity - they are what it took to get a clean measurement.

## Load shape

`capacity-ramp` (`Ago.Chat.LoadDriver`), defaults: `LOADDRIVER_STEP_SIZE=500`,
`LOADDRIVER_STEP_COUNT=10` (max target 5 000), `LOADDRIVER_STEP_HOLD_SECONDS=60`,
`LOADDRIVER_RAMP_CONCURRENCY=10`, `LOADDRIVER_MESSAGE_INTERVAL_SECONDS=45` (±20% jitter),
`LOADDRIVER_MAX_ERROR_RATE=0.05`. Each connection: a real visitor session + `JoinAsync` (a genuine new
conversation), then one visitor message roughly every 45 s while held open - deliberately not idle
(unlike `connection-storm`), matching "an operator waiting for messages."

## Topology

`k8s/overlays/local-capacity-ramp` on Docker Desktop: `ago-chat-api` ×3, `ago-chat-worker` ×3 throughout
all three runs (both per-pod limits unchanged from `base` in any run - 512 MiB/0.5 CPU and 512 MiB/1 CPU
respectively, the same numbers production runs under), one `redis`, one `rabbitmq`, one `minio`, one
`keycloak`. `postgres` is the one thing that differs run to run: 512 MiB/0.5 CPU, `max_connections=100`
(Run 1, `base`'s and the official image's own stock numbers, same as production) → 2 048 MiB/2 CPU
(Run 2, 4x both, at the author's own request after Run 1's finding) → `max_connections=300` added on top
(Run 3, after Run 2's own finding named the real cause: not memory, not CPU, a connection-count ceiling
neither prior change had touched). Otherwise the same per-pod ceilings as the public demo; only the
replica counts and the surrounding machine's own headroom differ.

## Results - Run 1 (stock resource limits)

| Step | Target | Reached | Connect errors | Connect p50/p95/p99/max | Message errors this step | Outcome |
|---|---|---|---|---|---|---|
| 1 | 500 | 500 | 0/500 (0.0%) | 589.3 / 1596.4 / 6654.2 / 8158.9 ms | 446/559 (79.8%) | **Safety valve fired** |

**One step reached, not ten.** Every one of the 500 connections opened successfully - the connect path
itself, at 500 concurrent open conversations across 3 replicas, has real tail latency (p99 6.7 s, one
outlier at 8.2 s) but zero failures. What actually broke, during the 60 s hold immediately after:

**Postgres crashed under memory pressure.** `docker stats`, sampled once mid-hold: `postgres` at
**460.3 MiB / 512 MiB (89.9%)**, `ago-chat-api` pods at 8-15% CPU each, `ago-chat-worker` at 3-7% -
nothing else was under real pressure. Sampled again ~90 s later: `postgres` at 25 MiB (4.9%), its PID
count dropped from 72 to 7. Its own log for that window:

```
FATAL:  the database system is in recovery mode          (repeated, dozens of backends)
LOG:  database system was not properly shut down; automatic recovery in progress
LOG:  redo starts at 0/BF47170
LOG:  redo done at 0/E6F2358
LOG:  database system is ready to accept connections
```

"Not properly shut down" is Postgres's own crash-recovery message - some backend process inside the
`postgres` container was killed abnormally (most likely the Linux kernel's OOM killer acting on the
container's cgroup, triggered by the 460 MiB reading moments earlier; the container itself never
restarted at the Kubernetes level - `kubectl get pod`'s `RESTARTS` stayed at `0` and
`lastState` stayed empty, so this was postmaster panicking and recovering in place, not a pod
restart). Every other pod's own health probes failed at the same moment (`Liveness probe failed:
dial tcp ...: connection refused` against `ago-chat-api`/`worker`/`webhooks`, `postgres`'s own probe:
"rejecting connections") - a single backend dying inside Postgres took the whole write path down with
it for the ~5-10 s the crash-recovery cycle took, which is exactly where the 446 message-send failures
and the WebSocket disconnects in the CSV come from. Recovery itself was fast and clean (WAL redo in
0.27 s wall-clock, no data loss - the same self-healing behaviour seen once already this session, that
time from an operator mistake rather than real load) - the finding is that it happened at all, not that
it took long to come back.

## Interpreting - Run 1

**The real bottleneck at this scale is not connection count, CPU, or any of the three rate limiters -
it is Postgres's own 512 MiB memory ceiling**, the identical number the public demo runs under. 500
concurrently open conversations, each holding a live connection and occasionally writing a message, was
enough to push a single Postgres instance to the edge of that limit and have the kernel or Postgres
itself take a backend down hard enough to trigger full crash-recovery. Three `ago-chat-api` replicas and
three `ago-chat-worker` replicas were all comfortably idle throughout (single digit-to-low-teens CPU
percent) - replicating the stateless hosts bought nothing here, because they were never the constraint.
This directly answers the "does scaling the stateless layer help" question this overlay was built to
ask: **not until Postgres's own memory budget is addressed first**.

**Read this against `2026-08-24-connection-storm.md`'s own 300-connection, fully-idle run** (`1.5%`
scale, `~37 KB/connection`, no failures) rather than as a contradiction: that scenario deliberately held
every connection silent to isolate pure connection-count memory growth from anything else. This run adds
real write traffic (a message roughly every 45 s per conversation) at a comparable connection count
(500 vs. 300) and finds the write path, not the connection count itself, as the actual limit - the two
reports are answering different questions and neither one's numbers transfer to the other's topology.

## Results - Run 2 (`postgres` at 4x memory and CPU: 2048Mi/2000m, from 512Mi/500m)

Same author, same day, direct follow-up: "можешь поднять в 4 раза память постгресу и ещё раз
попробовать?" (raise postgres's memory 4x and try again), then "добавь cpu тоже" (add CPU too) once
Run 1's own finding named memory specifically but left CPU untouched. `postgres` rolled cleanly this
time - `LOG: database system was shut down` (its normal shutdown message), not Run 1's "was not
properly shut down" - confirming the resize itself was uneventful.

| Step | Target | Reached | Connect errors | Connect p50/p95/p99/max | Message errors this step | Outcome |
|---|---|---|---|---|---|---|
| 1 | 500 | 500 | 0/500 (0.0%) | 125.4 / 364.9 / 3993.6 / 4957.5 ms | 0/500 (0.0%) | clean |
| 2 | 1 000 | 1 000 | 0/500 (0.0%) | 98.1 / 189.2 / 205.9 / 257.0 ms | 0/1 121 (0.0%) | clean |
| 3 | 1 500 | 1 500 | 0/500 (0.0%) | 143.4 / 252.4 / 309.5 / 596.9 ms | 0/1 856 (0.0%) | clean |
| 4 | 2 000 | 2 000 | 0/500 (0.0%) | 143.9 / 202.2 / 243.8 / 256.8 ms | 0/2 463 (0.0%) | clean |
| 5 | 2 500 | 2 329 | 171/500 (34.2%) | 231.3 / 689.3 / 1216.0 / 3642.4 ms | 2 034/3 104 (65.5%) | **Safety valve fired** |

Four full steps (2 000 concurrently open conversations, 8 038 messages sent, zero errors of any kind)
against the identical stateless-side resources Run 1 never got past 500 with. `postgres` itself stayed
healthy throughout step 5's own collapse - `docker stats` immediately after teardown: 278.9 MiB / 2 GiB
(13.6%), 0 container restarts. **What broke this time was `ago-chat-api`/`ago-chat-worker` themselves**,
confirmed from `kubectl get events`: a sequence of `Readiness probe failed: HTTP probe failed with
statuscode: 503` → `Liveness probe failed: ... context deadline exceeded` → `Container api failed
liveness probe, will be restarted` → `Liveness probe failed: ... connection refused` on multiple
`ago-chat-api` and `ago-chat-worker` pods within the same ~90 s window as step 5. Each restarted pod's
own `lastState` shows `exitCode: 0, reason: "Completed"` - a graceful Kubernetes-initiated restart after
the probe stopped answering in time, not a crash - but every live WebSocket connection on that pod was
still dropped (`The remote party closed the WebSocket connection without completing the close
handshake.`, dozens of instances in the CSV), which is where step 5's own connect and message failures
come from.

## Interpreting - Run 2

**Postgres's own 512 MiB ceiling was masking a second, higher one**: once memory stopped being the
first thing to break, the stateless hosts' own `base`-defined limits (512 MiB/0.5 CPU per `ago-chat-api`
replica, 512 MiB/1 CPU per `ago-chat-worker` replica - unchanged in this run, three replicas each) turned
out to be real after all, just further out - somewhere between 2 000 (clean) and 2 329 (probes already
timing out) concurrently open conversations. This is a materially different failure shape than Run 1's:
not a crash with a recovery cycle, but individual pods going too slow to answer their own health check
in time and being cycled by Kubernetes, each cycle dropping every WebSocket connection it was holding.
**The same lesson Run 1 taught about Postgres applies again, one layer up**: three replicas gave roughly
4x the connection count before failing (500 → ~2 300) compared to a hypothetical single replica at the
same per-pod limit - replicating the stateless hosts *did* help this time, because this time they were
the actual constraint, unlike Run 1 where they never got the chance to matter.

**Revised, after Run 3's own diagnosis below**: "the stateless hosts' own limits turned out to be real"
was an inference from the probe-timeout symptom, not a direct measurement - this report's own standing
rule is to say so plainly rather than let it stand unchallenged once a real measurement exists. Run 3's
`dotnet-trace` capture and a live-reproduced `PostgresException 53300` both point at the same untouched
`postgres:18-alpine` stock `max_connections=100` as the more precise cause: three `ago-chat-api` and
three `ago-chat-worker` replicas, each pooling its own Npgsql connections, colliding on that shared
100-connection ceiling as concurrent hub invocations grew - `ago-chat-api`/`worker` were not necessarily
slow because of their *own* CPU/memory, but because their requests were blocked waiting for a Postgres
connection slot Postgres itself was refusing. The "replicating them bought ~4x" conclusion still holds
as an observation; the *reason* it broke where it did is revised.

## Results - Run 3 (`postgres.max_connections=300`, from the stock 100)

Direct follow-up to Run 2's own diagnosis, not a guess: `docker stats` mid-Run-2 showed `postgres` CPU
at 113-200% of its 2-CPU limit and `pg_stat_activity` matching `docker stats`' own `PIDS` count exactly
(PostgreSQL is process-per-connection, not thread-pooled - confirmed live, not assumed), and a live
`PostgresException: 53300: sorry, too many clients already` reproduced running `capacity-ramp` again.
`max_connections` raised to 300 (`args`, not `command`, so the official image's own
`docker-entrypoint.sh` still runs its init-or-verify logic) - `shared_buffers`/`work_mem`/
`effective_cache_size` left at their own stock defaults (128 MB / 4 MB / 4 GB respectively, none of
which had ever been tuned for this container's real 2 GiB either), out of this run's own scope.

| Step | Target | Reached | Connect errors | Connect p50/p95/p99/max | Message errors this step | Outcome |
|---|---|---|---|---|---|---|
| 1 | 500 | 500 | 0/500 (0.0%) | 168.7 / 309.3 / 2848.2 / 3352.9 ms | 0/500 (0.0%) | clean |
| 2 | 1 000 | 1 000 | 0/500 (0.0%) | 97.7 / 193.0 / 240.1 / 274.8 ms | 0/1 144 (0.0%) | clean |
| 3 | 1 500 | 1 500 | 0/500 (0.0%) | 172.2 / 279.5 / 294.9 / 379.6 ms | 0/1 832 (0.0%) | clean |
| 4 | 2 000 | 2 000 | 0/500 (0.0%) | 205.5 / 302.1 / 382.3 / 788.2 ms | 0/2 528 (0.0%) | clean |
| 5 | 2 500 | 2 500 | 0/500 (0.0%) | 501.0 / 1705.9 / 2195.7 / 3601.0 ms | 0/2 590 (0.0%) | clean, latency climbing |
| 6 | 3 000 | 3 000 | 0/500 (0.0%) | 391.7 / 896.4 / 1200.4 / 1306.4 ms | 0/3 574 (0.0%) | clean |
| 7 | 3 500 | 3 500 | 0/500 (0.0%) | 407.9 / 925.8 / 1201.0 / 1400.1 ms | 0/3 225 (0.0%) | clean, ack p50 already 8.6 s |
| 8 | 4 000 | 4 000 | 0/500 (0.0%) | 496.2 / 998.3 / 1185.2 / 1396.4 ms | 1 091/2 229 (48.9%) | **Safety valve fired** |

Eight full steps, 4 000 concurrently open conversations reached with **zero connect errors at any
step** - every earlier run's own ceiling (500 in Run 1, ~2 300 in Run 2) passed cleanly. `docker stats`
mid-step-5, mid-hold: `postgres` at **199.83% CPU** (its 2-CPU limit, essentially saturated) and 259
connections (86% of the new 300 cap) - confirmed with a live number, not inferred. By step 8's own hold,
message-send latency reached **p50 40.2 s, p99 43.4 s** before the safety valve fired on a 48.9% message
error rate; the errors themselves (`The remote party closed the WebSocket connection without completing
the close handshake`, `'InvokeCoreAsync' ... connection is not active`) are timeout/disconnect symptoms
of that latency, not a new distinct failure mode - no `PostgresException 53300` this run, and `postgres`
itself never crashed or restarted (confirmed after teardown: same container, 0 restarts, memory back to
75%).

## Interpreting - Run 3

**Raising `max_connections` converted a hard failure into 8x more clean capacity and a graceful, if
severe, degradation** - not a cure, a trade. The connection-slot ceiling Run 2 was actually hitting is
gone at this scale; what is left underneath it, now visible for the first time, is genuine CPU
saturation on `postgres` itself (confirmed live at 194-200% of its 2-CPU limit during the degradation
window) - a real, different, and expected constraint once the artificial one in front of it is removed.
This is the textbook shape of chasing a bottleneck: each fix exposes the next real one, closer to the
actual resource ceiling, rather than producing an unlimited system.

**Why this refutes "add more `max_connections`" as a general strategy, not just at this specific
number**: PostgreSQL is process-per-connection (confirmed live via `pg_stat_activity` count matching
`docker stats`' own `PIDS` exactly) - every additional connection is a real OS process with real
baseline memory (measured live: (1.759 GiB total - 128 MiB `shared_buffers`) / 270 connections ≈
6.4 MiB/connection at step 8, in the same range the commonly-cited 5-10 MiB/idle-connection figure
gives) and real scheduling cost once active. On this container's own 2 CPU / 2 GiB, that arithmetic
caps out well before 300: memory-wise, roughly 250-280 total connections is where per-connection
overhead alone approaches the 2 GiB limit even before any query's own `work_mem`; CPU-wise, the
commonly-cited no-pooler formula (`(2 × cores) + spindle_count`, ~4-8 here) is far more conservative
than what this workload's own light per-message queries actually cost, but the *direction* is the same
one this run's own CPU reading confirms - somewhere on the order of 100-150 concurrently **active**
(not merely connected) backends is closer to where this specific 2-CPU box's real throughput plateaus.
Past that, more `max_connections` buys queueing room, not more throughput. The scalable fix at real
production scale is not a bigger number here - it is a connection pooler (PgBouncer, transaction-mode)
holding a small, fixed number of real Postgres backends in front of however many client connections the
app side wants to open, decoupling "how many app replicas/threads want a connection" from "how many OS
processes Postgres has to run." Not built or measured in this report - named as the next real step, not
guessed at further.

## What was tuned, and what regressed

- Tuned (Run 1): three per-site rate limiters raised in `overlays/local-capacity-ramp` only (never in
  `base` or `demo`) - `VisitorSessionRateLimit`, `ConversationCreateRateLimit`, `MessageSendRateLimit`,
  each found live by actually hitting its default.
- Tuned (between Run 1 and Run 2, the author's own explicit follow-up): `postgres`'s memory
  (512Mi→2048Mi) and CPU (500m→2000m) raised 4x, same overlay, requests scaled proportionally.
- Tuned (between Run 2 and Run 3, after this report's own `dotnet-trace`/live-error diagnosis):
  `postgres.max_connections` 100→300, via `args` (the image's own `docker-entrypoint.sh` still runs).
- Fixed, not just found (between Run 2 and Run 3): `25-107` - `VisitorHub.JoinCoreAsync` threw an
  unhandled `InvalidOperationException` (a raw `500` to the client) instead of a `HubException` when
  `ConversationCreateRateLimit` refused a join, unlike every other rate-limited path in the same file.
  Found live during Run 1, filed as its own item, fixed and merged (`ago-chat` PR #309) before Run 3 -
  Run 3 is the first of the three runs against the fixed `JoinAsync`.
- Not reached: Run 1's steps 2-10, Run 2's steps 6-10, Run 3's steps 9-10. All three safety-valve trips
  did exactly what `25-102`'s own design intends - stopped escalating rather than compounding a failure
  already in progress.

## Honest gaps in this run

- **One data point per run, not a distribution.** A single `docker stats` snapshot per run caught each
  finding; no continuous time series exists (this Prometheus instance scrapes no cAdvisor/container-
  level metrics - `container_cpu_usage_seconds_total` and friends are simply absent from it, confirmed
  by querying `__name__` directly). A third run instrumented with `docker stats --no-stream` polled on
  an interval, or a metrics-server, would turn "we caught it once" into a real curve for either finding.
- **No independent confirmation Run 1's OOM killer specifically fired** (vs. some other Postgres-internal
  fault) - the evidence (memory near the container's own limit, then a crash-recovery log, then memory
  back near zero, no Kubernetes-level pod restart) is strong but circumstantial; `dmesg`/kernel OOM logs
  were not captured from inside the node.
- **Run 2's own probe timeouts were root-caused after the fact, not in the moment** - Run 3's diagnosis
  (`dotnet-trace` on a bare local `ago-chat-api` instance, `DOTNET_PROCESSOR_COUNT=1`, plus a live
  `pg_stat_activity`/`docker stats` reading) points convincingly at `max_connections=100` rather than
  `ago-chat-api`/`worker`'s own CPU or memory, but that diagnosis was run against a *different* process
  (a standalone instance, not one of Run 2's own three live replicas, and after `25-107`'s fix landed) -
  a genuinely strong inference, not a repeat of the exact failing configuration.
- **Run 3's own CPU-saturation finding has the same shape of gap Run 2's did**: `docker stats` caught
  postgres at 194-200% CPU during the degradation window, which is real and load-bearing evidence, but
  it is still point-in-time snapshots, not a continuous trace of `postgres`'s own internals during the
  exact failure - no server-side profiling of the postgres process itself was attempted here, only of
  the client-side `ago-chat-api`.
- **Where the real ceiling sits was narrowed but not pinned to the connection** - clean through 4 000,
  failing during 4 000's own hold; `capacity-ramp`'s own step size (500) is coarser than this boundary.
- **The live public demo was not re-tested this way.** All three runs are local-only, by design (squeeze
  what the workstation offers before touching the deployment other people can see) - a matching run
  against the real VPS, with its own single-replica-everything topology (so no `postgres.max_connections`
  headroom argument from "many replicas pooling against one Postgres" applies the same way), is the
  natural next step and was explicitly deferred to a separate, human-warned run.
