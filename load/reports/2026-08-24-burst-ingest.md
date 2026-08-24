# 7-04: burst ingest (reduced scale)

**Date**: 2026-08-24
**Commits**: `ago-chat` `f9c090dd41b353c16d9e2684874a1f6616676b5e` (`main`), `ago-root`
`04ecf0e974c0f9e0f519fb8ded952e2db1885226` (`main`, branch point for `docs/7-04-load-scenarios`)
**Hardware**: one Windows 11 development workstation - 11th Gen Intel Core i7-11800H, 8 cores / 16
logical processors, 63.8 GB RAM. **Not** the provisioned cluster `nfr.md` targets.

## Scale disclosure - read this before the numbers below

**Deliberately, explicitly NOT `nfr.md`'s own target** - the same reduced-scale, unsupervised-overnight
decision covering all six of this item's scenarios (see `2026-08-24-steady-ingest.md` for the full
reasoning, not repeated here) and the same precedent `6-06` already established.

| | `nfr.md` target | This run | Scale factor |
|---|---|---|---|
| Peak burst ingest | 10 000 msg/s for 30 s | ~94 msg/s observed (133 msg/s offered), 30 s | **~0.9%** |

This proves the scenario design and reporting method, and produces one honest small-scale data
point. **It does not claim `nfr.md`'s 10 000 msg/s burst target would be met, or approached, at full
scale** - channel backpressure behaviour at 0.9% of target load is not evidence about behaviour at
100%. What a real run needs: the provisioned `k8s-local.md` cluster, k6 (or an equivalent generator)
actually capable of offering 10 000 msg/s without becoming its own bottleneck, and `7-02`'s own
channel-occupancy metric scraped live during the burst (this run could not use it - see below).

## Topology and tooling deviations

Same as `2026-08-24-steady-ingest.md`: compose loop (not k8s - a concurrent, unrelated session already
had the k8s cluster and the default-port `Api` instance, `5009`, in use), two `Api` instances on
non-default ports (`5109` operator-node, `5110` visitor-node, one fixed `Auth__SigningKey`), one
`Worker`, real `.NET SignalR client` driver (`Ago.Chat.LoadDriver`, `LOADDRIVER_SCENARIO=burst-ingest`)
instead of k6, `MessageSendRateLimit`/`VisitorSessionRateLimit` per-site budgets raised via environment
variables for this session only.

