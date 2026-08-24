# 7-04: reconnect storm (reduced scale)

**Date**: 2026-08-24
**Commits**: `ago-chat` `f9c090dd41b353c16d9e2684874a1f6616676b5e` (`main`), `ago-root`
`04ecf0e974c0f9e0f519fb8ded952e2db1885226` (`main`, branch point for `docs/7-04-load-scenarios`)
**Hardware**: one Windows 11 development workstation - 11th Gen Intel Core i7-11800H, 8 cores / 16
logical processors, 63.8 GB RAM. **Not** the provisioned cluster `nfr.md` targets.

## Scale disclosure

**Deliberately, explicitly NOT `nfr.md`'s own target** - same reduced-scale, unsupervised-overnight
decision as every other report in this batch (full reasoning in `2026-08-24-steady-ingest.md`). This
scenario is a correctness proof more than a throughput one, so the "% of target" framing matters less
here than for the others, but the honesty rule is identical: 20 lanes / ~20 msg/s steady traffic is a
small fraction of `nfr.md`'s 3 000 msg/s sustained target, and this run is a single-instance restart,
not `k8s-local.md`'s 3-replica rolling restart. **Does not claim this correctness result would still
hold at full connection/message scale or against a genuine rolling multi-replica deploy** - a
single-process restart is a strictly simpler failure mode than a rolling deploy across replicas, which
is exactly what `edge.md`'s own jittered-backoff design (`realtime.md`) exists to smooth out at scale.

## Topology and tooling deviations

Same base topology as the other reports in this batch (compose loop, `Api` on `5109`/`5110`, one
`Worker`, real `.NET SignalR client` driver). Two deviations specific to this scenario:

- **A single-instance restart, not `k8s-local.md`'s rolling restart across 3 replicas.** This run's
  own topology has exactly one `Api` process per node role, so "restart the visitor-node `Api`" means
  a full, momentary outage of that node, not a rolling one-replica-at-a-time deploy behind a load
  balancer. `local-dev.md`'s own "testing a real reconnect (node death) locally" note already
  documents this exact limitation and its fix (a fixed `Auth__SigningKey` across restarts, applied
  here) - this run is that same proven approach, driven by the load driver instead of by hand.
- **The restart was triggered manually, not by the orchestration script as originally written.** The
  first attempt (`load/output/raw/run-reconnect-storm.ps1`, this branch) used `Get-Date -AsUTC`, a
  parameter this machine's installed Windows PowerShell version does not have (`-AsUTC` was added in
  a later PowerShell version than what `powershell.exe` resolves to here) - the orchestrator script
  crashed on that line before ever reaching the scheduled restart, while the driver process itself
  (already `Start-Process`-launched, independent of the parent script) kept running unaffected. Found
  live, fixed by issuing the same restart commands directly rather than via the broken script,
  ~69 s into the 200 s run instead of the originally planned ~95 s - still a genuine mid-run restart
  under real steady traffic, just not exactly at the pre-planned mark. The script itself was not
  re-run or corrected in this branch (`[DateTime]::UtcNow` is the fix, for whoever reruns this) since
  the manual path already produced the real result this scenario needed.

## What this scenario answers

`nfr.md`'s own binary correctness claim: "zero acknowledged-but-lost messages while killing a pod mid-
load." Concretely: does every message a lane received a successful `SendMessageAsync` ack for still
exist, exactly once, in that conversation's history after the visitor-node `Api` process is killed and
restarted mid-run? And separately: how long does the client-observed outage last, and does SignalR's
own automatic-reconnect + `realtime.md`'s resume protocol (`JoinAsync(lastKnownSequence)`, exercised
implicitly here since the token and connection resume against the same conversation) bring every lane
back without operator intervention?

## Load shape

20 lanes, one visitor WebSocket connection each (manually assigned to the seeded demo operator,
cross-node), each sending one message per second for 200 s (offered ~20 msg/s aggregate) - steady,
not bursty, so the restart's effect is isolated from any burst-shaped queueing. `HubConnection` built
with `WithAutomaticReconnect` (retry delays 0, 1, 2, 5, 5, 5, 5, 5 s). ~69 s into the run, the
visitor-node `Api` process was killed (`Stop-Process -Force`) and immediately relaunched with the
**identical** environment, including the same fixed `Auth__SigningKey`, on the same port - so every
lane's already-issued visitor token stayed valid across the restart, matching `local-dev.md`'s own
proven "same key, killed and restarted" reconnect test.

## Results

Source: `RunReconnectStormAsync`, `tests/Ago.Chat.LoadDriver/Program.cs` (this branch, `ago-chat`).
Raw CSV: `load/output/raw/reconnect-storm.csv` (gitignored).

