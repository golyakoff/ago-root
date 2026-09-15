# Local capacity ramp: how many open conversations before something breaks

**Date**: 2026-09-15
**Commits**: `ago-chat` `1756492df25edd131c26f27466efb2d8cd356fb9` (`main`, carries `capacity-ramp`
itself, landed same day), `ago-deploy` `8ff0a40833ec2b15263ad89755c513f9ba9850d1` (`main`, carries
`k8s/overlays/local-capacity-ramp`, also landed same day, including two rate-limit fixes this run's
own method found live and folded back in).
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

`k8s/overlays/local-capacity-ramp` on Docker Desktop: `ago-chat-api` ×3, `ago-chat-worker` ×3 (both
per-pod limits unchanged from `base` - 512 MiB/0.5 CPU and 512 MiB/1 CPU respectively, the same numbers
production runs under), one `postgres` (512 MiB/0.5 CPU), one `redis`, one `rabbitmq`, one `minio`, one
`keycloak`. Same per-pod ceilings as the public demo; only the replica counts and the surrounding
machine's own headroom differ.

## Results

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

## Interpreting

**The real bottleneck at this scale is not connection count, CPU, or any of the three rate limiters -
it is Postgres's own 512 MiB memory ceiling**, the identical number the public demo runs under. 500
concurrently open conversations, each holding a live connection and occasionally writing a message, was
enough to push a single Postgres instance to the edge of that limit and have the kernel or Postgres
itself take a backend down hard enough to trigger full crash-recovery. Three `ago-chat-api` replicas and
three `ago-chat-worker` replicas were all comfortably idle throughout (single digit-to-low-teens CPU
percent) - replicating the stateless hosts bought nothing here, because they were never the constraint.
This directly answers the "does scaling the stateless layer help" question this overlay was built to
ask: **not until Postgres's own memory budget is addressed first** - either a larger `postgres` pod
limit, or a load pattern this project has not yet needed to reason about (connection pooling limits,
`shared_buffers` sizing, or `work_mem` per connection - not diagnosed here, out of this report's own
scope).

**Read this against `2026-08-24-connection-storm.md`'s own 300-connection, fully-idle run** (`1.5%`
scale, `~37 KB/connection`, no failures) rather than as a contradiction: that scenario deliberately held
every connection silent to isolate pure connection-count memory growth from anything else. This run adds
real write traffic (a message roughly every 45 s per conversation) at a comparable connection count
(500 vs. 300) and finds the write path, not the connection count itself, as the actual limit - the two
reports are answering different questions and neither one's numbers transfer to the other's topology.

## What was tuned, and what regressed

- Tuned: three per-site rate limiters raised in `overlays/local-capacity-ramp` only (never in `base` or
  `demo`) - `VisitorSessionRateLimit`, `ConversationCreateRateLimit`, `MessageSendRateLimit`, each found
  live by actually hitting its default.
- Regressed/found, not fixed here: `25-107` - `VisitorHub.JoinCoreAsync` throws an unhandled
  `InvalidOperationException` (surfaced to the client as a raw `500`) instead of a `HubException` when
  `ConversationCreateRateLimit` refuses a join, unlike every other rate-limited path in the same file.
  Filed as its own item rather than fixed inline, since this report's own scope is measurement, not a
  code change to the hub.
- Not reached: steps 2-10 (1 000-5 000 connections). The safety valve did exactly what `25-102`'s own
  design intends - it stopped escalating rather than compounding a failure already in progress. A
  second run, after `postgres`'s own memory budget is revisited, would be the way to see step 2 for
  real.

## Honest gaps in this run

- **One data point, not a distribution.** A single `docker stats` snapshot caught the 89.9% memory
  reading; no continuous time series exists (this Prometheus instance scrapes no cAdvisor/container-
  level metrics - `container_cpu_usage_seconds_total` and friends are simply absent from it, confirmed
  by querying `__name__` directly). A second run instrumented with `docker stats --no-stream` polled on
  an interval, or a metrics-server, would turn "we caught it once" into a real curve.
- **No independent confirmation the OOM killer specifically fired** (vs. some other Postgres-internal
  fault) - the evidence (memory near the container's own limit, then a crash-recovery log, then memory
  back near zero, no Kubernetes-level pod restart) is strong but circumstantial; `dmesg`/kernel OOM logs
  were not captured from inside the node.
- **The live public demo was not re-tested this way.** This run is local-only, by design (squeeze what
  the workstation offers before touching the deployment other people can see) - a matching run against
  the real VPS, with its own single-replica-everything topology and the same 512 MiB Postgres limit, is
  the natural next step and was explicitly deferred to a second, separate, human-warned run.