**No live channel-occupancy dashboard for this run.** `7-02`'s own metric
(`ago_chat_pipeline_channel_occupancy`, confirmed present in Prometheus's metric catalogue) exists,
but this compose loop's Prometheus is pre-configured to scrape only the unrelated default-port `5009`
instance (see the steady-ingest report's own note) - not this run's `5109`/`5110` instances - and
neither `Api` process exposes a `/metrics` endpoint of its own outside that scrape path (`curl` to
`/metrics` on both ports returned `404`). Wiring a second Prometheus scrape target meant editing
`ago-deploy`'s shared compose config while another session might depend on the existing one - out of
scope for this run. This is a real, stated methodology gap, not a silently skipped observation: the
backpressure finding below is named and explained from architecture and client-side timing, not
proven with a captured channel-depth number.

## What this scenario answers

When offered load jumps well above steady state for a short window, does the pipeline show
backpressure honestly (rising latency, a bounded queue filling) rather than silently dropping or
timing out? Does ack latency (the batch-writer path) behave differently from cross-node delivery
latency (the outbox-dispatch path) under the same burst - the "interesting mismatch" the `load-test`
skill's own Interpreting section calls out?

## Load shape

One pool of 40 lanes, held open for the whole run (connection count constant - only offered load
changes, isolating burst effects from connection-scale effects, which `connection-storm`'s own report
covers separately). Three phases, same lanes throughout: 30 s baseline (each lane every 3 s, ~13
msg/s aggregate), 30 s burst (each lane every 300 ms, ~133 msg/s aggregate), 30 s cooldown (back to
the baseline rate, to see whether the system recovers or the burst leaves a lasting scar). Total wall
clock 90 s.

## Results

Source: `RunBurstIngestAsync`, `tests/Ago.Chat.LoadDriver/Program.cs` (this branch, `ago-chat`). Raw
CSV: `load/output/raw/burst-ingest.csv` (gitignored).

| Path | Phase | n | p50 | p95 | p99 | max |
|---|---|---|---|---|---|---|
| Send -> ack | baseline | 400 | 84.6 ms | 101.6 ms | 107.3 ms | 108.6 ms |
| Send -> ack | **burst** | **2 809** | **100.5 ms** | **117.1 ms** | **133.5 ms** | 142.8 ms |
| Send -> ack | cooldown | 400 | 111.4 ms | 145.1 ms | 148.1 ms | 148.1 ms |
| Send -> delivered, cross-node | baseline | 400 | 127.4 ms | 189.8 ms | 207.6 ms | 214.0 ms |
| Send -> delivered, cross-node | **burst** | **2 699** | **566.9 ms** | **1 093.5 ms** | **1 161.2 ms** | 1 270.2 ms |
| Send -> delivered, cross-node | cooldown | 510 | 271.3 ms | 1 237.0 ms | 1 270.0 ms | 1 324.3 ms |

**Observed burst throughput**: 2 809 acked sends over the 30 s burst window = **93.6 msg/s**, against
~133 msg/s offered (~70% of offered - the pipeline slowed sends rather than silently dropping them:
**zero errors** across the whole 3 609-send run).

## Interpretation - the mismatch the skill asks for

**Ack latency stayed close to baseline through the burst** (p50 100.5 ms vs 84.6 ms baseline, p95
117.1 ms vs 101.6 ms) - the batch writer absorbs a ~10x offered-rate jump with only a modest latency
increase, consistent with `concurrency.md`'s own claim that batching is "the single highest-leverage
throughput mechanism in the project."

**Cross-node delivery latency did not stay close to baseline - it went up roughly 4-6x** (p50 566.9 ms
vs 127.4 ms baseline, p95 1 093.5 ms vs 189.8 ms, p99 1 161.2 ms vs 207.6 ms) and **stayed elevated
into the cooldown window** (p95/p99 still above 1 200 ms after the burst ended, though n is smaller
there and includes messages queued during the tail of the burst). This is exactly `nfr.md`'s own
predicted first suspect: "the end-to-end number carries one broker hop plus the outbox dispatch
interval by design... if it misses, the dispatcher's poll-with-notify latency is the first suspect,
not the database." `Ago.Chat.Worker`'s `appsettings.Development.json` sets
`OutboxDispatcher:PollInterval` to `00:00:05` - a burst of ~4 000 outbox rows in 30 s landing against a
5-second poll-with-notify dispatcher is architecturally exactly where a queueing delay would show up,
and the shape of the numbers (ack flat, cross-node delivery multiplying, both recovering only slowly)
matches a downstream queue filling rather than the batch-writer or Postgres struggling. This is named
from architecture and the observed client-side timing, **not proven with a captured outbox-lag or
channel-occupancy number** (see "no live dashboard" above) - a real follow-up run with the metric
wired up would confirm or correct this reading.

Against `nfr.md`'s targets (send -> ack: 15/50/150 ms; send -> delivered cross-node: 40/120/300 ms):
every burst-phase number misses, expected at ~1% of the target burst rate on unbatched dev hardware -
**not a claim these targets would be met, or missed the same way, at full scale.**

## Server-side observations

Same "no live dashboard for this run's own instances" gap as the channel-occupancy note above. No
continuous process-resource sampling for this scenario (reserved for `connection-storm`); a spot
check immediately after the run showed no elevated memory versus the steady-ingest run's own numbers
(`Api` visitor-node ~250-310 MB working set across this session, not scenario-isolated further).

## What was tuned

Same rate-limit environment-variable overrides as `steady-ingest`, carried over (both scenarios ran
against the same long-lived `Api`/`Worker` processes in one session). No pipeline batch-size,
channel-capacity, or `OutboxDispatcher:PollInterval` was changed for this run - the delivery-latency
finding above is about *default* configuration under burst, not a tuning result.

## What a real, full-scale run still needs

The provisioned k8s cluster, a generator actually capable of 10 000 msg/s for 30 s without becoming
the bottleneck, and - specifically for this scenario - a working live channel-occupancy and
outbox-lag dashboard scraping the actual instances under test, so the cross-node delivery-latency
finding above can be confirmed against a real queue-depth number instead of inferred from
architecture and client-side timing alone.
