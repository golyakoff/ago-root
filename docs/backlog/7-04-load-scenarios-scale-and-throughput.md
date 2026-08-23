# k6: steady ingest, burst, connection storm, reconnect storm, assignment contention, attachment presign

- **Stage**: 7
- **Status**: ready
- **Depends on**: `7-01`, `7-02`, `7-03` — server-side metrics and dashboards to watch live and cite in
  the report, per the `load-test` skill's own "collect from both sides" rule

## Goal

After this, six k6 scenarios exist under `load/scenarios/` proving `nfr.md`'s scale and latency
targets under normal, non-failure-injected operation: steady ingest at 3 000 msg/s, a 10 000 msg/s /
30 s burst, 20 000 concurrent WebSocket connections, a rolling-restart reconnect storm, assignment
contention against a 10 000-deep waiting queue, and attachment presign throughput at 50/s — each with
its own report in `load/reports/`, real numbers against `nfr.md`'s tables, not an assertion that the
targets were probably met.

## Context to read first

The `load-test` skill in full — scenario design rules, the reporting template, the
percentiles-not-averages interpretation section; this item is that skill applied, not reinvented.
`nfr.md`'s Scale targets and Latency targets tables verbatim — the exact numbers every scenario's
success criteria comes from. `runbooks/load-testing.md`'s layout (`load/scenarios/`, `load/lib/`,
`load/reports/`, `load/output/`). `concurrency.md`'s "What we will measure" section (batch-size-vs-
latency curve, channel saturation, assignment contention under a waiting-queue backlog) and its
assignment section for what "10 000 waiting" contention actually exercises
(`OperatorCapacityStore.TryClaimAsync`'s row-count-0 retry path). `realtime.md`'s reconnect/resume
protocol and `3-06`'s own drain proof — what "reconnect storm" is testing (zero acknowledged-but-lost
messages through a rolling restart), already proven once at small scale in `3-06`; this item proves it
at connection-storm scale. `file-storage.md` for the presign path's shape — bytes never touch the API,
so this scenario only exercises presign + verify, matching `nfr.md`'s own "Presign + verify path only"
note.

## Scope

- `load/lib/`: shared helpers — visitor/operator auth token minting, a WebSocket client wrapper for
  k6, tenant/site/conversation data seeding (extending `1-05`'s `create-demo-tenant.sh` approach to the
  scale this item needs, or adding a bulk-seed variant — whichever is less invasive to the existing
  script).
- Six `load/scenarios/*.js` k6 scripts, each stating up front (per the skill) the question it answers,
  the load shape (ramp/plateau/duration long enough for GC and connection-pool steady state), the
  topology it ran against, and its success criteria taken directly from `nfr.md`:
  1. **Steady ingest** — 3 000 msg/s sustained, plateau long enough to be a real measurement, not a
     warm-up average.
  2. **Burst ingest** — 10 000 msg/s for 30 s, watching channel backpressure (not hiding it) via
     `7-02`'s channel-occupancy metric.
  3. **Connection storm** — ramp to 20 000 concurrent WebSocket connections, watching per-connection
     memory and GC pressure (`nfr.md`'s own stated reason for this target).
  4. **Reconnect storm** — steady traffic plus a rolling restart of `Ago.Chat.Api` mid-run, asserting
     zero acknowledged-but-lost messages and measuring reconnect latency.
  5. **Assignment contention** — seed a 10 000-deep waiting queue, measure waiting → assigned latency
     against `nfr.md`'s table, assert zero operators ever exceed capacity.
  6. **Attachment presign throughput** — 50 presign + verify operations/s, per `nfr.md`'s target.
- One `load/reports/<date>-<scenario>.md` per scenario, filled from the skill's own template: date,
  commit, hardware, topology, results (p50/p95/p99, throughput, error rate), server-side observations
  pulled from `7-03`'s dashboards, and what was tuned (batch size, channel capacity, pipeline worker
  count — `concurrency.md`'s own named knobs) if anything needed changing to hit the target.

## Out of scope

- Failure-injected scenarios (cold-cache stampede, pod-kill, hanging webhook endpoint) — `7-05`, a
  different kind of question (correctness/isolation under a broken dependency, not throughput under
  normal operation).
- The synthesizing whole-stage report — `7-06`.
- Tuning past what's needed to hit `nfr.md`'s stated targets — if a target is missed, the report says
  so and hands off a follow-up item; this item does not chase a target past what the existing
  pipeline's config knobs can reasonably do in one MR.

## Done when

- [ ] All six scenarios run against the real Kubernetes local cluster (`k8s-local.md` topology: 3 Api
      replicas, 2 Worker replicas, per `nfr.md`'s own stated topology) — compose-loop numbers are not
      comparable and are not what gets reported (`load-test` skill's own rule).
- [ ] Six reports exist in `load/reports/`, each with date, commit, hardware, topology, results,
      server-side observations, and an explicit met/missed verdict per `nfr.md` target — a missed
      target stays in the report with an explanation, never dropped.
- [ ] `load/output/` raw k6 output is gitignored; only the reports are committed.

## Open questions

None — every scenario's success criteria already exists in `nfr.md`; nothing here is a design choice
left open.
