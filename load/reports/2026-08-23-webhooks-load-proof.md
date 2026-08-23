# 6-06: hung-webhook isolation load proof

**Date**: 2026-08-23
**Commits**: `ago-chat` `06c4e77e578b58715260eecb665b831ef33bc862` (`main`, includes `6-05`'s webhook
dispatcher), `ago-platform` `d91f05d919dda6fd9827aa31984828332038b275` (`main`, includes `6-01`'s
`Ago.Platform.Resilience`)
**Hardware**: one Windows 11 development workstation - 16 logical CPUs, ~68 GB RAM. **Not** the
provisioned cluster `nfr.md` targets - that is Stage 7's own job (`7-04`-`7-06`). This report's
absolute numbers must be read against that fact, not against `nfr.md`'s cluster-scale targets as if
they were comparable; the isolation *delta* (baseline vs. hung-CRM, same box, same run) is this
item's actual claim.

## What this proves, and what it does not

This is `6-06`'s own scope: prove that a hung webhook endpoint does not measurably slow chat message
delivery, and observe the per-endpoint breaker and per-tenant bulkhead doing real work while it
happens. It is explicitly **not** `nfr.md`'s full scale target (20,000 connections, 3,000 msg/s) -
that is Stage 7's much larger, cluster-provisioned undertaking.

**Verdict, stated plainly up front**: the isolation claim holds - chat message latency was not
measurably worse with the CRM hung than without it, on the same hardware, same run design. The
per-endpoint breaker opened and stayed open with **real evidence**, not an assertion. The per-tenant
bulkhead's own concurrency cap could **not** be proven to hold, despite three separate, deliberate
attempts to saturate it - a real gap, root-caused below, handed back as a new backlog item
recommendation rather than patched here.

## Topology

