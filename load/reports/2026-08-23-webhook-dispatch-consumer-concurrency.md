# 6-07: webhook-dispatch consumer concurrency - the bulkhead rejection, observed

**Date**: 2026-08-23
**Commits**: `ago-chat` branch `feat/6-07-webhook-dispatch-consumer-concurrency`, based on `main`
`9697ecb` (`6-06`'s own merged webhooks-load-proof commit). *(Exact commit hash for this item's own
change to be filled in once committed - this report was written and the run performed against the
uncommitted working tree of that branch.)*
**Hardware**: the same one Windows 11 development workstation `6-06`'s report used - 16 logical CPUs,
~68 GB RAM, **shared with other concurrent sessions during this run** (see "Deviations" below) - not
the provisioned cluster `nfr.md` targets.

## What this proves, and what it does not

`6-06`'s own report left one claim unmet: "the per-tenant bulkhead's own concurrency cap was never
observed to reject anything, despite three separate attempts" - root-caused there to
`Ago.Platform.Messaging.RabbitMq.RabbitMqEventConsumer.SubscribeAsync` awaiting its handler delegate
inline, capping real per-subscription concurrency at ~1-2 regardless of burst size. `6-07`'s own scope
is exactly closing that gap: give the two webhook-dispatch consumers genuine concurrent processing,
preserve per-conversation ordering while doing it, and re-run `6-06`'s own burst to see whether a real
`BulkheadRejected`-shaped outcome now appears.

This report is **not** a re-run of `6-06`'s full latency-isolation/breaker proof - that claim was
already met with real evidence in `6-06`'s own report and is unrelated to this item's own change (no
message-pipeline code was touched). This report is scoped to the one thing `6-06` left open: does a
burst now actually reach and exceed the bulkhead's `MaxConcurrency=4`/`MaxQueuedActions=16` = 20-slot
cap for one tenant.

**Verdict, stated plainly up front**: yes. Two genuine `BulkheadRejected` deliveries
("Rejected by per-tenant concurrency limit.") were recorded in `webhook_deliveries`, the first time
this outcome has ever been observed for this system - `6-06`'s own three deliberate attempts (up to 40
concurrent conversations) produced zero. The fix (`ConcurrentWebhookDispatchPump`, a bounded local
queue plus a per-conversation-key FIFO dispatcher, entirely inside `Ago.Chat.Webhooks` - see the
handback report's "What I built" for the full design) is what unlocked this: real concurrent delivery
attempts now reach double digits within milliseconds of a burst starting, comfortably exceeding what a
single-flight consumer could ever produce.

## The fix, in one sentence

Both webhook-dispatch consumers now enqueue each delivery into a bounded, in-process `Channel<T>`
and return immediately from the delegate `RabbitMqEventConsumer.SubscribeAsync` awaits inline, so the
broker client dispatches the next delivery right away instead of waiting for this one's real (possibly
multi-second) processing to finish; a single dispatch loop then hands each delivery to a per-conversation
FIFO mailbox, and up to `MaxConcurrency` (32, unmeasured starting point) of those mailboxes run their
handler concurrently at once, bounded by a shared semaphore, independent of `PrefetchCount`. Full design
rationale, the real ordering bug this design caught and fixed during development, and every architectural
trade-off: `src/Ago.Chat.Webhooks/ConcurrentWebhookDispatchPump.cs`'s own doc comments (this branch).

## Topology

Same compose fast-loop infra `6-06` used (Postgres, RabbitMQ, Redis, MinIO, Keycloak - already running,
shared with other work on this machine, not started or stopped by this run), same demo tenant/site
(`00000000-0000-0000-0000-000000000001`), same operator capacity bump (50) and `conversation:close`
grant `6-06` had already applied and left in place. Five real, separately-running processes, all built
`-c Release` from this branch's own working tree (`Ago.Chat.slnx` build, no `AgoPlatformDevOverride` -
this item made no `ago-platform` change):

