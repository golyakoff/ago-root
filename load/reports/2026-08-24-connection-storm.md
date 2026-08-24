# 7-04: connection storm (reduced scale)

**Date**: 2026-08-24
**Commits**: `ago-chat` `f9c090dd41b353c16d9e2684874a1f6616676b5e` (`main`), `ago-root`
`04ecf0e974c0f9e0f519fb8ded952e2db1885226` (`main`, branch point for `docs/7-04-load-scenarios`)
**Hardware**: one Windows 11 development workstation - 11th Gen Intel Core i7-11800H, 8 cores / 16
logical processors, 63.8 GB RAM. **Not** the provisioned cluster `nfr.md` targets.

## Scale disclosure - read this before the numbers below

**Deliberately, explicitly NOT `nfr.md`'s own target** - same reduced-scale, unsupervised-overnight
decision as every other report in this batch (full reasoning in `2026-08-24-steady-ingest.md`).

| | `nfr.md` target | This run | Scale factor |
|---|---|---|---|
| Concurrent WebSocket connections | 20 000 total | 300 | **1.5%** |

Proves the scenario design and measurement method, and gives one honest per-connection memory data
point. **Does not claim `nfr.md`'s 20 000-connection ceiling is reachable, or that per-connection
memory stays this low at that scale** - GC behaviour and connection-registry contention at 1.5% of
target are not the same regime as 100%. A real run needs the provisioned cluster and enough
concurrent client processes/machines that the load generator's own memory is not confounded with the
server's (a single driver process holding 20 000 live `HubConnection` objects would itself become a
major memory consumer worth isolating from the server-side number).

## Topology and tooling deviations

Same as `2026-08-24-steady-ingest.md`: compose loop, not k8s (a concurrent unrelated session already
had the k8s cluster and the default `Api` port `5009` in use); this run's own `Api` instances on
`5109`/`5110`; real `.NET SignalR client` driver instead of k6.

This scenario needed only the visitor-node `Api` (`5110`) and did **not** raise `VisitorSessionRateLimit`
beyond what `steady-ingest`/`burst-ingest` had already set earlier in the same session (same
long-lived process) - stated here since a fresh run of this scenario alone, against default limiter
config, would need `VisitorSessionRateLimit__PerSiteCapacity` raised above its 20-handshake-burst
default to reach 300 connections without the limiter itself becoming the bottleneck.

## What this scenario answers

`nfr.md`'s own stated reason for the 20 000-connection target: is per-connection memory and GC
pressure visible and bounded as concurrent connection count grows? Does connect time (visitor-session
REST call + hub negotiate + `JoinAsync`) stay flat as connections ramp, or degrade?

## Load shape

Ramp to 300 concurrent visitor WebSocket connections over 60 s (15-connection concurrency gate, ~5
new connections/s), each connection opened, joined (`JoinAsync`, starting a conversation), then held
**idle** - no message traffic, deliberately, to isolate connection-scale effects from the ingest-
pipeline effects `steady-ingest`/`burst-ingest` already cover. Hold at 300 for 90 s, then close every
connection. Total wall clock ~150 s (plus teardown). Paired with `resource-monitor.ps1` (`6-06`'s own
tool, reused unmodified) sampling all three processes every 5 s for the run's full duration.

## Results

Source: `RunConnectionStormAsync`, `tests/Ago.Chat.LoadDriver/Program.cs` (this branch, `ago-chat`).
Raw CSV: `load/output/raw/connection-storm.csv` (gitignored). Resource samples:
`load/output/raw/connection-storm-resource-samples.csv` (106 samples across 3 processes,
`resource-monitor.ps1`, Windows-only - `Get-Process`-based, stated since nothing else in this repo's
tooling is platform-locked this way).

**Connections**: 300/300 connected successfully, 0 failures, 300/300 still open at teardown (no
connection dropped unexpectedly during the 90 s hold).

| Metric | n | p50 | p95 | p99 | max |
|---|---|---|---|---|---|
| Connect time (POST visitor-session + hub negotiate + `JoinAsync`) | 300 | 21.5 ms | 47.4 ms | 58.9 ms | 333.7 ms |

Connect time stayed low and stable through the ramp - no visible degradation as concurrent connection
count grew from 0 to 300 (the max of 333.7 ms is a single outlier, not a trend; p99 at 58.9 ms is
close to p50, unlike a queueing signature where p99 would pull far above p95).

**Resource usage, visitor-node `Api` (the only process this scenario's connections touch)**:

| Point | Working set (MB) | Threads | Handles |
|---|---|---|---|
| Pre-ramp baseline (before this scenario's own connections opened) | 306.5 | 84 | 995 |
| Post-ramp, 300 connections settled | 316.6 - 317.9 | 42 - 55 | 1 061 - 1 296 |

**~11 MB total growth for 300 additional concurrent connections (~37 KB/connection)**, and it stayed
flat (not climbing) for the full 90 s hold - no leak signature. Thread count did **not** scale
linearly with connection count (42-55 threads holding 300 async WebSocket connections) - expected for
Kestrel's async I/O model, not one OS thread per connection. Handle count grew roughly proportionally
(~995 to ~1 061-1 296) and also stayed flat during the hold. `Worker` and operator-node `Api` (both
untouched by this scenario's own connections) stayed essentially flat throughout (`Worker` 180.0-190.4
MB, operator-node 184.3-184.4 MB) - confirming the memory growth above is attributable to the visitor
connections specifically, not general session drift.

All comfortably under `nfr.md`'s 512 MB/pod budget - **not a claim that budget holds at 20 000
connections**, only that nothing looked abnormal at 300, and the ~37 KB/connection figure is at least
a real (if small-scale) number to extrapolate *from*, cautiously, when planning the full-scale run.

## Interpretation

No queueing or degradation signature in connect time as connections ramped (flat p50/p95/p99
throughout, no upward trend visible in the raw CSV's own timestamp-ordered samples). Memory growth
was small, linear-looking, and did not continue growing during the idle hold - consistent with
per-connection state being bounded and released correctly on the happy path. This says nothing about
behaviour near capacity limits, under connection churn (see `2026-08-24-reconnect-storm.md` for churn
under restart specifically), or at anywhere near 20 000 connections.

## What was tuned

Nothing pipeline-specific - `VisitorSessionRateLimit` was already raised earlier in this session (see
above). No batch-size, channel-capacity, or connection-registry knob was changed.

## What a real, full-scale run still needs

The provisioned cluster, enough separate load-generator processes/machines that 20 000 live
`HubConnection` objects don't make the generator itself the memory story, and - given this run's own
~37 KB/connection number came from only 300 connections - a genuine measurement at meaningfully
higher counts (several thousand, not just the final 20 000 target) to see whether per-connection cost
stays flat or grows as the connection registry (Redis-backed, per `realtime.md`) itself comes under
more load.
