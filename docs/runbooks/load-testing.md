# Runbook: load testing

> **Status: skeleton.** Filled in at Stage 7, when the scenarios exist and have been run.

Rules of conduct live in the `load-test` skill; targets live in `docs/architecture/nfr.md`. This file
is the mechanics.

## Layout

```
load/
  scenarios/        k6 scripts, one per question being asked
  lib/              shared helpers (auth, ws client, data generation)
  reports/          <date>-<scenario>.md — committed, and the only source of performance numbers
  output/           raw k6 output — gitignored
```

## Running

1. Bring up the cluster (`k8s-local.md`) at the topology the report will state.
2. Seed a realistic tenant: sites, operators, conversations, message history.
3. Warm up, then measure. Discard the warm-up window explicitly.
4. Capture both k6 client-side results and server-side metrics for the same window.

## Reporting

Copy the template from the `load-test` skill. Every report states date, commit, hardware, topology,
scenario, results, server-side observations, what was tuned, and what regressed. Missed targets stay
in the report with an explanation.

## Interpreting

Percentiles, never averages. A p99 far above p95 means queueing, GC, or a lock convoy — name which
and prove it with server metrics. Latency climbing while throughput stays flat means a bounded queue
somewhere is full; find it. Every queue in this system is bounded and instrumented precisely so that
this question has an answer.