| Process | Role | Port |
|---|---|---|
| `Ago.Chat.Api` (instance 1) | operator's node | 5009 |
| `Ago.Chat.Api` (instance 2) | visitor's node | 5010 |
| `Ago.Chat.Worker` | outbox dispatch, assignment | 5000 (default) |
| `Ago.Chat.FakeCrm` | `FakeCrm__DefaultBehavior=hang-30s` | 5290 |
| `Ago.Chat.WebhookDispatchRunner` | `6-06`'s own stand-in for `Ago.Chat.Webhooks` (SSRF-recheck removed only - see `6-06`'s report for why) - now running **this item's fixed consumers**, unmodified otherwise | 5292 |

## Deviations from `6-06`'s own scenario, stated plainly

1. **A fresh `WebhookEndpoint` was registered for the burst, not `6-06`'s original one.** The shared
   compose broker had accumulated a real backlog of unacked/retry-queued events from `6-06`'s own
   earlier session (still sitting in the `.retry` queues at the moment this item's `Ago.Chat.Worker`/
   `WebhookDispatchRunner` were started). Draining that backlog on startup tripped `6-06`'s original
   endpoint's own per-endpoint breaker (`WebhookResiliencePipelines.GetEndpointPipeline`, keyed by
   `WebhookEndpointId`) before this item's own deliberate burst could run - exactly the "needs a fresh,
   unopened breaker to have any chance of working" condition `6-06`'s own report already named. The old
   endpoint was deactivated (`UPDATE webhook_endpoints SET active=false`) and a new one seeded
   (`--seed`, same mechanism `6-06` used) pointing at the same hung `Ago.Chat.FakeCrm`, giving the burst
   a genuinely untripped breaker to work against - the bulkhead itself (keyed by `SiteId`, not
   `WebhookEndpointId`) needed no such reset, since it carries no persisted "open" state between calls.
2. **A shortened scenario, not the full 60s baseline + 180s hung window.** This item's own claim is
   narrower than `6-06`'s (one mechanism, not the full isolation/breaker/bulkhead triad), so the run
   used `LOADDRIVER_BASELINE_SECONDS=3 LOADDRIVER_HUNG_SECONDS=20 LOADDRIVER_LANES=1` - long enough for
   the burst itself and a few steady-lane sends either side of it, short enough to be a good citizen on
   a machine shared with other concurrent sessions. `LOADDRIVER_BULKHEAD_BURST=25`, unchanged from
   `6-06`.