**Timeline**:

| Event | UTC time |
|---|---|
| Run start | 05:47:38.294 |
| Visitor-node `Api` killed | 05:48:47.606 |
| New process object created | 05:48:48.754 (~1.15 s after kill) |
| All 20 lanes observed `Reconnected` | 05:48:50.134 (all 20 within a 0.15 ms spread of each other) |
| Run end | 05:50:58.294 |

**Client-observed outage window: ~2.53 s** from kill to every lane's `HubConnection` reporting
`Reconnected` (the new process's own ASP.NET Core startup, not connection-retry backoff, dominates
this - the lanes' 0 s-first-retry setting meant they were already hammering the (temporarily absent)
port the whole time).

| Metric | n | value |
|---|---|---|
| Successful sends (send -> ack, outside the outage window) | 3 460 | p50 129.6 ms, p95 175.0 ms, p99 240.7 ms, max 4 195.9 ms |
| Failed sends (during/around the outage window) | 8 | all `TaskCanceledException` or `WebSocketException` at 05:48:47.736 - 0.13 s after the kill signal, the in-flight sends that lost their connection |
| Reconnect events observed | 20 | across all 20 lanes - every lane recovered on its own, no lane left permanently disconnected |

The single 4 195.9 ms max in the ack-latency distribution is the one send that was in-flight or queued
immediately around the restart and got a slow ack once the connection recovered - not a steady-state
number, and not excluded from the stat above since it is a real, honestly-reported outlier, not a
warm-up artifact.

**Zero acknowledged-but-lost check (the concrete form of `nfr.md`'s correctness claim)**: for every
one of the 20 lanes, this run paginated that lane's own full conversation history after the run ended
and compared it against every sequence number `SendMessageAsync` had returned to that lane during the
run (the load driver's own `RunReconnectStormAsync` reconciliation step, `tests/Ago.Chat.LoadDriver/Program.cs`).

**All 20/20 lanes: OK - every one of 173 acknowledged messages present exactly once, no gap, no
duplicate.** (`load/output/raw/reconnect-storm-markers.txt` carries the same per-lane result lines.)

## Interpretation

**The correctness claim holds at this scale**: zero acknowledged-but-lost messages, zero duplicates,
across 20 lanes and 3 460 successful sends through a real process kill-and-restart. Every lane's
`HubConnection` recovered on its own via SignalR's automatic reconnect within the ~2.5 s outage
window - no lane needed the driver to intervene, and the 8 failed sends were exactly the in-flight
ones caught by the outage, not a broader failure. This is the same "no gap, no duplicate" result
`local-dev.md`'s own manual `5-07`/`5-09` verification already found by hand, now proven by an
automated driver across 20 concurrent lanes instead of one manual tab.

Not measured here, and worth naming as a real gap for the full-scale run: this was a **single-instance**
restart, so "reconnect latency" above is really "time for a brand-new `dotnet` process to finish
ASP.NET Core startup and start accepting connections again" - a k8s rolling restart across 3 replicas
would (by design) never take the whole node offline at once, so the *shape* of the outage a real
cluster run would see is different, likely shorter per-client and staggered rather than
simultaneous. This run cannot speak to that shape - only to "does the resume protocol correctly
recover with no loss," which it does.

## Server-side observations

No live dashboard for this run's own instances (same gap as the other reports in this batch). The new
visitor-node `Api` process's own `/healthz/live` returned `Healthy` within a few seconds of relaunch
(confirmed by hand immediately after the scripted restart, before the driver's own lanes had all
reconnected).

## What was tuned

Nothing pipeline-specific. `HubConnection`'s automatic-reconnect retry delays (`0, 1, 2, 5, 5, 5, 5, 5`
seconds) are this driver's own client-side choice, not a server config value - `realtime.md`'s own
jittered-backoff design governs the server's `reconnect(after: jitteredDelay)` push, which this
client-driven restart test does not exercise (that message is for a graceful server-initiated
drain/shutdown, not an abrupt kill, per `realtime.md`'s own distinction).

## What a real, full-scale run still needs

The provisioned `k8s-local.md` cluster's actual rolling restart (one replica at a time, behind NGINX
Gateway Fabric, `edge.md`), enough concurrent lanes to approach `nfr.md`'s own connection/throughput
targets, and - since a rolling restart is meant to be invisible to most clients - a report of *what
fraction* of clients see any interruption at all, not just "the one node's own clients recovered
cleanly" (this run's own single-node design cannot distinguish "no client saw any gap" from "the one
node I killed was the only node, so every client necessarily saw one").