Compose fast-loop infra (`docker-compose`, already running for this session): Postgres, RabbitMQ,
Redis, MinIO, Keycloak - the same containers `docs/runbooks/local-dev.md` describes, not a second
copy. On top of it, six real, separately-running processes (all built `-c Release`, no code changes
beyond what's described in "Deviations" below):

| Process | Role | Port |
|---|---|---|
| `Ago.Chat.Api` (instance 1) | operator's node | 5009 |
| `Ago.Chat.Api` (instance 2) | visitor's node | 5010 |
| `Ago.Chat.Worker` | outbox dispatch, assignment | 5000 (default) |
| `Ago.Chat.FakeCrm` | `6-04`'s fake CRM, `FakeCrm__DefaultBehavior=hang-30s` for the whole hung-CRM window | 5290 |
| `Ago.Chat.WebhookDispatchRunner` | this item's own tooling (see Deviations) | 5292 |
| Load driver / dispatch runner | see below | n/a |

Both `Ago.Chat.Api` instances share one fixed `Auth__SigningKey` so a visitor token minted on
instance 2 is valid everywhere, and both point at the same Postgres/RabbitMQ/Redis - this is what
makes "operator connected to instance 1, visitor connected to instance 2" a **genuine cross-node**
pair for `realtime.md`'s connection-registry routing, not two copies of the same process pretending
to be different nodes.

## Deviations from the default tooling/host, stated plainly

Two deliberate deviations, both because this is a single dev workstation with only private-range
addresses, not a provisioned cluster with a public endpoint:

1. **Load driver is a real .NET SignalR client, not k6.** `docs/runbooks/load-testing.md` names k6 as
   this project's tool. k6 could not be installed in this sandboxed session without downloading and
   running an external binary this background session had no way to get interactive confirmation for
   (this repo's own tool-safety rules). Separately, and just as decisive: SignalR's hub protocol
   (JSON messages framed with a `0x1e` record separator over the WebSocket) is not something a k6
   script speaks out of the box: hand-rolling that framing from scratch, untested, risked measuring
   bugs in a reimplementation of the protocol rather than the real system. `tests/Ago.Chat.LoadDriver`
   (new, this item) uses the real `Microsoft.AspNetCore.SignalR.Client` package instead - the same
   library a real widget/console effectively sits on top of - and follows the load-test skill's own
   discipline otherwise: a stated load shape, a warm-up/baseline phase discarded from the "does the
   hung CRM change anything" comparison, percentiles not averages, real numbers or none at all.

2. **A new `tests/Ago.Chat.WebhookDispatchRunner` stands in for the real `Ago.Chat.Webhooks` host.**
   `6-05`'s dispatcher (merged to `main` the same day this item started) includes a delivery-time SSRF
   recheck (`ConnectWithSsrfRecheckAsync` in `Ago.Chat.Webhooks/Program.cs`) that resolves the target
   host's DNS itself and refuses to connect to any private, loopback, or link-local address - correct,
   deliberate, and proven by `6-05`'s own tests. It also makes it **structurally impossible** to point
   the real, unmodified host at a fake CRM this workstation can only run on a private address (every
   address a dev box owns - loopback, RFC1918, Docker/K8s pod/service ranges - is exactly what that
   check exists to block). This runner is `Ago.Chat.Webhooks/Program.cs` with that one check removed
   (documented at the point it differs, in both the runner's own `Program.cs` and its `.csproj`); every
   other line - `ChatModule` registration, resilience-pipeline options, the two real hosted RabbitMQ
   consumers, `HttpWebhookDeliveryClient`, `WebhookResiliencePipelines` - is the unmodified real
   product code, composed the same way `tests/Ago.Chat.Integration.Tests/WebhookDispatchTestHarness`
   (`6-05`'s own test suite) already composes it for the identical reason. The webhook endpoint itself
   was registered by inserting a `WebhookEndpoint` row directly via EF (`--seed` mode on this same
   runner), bypassing `RegisterWebhookEndpointHandler`'s own HTTPS-only/SSRF-at-registration check -
   the same "tests write rows directly, `6-03`'s own precedent" pattern `WebhookDispatchTestHarness.
   RegisterEndpointAsync` already establishes, for the same reason (that check is `6-03`'s to prove,
   already proven, and irrelevant to this item's own claim).

Both tools are real product code exercised end to end (real Postgres, real RabbitMQ, real outbox
dispatch, real Polly pipelines, a real hung `Ago.Chat.FakeCrm` process) - the deviations are about
which process composes that code and which client drives traffic, not about faking any of the
behaviour being measured.

## Scenario

- 8 concurrent visitor "lanes" connected to the visitor node (5010), each in its own conversation,
  auto-assigned (`JoinConversationAsync`) to the one seeded demo operator connected to the operator
  node (5009) - every single message therefore crosses nodes through the Redis-backed connection
  registry, matching `nfr.md`'s "delivered to a recipient on another node" row exactly, not by
  accident.
- Each lane sends one message every 6.5s. This rate is not an arbitrary "modest" pick - it is
  `MessageSendRateLimitOptions`' own configured per-site sustained cap (100 msg/min ≈ 1.67 msg/s,
  `caching.md`) that this system already enforces at these (unmeasured, default) settings; 8 lanes at
  6.5s ≈ 1.23 msg/s aggregate, safely under that cap so the numbers below measure message-pipeline
  latency, not this system's own rate limiter. Explicitly **not** `nfr.md`'s 3,000 msg/s target - that
  is Stage 7's job at cluster scale.
- 60s baseline (no `Ago.Chat.FakeCrm`, no dispatch runner running at all - literally nothing webhook-
  shaped exists yet) + 180s hung-CRM window (`FakeCrm__DefaultBehavior=hang-30s`, dispatch runner
  live, one active webhook endpoint registered for the site) started within ~0.3s of the marked
  `hung_start_utc`, verified from the driver's own printed timestamp vs. the process-launch timestamp.
- Every lane recycles (closes its conversation, opens a fresh one) every ~45s, keeping
  `ConversationAssignedToOperator`/`ConversationClosed` events - the two events `6-05`'s dispatcher
  reacts to - flowing continuously through the whole hung-CRM window, not just once at the start.
- A 25-conversation concurrent burst fired at the instant the hung-CRM window began, meant to stress
  the per-tenant bulkhead (see "Bulkhead" below for why this did not produce the intended evidence,
  and two further isolated burst attempts up to 40 concurrent conversations that also did not).

Full source: `tests/Ago.Chat.LoadDriver/Program.cs`, `tests/Ago.Chat.WebhookDispatchRunner/Program.cs`
(this branch). Raw per-message CSV: `load/reports/run1-messages.csv`. Resource samples:
`load/reports/run1-resource-samples.csv` (collector: `load/lib/resource-monitor.ps1`, **Windows-only**
- `Get-Process`-based, stated here since nothing else in this repo's tooling is platform-locked this
way).

## Results: chat message latency

| Path | Phase | n | p50 | p95 | p99 | max |
|---|---|---|---|---|---|---|
| Send → ack (persisted) | baseline (no webhook activity) | 80 | 86.1 ms | 111.8 ms | 154.9 ms | 154.9 ms |
| Send → ack (persisted) | hung-CRM window | 216 | 77.5 ms | 95.8 ms | 114.7 ms | 114.7 ms |
| Send → delivered, cross-node | baseline | 80 | 120.0 ms | 158.2 ms | 178.5 ms | 178.5 ms |
| Send → delivered, cross-node | hung-CRM window | 216 | 93.9 ms | 130.3 ms | 145.1 ms | 155.0 ms |

**The isolation claim**: every hung-CRM-window number is *lower* than its baseline counterpart, not
higher. There is no measurable slowdown from the hung webhook endpoint - if anything the opposite,
which is not evidence the hung CRM helped anything; it is warm-up (JIT, connection pools, caches) still
settling during the first 60s baseline window, the same effect `load-test`'s own skill names ("discard
the warm-up window explicitly"). Read this as "flat," not "faster because of the outage."

**Against `nfr.md`'s own targets** (send→ack: 15/50/150 ms; send→delivered cross-node: 40/120/300 ms
p50/p95/p99): this dev-loop run **misses every p50 and p95 target** on both paths, in both phases -
expected and stated up front, not a surprise this report is hiding. `nfr.md`'s numbers describe a
3-replica, resource-limited cluster under Stage 7's own load generator; this is one unbatched,
Development-mode process pair on a laptop, with `dotnet run`'s own JIT/startup overhead still present.
The **p99** numbers land inside or near target range (114.7/154.9 ms against a 150 ms ack target,
145.1 ms against a 300 ms delivered target) - encouraging, but not a substitute for Stage 7's own
measurement on the real topology. **This report does not claim `nfr.md`'s targets are met** - only
that the hung CRM did not make them worse.

## Results: breaker

**Real, extensive evidence** - not "should have opened per the config." Across the full run plus the
two follow-up bulkhead-focused bursts, 217 webhook deliveries were attempted against the one hung
endpoint; every one ended `DeadLettered`, and the dispatcher's own log names the reason for each:

```
Webhook delivery to endpoint ed623999-d002-4b79-a6d2-11dd1d3efaf2 dead-lettered after 2 attempt(s) (BreakerOpen).
Polly.CircuitBreaker.BrokenCircuitException: The circuit is now open and is not allowing calls.
 ---> Ago.Chat.Webhooks.WebhookResponseHeadersTimeoutException: The webhook endpoint did not send response headers within the configured timeout.
```

(full grep, 651 lines: `load/reports/run1-breaker-evidence.txt`,
`load/reports/bulkhead-burst-breaker-evidence.txt`)

Reason tally across every dead-lettered delivery in this report: 198 at `attempt(s)=1` (breaker
already open, near-instant short-circuit - no HTTP call made), 18 at `attempt(s)=2`, 1 at
`attempt(s)=3` (a real half-open probe genuinely paid the ~3s timeout again before re-opening the
breaker). This is exactly `resilience.md`'s "not stays half-open forever, not stays closed hammering a
dead endpoint" - the breaker opened within the first couple of real, full-timeout attempts and then
spent the rest of the run cycling open → half-open probe (pays one real timeout) → open again, since
the endpoint never recovers (by design, `hang-30s` never succeeds). Zero deliveries paid the full 30s
hang - the dispatcher's own 3s total timeout (`Resilience:Webhooks:Timeout:Duration`) is what actually
ends every attempt, matching `resilience.md`'s own "the total timeout is what ends it, not the fake
server giving up."

## Results: bulkhead - not proven, root cause identified

**The per-tenant bulkhead's `MaxConcurrency=4`/`MaxQueuedActions=16` cap was never observed to reject
anything, despite three separate attempts**: the 25-conversation burst inside the main run, and two
further isolated bursts (25 and 40 concurrent conversations, the second against a freshly restarted
dispatch runner with a clean, unopened breaker specifically to rule out "the breaker was already open
before the burst arrived" as the explanation). None produced a single `BulkheadRejected`-shaped
dead-letter reason - every one was `BreakerOpen`.

**Root cause, found by reading the actual consumer code, not guessed**:
`Ago.Platform.Messaging.RabbitMq.RabbitMqEventConsumer.SubscribeAsync` registers exactly one
`ReceivedAsync` handler per subscription that `await`s the caller's handler **inline**, before
returning control to the client library:

```csharp
consumer.ReceivedAsync += async (_, delivery) =>
{
    ...
    try { await handler(envelope, context, cancellationToken); }
    catch (Exception) { await context.NackAsync(requeue: true, cancellationToken); }
};
```

`PrefetchCount` (default 50) controls how many *unacked* messages the broker will buffer for this
channel, but it does not make delivery **processing** concurrent - each `ReceivedAsync` invocation is
awaited to completion before the next one is dispatched, so at most **one** delivery is being handled
at a time per subscription. `ConversationAssignmentWebhookDispatchConsumer` and
`ConversationClosedWebhookDispatchConsumer` are two independent subscriptions, so at most **two**
deliveries for one site can ever be in flight at once in the current architecture - structurally short
of `MaxConcurrency=4`, and nowhere near the 16-item queue that would need to fill before a rejection
is even possible. `DispatchWebhooksForEventHandler`'s own per-event fan-out is concurrent *across
endpoints for the same event* (`resilience.md`'s "one endpoint's failure never blocks another's") -
irrelevant here, since this test (like most real tenants) registered exactly one endpoint.

This is not a flaw in the Polly bulkhead policy itself (`WebhookResiliencePipelines.
GetSiteBulkheadPipeline`, unmodified, presumably correct in isolation - `Ago.Platform.Resilience`'s own
unit tests are the place that would prove that directly, not this item). It is that **the caller never
offers the bulkhead more than ~1-2 concurrent executions to gate**, regardless of how many events are
queued in RabbitMQ. A busy tenant with many endpoints, or several tenants' webhook traffic landing at
once, would hit the exact same ceiling in production - this is very likely also a **throughput problem
independent of the bulkhead question**: one message at a time per event type, per process, is a low
ceiling for a "webhook fan-out" system regardless of how fast each individual HTTP call is.

**Recommendation, not patched here** (matches this item's own explicit scope: a discovered resilience
gap is reported, not silently fixed inside `6-06`): a new backlog item to give
`RabbitMqEventConsumer` (or specifically the webhook-dispatch consumers) genuine concurrent message
processing - e.g. a bounded worker pool draining a local channel fed by `ReceivedAsync`, the same
bounded-channel shape `4-05`'s in-process message pipeline already uses elsewhere in this codebase -
and then re-running this same burst to actually observe `MaxQueuedActions` reject something. Until
that lands, the per-tenant bulkhead's own concurrency cap should be treated as **unverified under
concurrent load**, not proven safe by configuration.

## Results: resource usage (Api/Worker), whole run

Sampled every 5s throughout (`load/reports/run1-resource-samples.csv`, 180 samples across 3
processes). Working-set memory stayed flat with no growth trend across baseline → hung-CRM transition
or over the run's own 3+ minutes - no leak surfaced on the chat-pipeline side from the webhook side
being busy and failing continuously:

| Process | Working set (MB) | Threads | Handles |
|---|---|---|---|
| `Ago.Chat.Api` (operator node, 5009) | 152.6 – 182.7 | 29 – 38 | 686 – 730 |
| `Ago.Chat.Api` (visitor node, 5010) | 171.9 – 210.0 | 29 – 63 | 771 – 969 |
| `Ago.Chat.Worker` | 164.7 – 191.3 | 32 – 40 | 673 – 781 |

All well under `nfr.md`'s 512 MB/pod budget (again: this is a Development-mode process, not a
resource-limited container - not a claim that budget is met, just that nothing grew unbounded).
Thread/handle ranges are consistent with normal SignalR connection churn from lane recycling, not a
runaway count.

## Other real findings from this run, out of this item's own scope to fix

- **`Directory.Packages.props` was stale before this branch** - every `Ago.Platform.*` pin was
  `0.11.0` while `ago-platform`'s `main` (and its own `CHANGELOG.md`) had already moved the whole
  shared-version pack to `0.12.0` as of `6-01`. Restoring this solution against a freshly packed local
  feed failed outright (`NU1109`, package downgrade) before this branch bumped every pin to `0.12.0` -
  this blocked *any* build of `ago-chat`, not just this item's own new projects, so the fix is included
  in this branch's commit rather than filed separately (`Directory.Packages.props`, this diff).
- **`DbUpdateConcurrencyException` surfaces as a raw 500**, not a clean `409`, on `POST
  /api/v1/conversations/{id}/close` (and once on `JoinConversationAsync`) under concurrent load against
  the same conversation - a real optimistic-concurrency race between a message send updating
  `conversations.xmin` and a close/(re)assign reading a now-stale row. Hit 10 times across this run's
  ~200+ close/assign calls (~5%). Recommend a follow-up backlog item: `CloseConversationHandler`/
  `AssignConversationHandler` should retry once on `DbUpdateConcurrencyException` or translate it to a
  clean RFC 7807 `409`, matching `api-design.md`'s own error convention - not patched here, since it is
  unrelated to webhook isolation and this item's own scope explicitly does not extend to fixing
  discovered gaps.
- **An unrelated, pre-existing RabbitMQ queue** (`ConversationAssignedToOperator`, no consumer-name
  suffix) was observed holding 4,129 unconsumed messages with zero consumers, and
  `OperatorPresenceLost.operator-disconnect-grace` held 1,547 - neither is a queue this item's own
  consumers touch, and neither was created by this run. Flagged as observed, not investigated further
  (out of scope) - worth someone checking whether this is a leftover from a pre-`5-11` binding or a
  genuinely live leak.
- `VisitorSessionRateLimitOptions`' per-site cap (20 sessions/min) correctly rejected a portion of the
  concurrent-burst *session creation* calls with `429` during the bulkhead attempts - expected,
  correct inbound rate-limiting behaviour (`resilience.md`'s own boundary table), not a bug; noted so
  the burst's own numbers (fewer than the requested 25/40 conversations actually completed) are not
  mistaken for a driver defect.

## Verdict

**Isolation claim: met.** Chat message send→ack and send→delivered-cross-node latency were not
measurably worse with a webhook endpoint hung for the entire window than with no webhook activity at
all, on identical hardware and load shape. `nfr.md`'s own absolute cluster-scale targets are not met by
this dev-loop topology - expected, stated, and explicitly out of this item's scope to meet (Stage 7's
job).

**Breaker claim: met, with real evidence** - opens fast, stays open, half-open probes pay a real
timeout and correctly re-open rather than getting stuck either fully open forever or fully closed
hammering a dead endpoint.

**Bulkhead claim: not met.** Three deliberate attempts to saturate `MaxConcurrency=4`/
`MaxQueuedActions=16` for one tenant all failed to produce a single rejection, root-caused to
`RabbitMqEventConsumer`'s sequential-per-subscription delivery processing capping real concurrency at
~1-2 regardless of burst size or backlog depth. Recommended as a new backlog item (give the webhook
dispatch consumers genuine concurrent processing, then re-run this same burst) rather than patched
inside this item's own scope.
