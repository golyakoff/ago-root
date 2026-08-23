# Stage 6 capstone: prove the bulkhead under load, not by configuration reading

- **Stage**: 6
- **Status**: ready
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

- [ ] A real run, with real numbers, published in a short report: chat message latency (p50/p95)
      during the hung-CRM window, compared explicitly against `nfr.md`'s targets.
- [ ] Breaker-open and bulkhead-saturation observed and reported, not merely "should have happened
      per the config."
- [ ] The verdict is stated plainly: met the bar, or did not - and if not, exactly which mechanism
      failed to hold, handed back as a new backlog item rather than silently patched inside this one.

## Open questions

None - this item's job is to measure against already-decided targets (`nfr.md`) and an already-built
system (`6-01`-`6-05`), not to design anything new.
