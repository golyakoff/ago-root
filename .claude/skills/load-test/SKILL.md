---
name: load-test
description: Design, run and report a load test for AGO Platform with k6 - scenarios, method, and the honest reporting rules. Use before making any performance claim, when tuning batch sizes or worker counts, or when producing the Stage 7 report.
---

# Load testing

Authoritative sources: `docs/architecture/nfr.md`, `docs/runbooks/load-testing.md`.

## The rule that governs everything here

**No performance number exists until it is measured on stated hardware and written into
`load/reports/`.** Do not estimate, do not extrapolate, do not repeat a number from a blog post about
someone else's system. If asked how fast something is and no report exists, the answer is "not
measured yet".

## Designing a scenario

Each scenario states, before it runs:

- What question it answers ("does batch size 500 beat 100 at 3k msg/s?").
- The load shape: ramp, plateau, duration. Plateaus long enough for GC and connection pools to reach
  steady state - a 30-second run measures warm-up.
- The topology under test: replica counts, resource limits, and whether it ran on the cluster or in
  compose (they are not comparable, and mixing them invalidates the report).
- Success criteria taken from `nfr.md`, chosen up front. Deciding what "good" means after seeing the
  numbers is how projects fool themselves.

## Scenarios the project needs

Steady ingest; burst ingest; connection storm (mass connect); reconnect storm (rolling restart under
load); cold-cache stampede; assignment contention with a deep waiting queue; pod kill mid-load
(correctness, not latency); attachment presign throughput.

## Running

- Warm up, then measure. Discard the warm-up window explicitly rather than averaging it in.
- Change one variable at a time. Two changes and one number means you learned nothing.
- Collect from both sides: k6's client-side latency **and** server metrics (queue depth, batch size,
  outbox lag, pool usage, GC). The interesting finding is usually the mismatch between them.
- Watch for the load generator being the bottleneck - if client CPU is saturated, the numbers are
  about k6, not about the system.

## Reporting

Every report in `load/reports/<date>-<scenario>.md` contains: date, commit, hardware, topology,
scenario, results (p50/p95/p99 + throughput + error rate), server-side observations, the conclusion,
and **what was tuned and what regressed**. Missed targets stay in the report with an explanation.
A report that only contains wins is not a measurement, it is a brochure - and a reviewer will notice.

## Interpreting

- Percentiles, never averages. An average latency in a system with queues is a number that describes
  nothing that happened to anyone.
- A p99 far above p95 usually means queueing, GC pauses, or lock convoy - name which, then prove it
  with server-side metrics.
- Latency rising while throughput stays flat means saturation upstream; find the bounded queue that
  is full, which is exactly why every queue in this system is bounded and instrumented.
