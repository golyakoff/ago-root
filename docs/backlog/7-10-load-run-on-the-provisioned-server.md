# Run the load scenarios against the real server, and publish what it actually holds

- **Stage**: 7 — filed 2026-08-26, after the VPS existed and Stage 7 did not.
- **Status**: ready
- **Depends on**: `7-04` (the scenarios exist and are runnable), `7-06` (the report format), and the
  public deployment being live — all shipped.

## Goal

`README.md`'s Numbers section stops apologising for a workstation and states what a real, cheap,
externally-hosted server actually holds. Every figure carries the hardware it was measured on.

## Why this is worth doing rather than dropping

Stage 7's numbers are honest and they are small: **all nine scenarios ran at roughly 1–3% of
`nfr.md`'s stated scale**, on one development workstation, and **every p50/p95 target was missed**.
The report says so and the README repeats it.

The temptation is to delete the section, since a missed target reads badly. That would be the wrong
trade twice over. It removes the only evidence in the project that anything was measured at all, and
it removes the one property those numbers do have: they are *true*, and stated against a target
rather than in isolation.

The right move is the opposite. The constraint that produced them — no machine to run against — is
gone. There is a provisioned single-node k3s server carrying the public demo. It is deliberately
cheap, and that is what makes the answer interesting: **"a €N/month box holds X concurrent
connections and Y msg/s"** is a far stronger statement than "we hit 1.5% of target on a laptop",
even if X and Y are also modest. A number with hardware attached can be reasoned about; a number
from an unnamed workstation cannot.

## Scope

- **Re-run `7-04`'s scenarios against the public deployment**, unchanged where possible. A scenario
  that has to change to run there is a finding — record what changed and why.
- **Find the ceiling rather than confirming a target.** The point is not to pass `nfr.md`; on this
  hardware most of it will not be met and that is expected. The deliverable is *where it stops* and
  *what stops it* — connections, ingest rate, or latency, and which resource ran out first.
- **State the hardware in the same breath as every number**: vCPU, RAM, disk class, and the fact that
  it is one node with everything co-resident (Postgres, RabbitMQ, Redis, MinIO and all three hosts
  share it, which is itself part of the answer).
- **Load must be generated from outside the node.** A generator sharing the server's CPU measures the
  generator. If the driving machine's own network becomes the limit, say so rather than reporting the
  number it produced.
- **A report in `load/reports/`**, same shape as `7-06`'s, and a rewritten README Numbers section
  that cites it.
- **Compare against the workstation run** where the scenarios are the same. Two data points on
  different hardware say something neither says alone.

## Out of scope

- **Tuning to make the numbers better.** Measure first. Any tuning that suggests itself is a separate
  item with its own before/after, per CLAUDE.md rule 7.
- **Scaling the server.** The cheapness is the point of the measurement.
- **Chaos scenarios** (`7-05`) — same reasoning, but pod-kill and partition testing against the live
  public demo needs its own decision about acceptable disruption. File separately if wanted.
- Re-running the two correctness bullets Stage 7 could not cover; they are `7-06`'s open items and do
  not become answerable just because the hardware changed.

## Done when

- [ ] Every `7-04` scenario has run against the public deployment, or is recorded as not-run with the
      reason.
- [ ] For connections and for sustained ingest, the report states **the point at which it stopped and
      what ran out** — not merely that a chosen level held.
- [ ] Every published figure names the hardware it was measured on, and the load generator's own
      location is stated.
- [ ] `README.md`'s Numbers section is rewritten against this run, and still states plainly which
      `nfr.md` targets are not met — the honesty of the current section is a feature to keep, not the
      thing being fixed.
- [ ] The report says whether the demo remained usable during the runs, because it is a public URL
      somebody may be looking at.

## Open questions

**Whether to run against the live demo or a second, identical, throwaway node.** Running against the
live one measures the real thing and risks degrading a URL that is on the README; a throwaway costs
money and measures a copy. The item decides and records which, and if it is the live one, it states
when the runs happened so a visitor who saw it slow has an explanation.

**What "the target" even means on this hardware.** `nfr.md`'s numbers were written for a provisioned
cluster, not one cheap node. Reporting a 3% figure against them is arithmetically fine and
communicates little. Consider stating a second, explicitly-labelled expectation for this hardware —
and be careful that it does not quietly become the target.
