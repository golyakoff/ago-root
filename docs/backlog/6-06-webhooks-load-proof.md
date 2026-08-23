# Stage 6 capstone: prove the bulkhead under load, not by configuration reading

- **Stage**: 6
- **Status**: done (partial pass, honestly reported - see Done-when)
- **Depends on**: `6-01` through `6-05` - this item adds no new product code, only the proof

## Goal

`roadmap.md`'s own Stage 6 "Done when" is answered with a number, not an assertion: with `6-04`'s fake
CRM set to hang 30 seconds on every call, message ingest and delivery stay inside `nfr.md`'s targets.
This is a smaller, targeted rehearsal of what Stage 7 does exhaustively later - one specific claim
("the bulkhead holds"), proven now, because Stage 6 is the stage that made the claim.

## Context to read first

`nfr.md`'s latency targets table, specifically "Send -> delivered to a recipient on another node" -
the metric this item must show is *unaffected* by a hung webhook endpoint, since message delivery and
webhook delivery are meant to be fully isolated (`adr/0013`). `resilience.md`'s "How this is proven"
section - already names this exact approach ("Stage 7 tests each one... the assertion is always about
the rest of the system staying within its latency targets while the dependency is broken"), this item
is that same discipline applied narrowly, ahead of Stage 7's own fuller suite. `CLAUDE.md`: "measure
or stay silent" - this item either produces a real number in a report, or it does not claim the bar
was met.

## Scope

- A `load/` scenario (whatever tool this project's existing `load/` directory already uses - check
  before introducing a second one): sustained message traffic at a modest, honestly-labelled rate
  (not `nfr.md`'s full 3 000 msg/s target - that is Stage 7's own job with the full cluster topology;
  this item's point is the *isolation* claim, provable at a much smaller, cheaper scale) while every
  registered webhook endpoint is `6-04`'s fake CRM set to `hangs` (30s) for the whole run.
- Measure message send-to-ack and send-to-delivered latency during the run, compare against `nfr.md`'s
  targets - report the real numbers, not a pass/fail without them.
- Observe and record: the per-endpoint breaker opens (not stays half-open forever, not stays closed
  hammering a dead endpoint), the bulkhead's concurrency cap is actually hit and holds (queued/rejected
  webhook work, not queued/rejected chat traffic), and `Ago.Chat.Api`/`Ago.Chat.Worker`'s own resource
  usage stays flat - a leaking thread/connection pool from the webhook side would eventually surface
  as slower chat traffic even with correct isolation *in principle*.
- A short report (markdown, alongside the `load/` scenario itself) with the real numbers and a plain
  verdict - matches this project's own `CLAUDE.md` rule against inventing figures elsewhere.

## Out of scope

- The full `nfr.md` scale targets (20 000 connections, 3 000 msg/s sustained) - Stage 7's own, much
  bigger undertaking with a genuinely provisioned cluster, not this item's cheaper, targeted rehearsal.
- Any new resilience mechanism discovered as missing during this item - if the bulkhead does *not*
  hold, that is a real bug in `6-05`'s own implementation to fix there (or a new backlog item, if
  large), not something this item's own scope stretches to also repair.

## Done when

- [x] A real run, with real numbers, published in a short report: chat message latency (p50/p95)
      during the hung-CRM window, compared explicitly against `nfr.md`'s targets. Isolation held - every
      hung-CRM-window number was *lower* than baseline, not higher (read as flat, warm-up artifact, not
      "faster because of the outage"). `nfr.md`'s own p50/p95 cluster-scale targets were missed on this
      dev-laptop topology, as expected and stated up front - that measurement is Stage 7's job.
- [x] Breaker-open and bulkhead-saturation observed and reported, not merely "should have happened
      per the config." Breaker: real evidence, 217 dead-lettered deliveries, opens fast and correctly
      cycles open/half-open for the whole run. Bulkhead: **not observed** despite three deliberate burst
      attempts - see verdict below.
- [x] The verdict is stated plainly: met the bar, or did not - and if not, exactly which mechanism
      failed to hold, handed back as a new backlog item rather than silently patched inside this one.
      **Isolation: met. Breaker: met, with real evidence. Bulkhead: not met** - root-caused to
      `Ago.Platform.Messaging.RabbitMq.RabbitMqEventConsumer` awaiting each delivery handler inline,
      capping real per-tenant webhook concurrency at ~1-2 regardless of burst size, well short of the
      configured `MaxConcurrency=4`/`MaxQueuedActions=16`. Not a bug in the Polly bulkhead policy itself
      - the caller never offers it enough concurrent work to gate. New backlog item recommended: give
      the webhook-dispatch consumers genuine concurrent processing (bounded worker pool draining a
      local channel, matching `4-05`'s existing in-process pipeline shape), then re-run this same burst
      to observe a real rejection.

## Shipped in

`feat/6-06-webhooks-load-proof` (`ago-chat`) - `tests/Ago.Chat.LoadDriver` (real SignalR client traffic
driver) and `tests/Ago.Chat.WebhookDispatchRunner` (real dispatch code minus the delivery-time SSRF
recheck, needed to target a fake CRM on a private dev-box address from a dev laptop - documented in the
report). Also fixed a pre-existing `Directory.Packages.props` staleness (`Ago.Platform.*` pinned to
0.11.0 against `ago-platform`'s actual current 0.12.0) that was blocking every build in the repo, not
just this item's. Full report: `load/reports/2026-08-23-webhooks-load-proof.md` (this repo). Also
surfaced two unrelated real findings, each recommended as its own future backlog item rather than
patched here: `DbUpdateConcurrencyException` surfacing as a raw 500 instead of a clean 409 on
conversation close/assign under concurrent load (~5% of calls in this run), and an unexplained
4,129-message backlog on a consumer-less `ConversationAssignedToOperator` queue, unrelated to this
item's own consumers, worth checking separately.

## Open questions

None - this item's job is to measure against already-decided targets (`nfr.md`) and an already-built
system (`6-01`-`6-05`), not to design anything new.