3. **Machine was not otherwise idle.** Unlike `6-06`'s own run (a dedicated window), this run shared the
   box with many other concurrent background sessions (visible in the OS's own process list throughout).
   This has no bearing on the structural claim being made (a real `BulkheadRejected` outcome either
   appears or it does not - noisy-neighbour CPU contention does not fabricate one), but it is why this
   report does not repeat `6-06`'s own latency-isolation table as a fresh claim - that comparison needs
   a clean baseline this run's conditions could not honestly provide, and it is not this item's own
   claim to make again.

## Results: the burst

25 concurrent conversations requested; `LOADDRIVER_BULKHEAD_BURST`'s own driver hit the pre-existing,
correct `VisitorSessionRateLimitOptions` per-site rate limit (`429`, expected inbound behaviour -
`6-06`'s own report notes the identical effect) and once the pre-existing `DbUpdateConcurrencyException`
gap `6-06` already reported and recommended as a separate item - 18 conversations' worth of
assign+close event pairs actually reached the broker. Even with that attrition:

```
SELECT status, response_snippet, count(*)
FROM webhook_deliveries WHERE endpoint_id = '9acacf91-b5e1-4dd6-9f6a-e95d461c7d34'
GROUP BY status, response_snippet ORDER BY count(*) DESC;

    status    |                  response_snippet                  | count
--------------+-----------------------------------------------------+-------
 DeadLettered | The circuit is now open and is not allowing calls.  |    46
 DeadLettered | Rejected by per-tenant concurrency limit.            |     2
```

The two `BulkheadRejected` rows, by timestamp - both within 40ms of each other, both before the breaker
had tripped:

```
 event_type          | status       | response_snippet                          | created_at
----------------------+--------------+--------------------------------------------+-------------------------------
 conversation.closed  | DeadLettered | Rejected by per-tenant concurrency limit.  | 2026-08-23 20:52:10.77079+00
 conversation.closed  | DeadLettered | Rejected by per-tenant concurrency limit.  | 2026-08-23 20:52:10.810459+00
```

Followed, ~1.6s later, by a cluster of 20 deliveries within a ~230ms window all short-circuited by the
now-tripped per-endpoint breaker (`MinimumThroughput=2`/`FailureRatio=0.5` - the same aggressive,
already-configured production thresholds `6-06`'s own report used, not a test-only relaxation) - exactly
the sequence `6-06`'s report predicted would happen *if* real concurrency ever reached the bulkhead: a
handful of genuinely concurrent, genuinely hanging HTTP attempts get far enough to exceed the 20-slot
cap before enough of them individually time out to trip the breaker and start short-circuiting
everything else. Full evidence: `6-07-bulkhead-rejected-rows.txt`/`6-07-all-endpoint-deliveries.txt` (this directory).

Chat message latency during the same window (`Ago.Chat.LoadDriver`'s own steady-lane traffic, n=4 -
too few samples for a percentile claim on a shortened run, included for completeness, not as a repeat
of `6-06`'s own isolation claim):

| Path | n | p50 | p95 | max |
|---|---|---|---|---|
| Send → ack | 4 | 94.3 ms | 367.8 ms | 367.8 ms |
| Send → delivered, cross-node | 4 | 155.5 ms | 562.4 ms | 562.4 ms |

Consistent with "not measurably broken," not presented as a fresh isolation proof given the small n and
shared-machine conditions stated above.

## Why this is real evidence the fix works, not a lucky race

`6-06`'s own root-cause finding was structural: a single-flight consumer can have at most ~1-2
deliveries in flight per subscription, *regardless* of burst size or backlog depth - three separate
attempts (25, then 25, then 40 concurrent conversations) against `6-06`'s own unfixed code produced
zero bulkhead rejections, not "a rejection was unlikely," but "a rejection was structurally
impossible" (2 in flight can never exceed a 20-slot cap). This run's first-ever deliberate burst against
the fixed code produced two rejections despite less favourable conditions than `6-06`'s own attempts
(a shared, busy machine; 18 successful conversations instead of 25; a breaker that had already tripped
once on unrelated backlog and had to be given a fresh endpoint to test against at all). The mechanism
this item added - see `ConcurrentWebhookDispatchPumpTests` (`Ago.Chat.Concurrency.Tests`, 3 tests, run 8
times back to back with zero flakes during development) - independently proves, without a broker, that
more than one delivery for distinct partition keys genuinely overlaps in time under this pump, which is
the only way 20+ concurrent attempts against one site's bulkhead could ever occur from a burst of
distinct-conversation events.

## Verdict

**Bulkhead claim: met.** A real `BulkheadRejected`-shaped outcome ("Rejected by per-tenant concurrency
limit.") was observed for the first time, closing the gap `6-06`'s own report left open. The per-tenant
bulkhead's concurrency cap is no longer merely "correct in isolation" (`6-06`'s own careful phrasing) -
it has now been shown to actually gate real concurrent webhook-dispatch traffic for one tenant.

**Not re-claimed here** (unchanged from `6-06`, not this item's own scope): the full latency-isolation
table, the breaker's own open/half-open cycling behaviour (unaffected by this change, and already proven
with 217 dead-lettered deliveries' worth of evidence in `6-06`'s report), and `nfr.md`'s cluster-scale
targets (Stage 7's own job).
