# Stage 7 capstone: nfr.md, answered with numbers

- **Stage**: 7
- **Status**: ready
- **Depends on**: `7-01` through `7-05` — this item adds no new instrumentation or scenarios, only the
  synthesis

## Goal

`roadmap.md`'s own Stage 7 "Done when" is satisfied: one report exists in `load/reports/` that walks
`nfr.md` target by target (scale, latency, correctness-under-stress, resource budgets, observability)
and states, for each, the real measured number and which of `7-04`/`7-05`'s nine scenario reports it
came from — a reviewer can open this one document and see whether the project's own numeric claims
hold, without cross-referencing nine files by hand. Any target that was missed is explained, not
dropped.

## Context to read first

`nfr.md` in full — this report's own table of contents is `nfr.md`'s own section headings. Every
`load/reports/*.md` file `7-04` and `7-05` produced. The `load-test` skill's Reporting section ("a
report that only contains wins is not a measurement, it is a brochure — and a reviewer will notice").
`6-06` for the tone and honesty bar of a capstone report at smaller scale — this item is the same
discipline, applied system-wide.

## Scope

- One document, `load/reports/<date>-stage-7-summary.md`:
  - A table mirroring `nfr.md`'s Scale targets table (target vs. measured, scenario cited).
  - The same for Latency targets (p50/p95/p99 columns, per path).
  - A plain pass/fail list for each Correctness under stress bullet.
  - Resource-budget numbers actually observed (Api/Worker pod memory/CPU at target load, read from
    `7-03`'s dashboards) against the stated budgets.
  - A short paragraph on Availability behaviour — which dependency failure degrades, which rejects,
    matching what `7-05` actually observed, not what `realtime.md` predicted in advance.
- A "what was tuned" section aggregating every config knob any of `7-04`/`7-05`'s reports changed
  (batch size, channel capacity, pipeline worker count, etc.), so a reader sees the full tuning story
  in one place instead of assembled from nine reports.
- A short, honest "what regressed or fell short" section: if a target was missed, name it, name the
  suspect (per the skill's own "a p99 far above p95 usually means queueing, GC pauses, or a lock
  convoy — name which, then prove it with server-side metrics"), and link the follow-up backlog item if
  one was created.
- `roadmap.md`'s Stage 7 section: no prose change expected, but if any deliverable line turns out not
  to match what was actually built (a scenario renamed, a metric consolidated), correct it here, in the
  same change — `CLAUDE.md`'s "docs are part of the deliverable" rule.

## Out of scope

- Running any new load test — this item synthesizes `7-04`/`7-05`'s existing reports. If a gap is found
  (a target with no scenario that measured it), that gap is reported honestly and handed back as a new
  backlog item, not quietly filled in here by running something ad hoc outside the already-reviewed
  scenario set.
- Fixing anything the numbers reveal — same rule as `7-05`'s own Out of scope, applied one level up.

## Done when

- [ ] `load/reports/<date>-stage-7-summary.md` exists, covers every table/bullet in `nfr.md`, and every
      number in it traces to a specific `load/reports/*.md` file from `7-04`/`7-05` — a citation, not a
      restated assertion.
- [ ] Every missed target is named as missed, with a stated suspect and (where warranted) a linked
      follow-up backlog item — none are quietly dropped or reworded into a pass.
- [ ] `roadmap.md`'s Stage 7 section double-checked against what was actually built; corrected in this
      same change if it drifted, left untouched if it didn't.

## Open questions

None.
