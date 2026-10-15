# ADR-0193: A tail-sampling OTel Collector sits in front of Jaeger

- **Status**: Accepted
- **Date**: 2026-10-15
- **Stage**: 26

Supersedes ADR-0025 (its `Status` line changed with this ADR, and only that line).

## Context

`adr/0025` sent every host's OTLP straight to Jaeger and named its own exit: "revisit if a second
telemetry backend or **centralized sampling** becomes real". The second half is now real.

- Every request is recorded (the SDK default, `ParentBased(AlwaysOn)`). Jaeger's in-memory store is
  bounded at 10000 traces (`adr/0057`), which at probe-dominated traffic is about an hour - so a trace
  an operator wants may already be gone, and a bigger store is a bigger bill for traces nobody opens.
- `26-331` removed the probe and scrape traces; `26-336` added `Otel:Sampling:Ratio` (recorded in
  `adr/0194`; the `ago-platform` changelog calls it `26-332`, a number `ago-root#1897` already held). A ratio is a
  *head* decision: made when the root span starts, before it is known whether the request failed or
  was slow. Lowering it lowers the chance of keeping exactly the traces worth keeping.
- A trace crosses Api, Worker and Webhooks (outbox → broker → consumer). Deciding after the fact needs
  one place that sees all of it.

## Decision

One OpenTelemetry Collector (contrib distribution) runs as a **single-replica gateway** between the
hosts and Jaeger. Hosts export OTLP to `otel-collector:4317`; the collector forwards to Jaeger.

Its `tail_sampling` processor keeps a trace if **any** policy matches: it contains an error span, it
took longer than 500 ms, or it falls in a 10 % baseline. Hosts keep `Otel:Sampling:Ratio = 1` while the
collector is in the path - a host that drops at the root has already discarded the error the collector
exists to keep. The config is `ago-deploy/k8s/base/otel-collector-config.yml`, read by both the compose
loop and the cluster.

500 ms is the largest p95 in `architecture/nfr.md`'s latency table, so anything above it is outside
every stated target. The 500 ms, the 10 % and the `decision_wait` are **unmeasured starting points**;
`load/` has to put numbers on them before they are called tuned (CLAUDE.md rule 7).

## Consequences

- **Errors and slow requests survive, the rest is cut.** Jaeger's ring now holds mostly traces someone
  would open, so the same 10000 spans a much longer window.
- **A new deployable and a new failure mode.** If the collector is down, hosts' exporters drop spans
  (the OTLP exporter's own queue, not a request path - no user-visible failure). That is a regression
  from `adr/0025`'s "no extra hop's own failure mode".
- **It must stay one replica.** Tail sampling is only correct when all spans of a trace reach the same
  instance; a second replica splits traces. Scaling out needs a trace-id load-balancing exporter in
  front, not done here.
- **Late spans can split a trace.** A span arriving after `decision_wait` (10 s) is judged on its own,
  so one slow outbox hop can leave a kept half and a dropped half. Unmeasured; the item's load run is
  where this gets a number.
- **Memory is held per undecided trace**, bounded by `memory_limiter` under a 512Mi pod limit.
- **A second place that sees every span** - the redaction rule in `personal-data.md` (Traces row) still
  holds because hosts redact before export, but the collector is now in that data path and any future
  processor added to it must not reintroduce what `16-05` removed.
- **Metrics are untouched**: Prometheus still scrapes each host.

## Alternatives considered

- **Keep direct export and lower `Otel:Sampling:Ratio`.** The pragmatic default, and what most teams
  start with. Lost because it throws away errors in proportion to everything else; the point of the
  change is the traces head sampling cannot choose.
- **A per-host sidecar collector.** Same tail-sampling processor, no shared bottleneck. Lost because a
  sidecar sees only its own host's spans; a trace that crosses Api and Worker is judged in two places.
- **Jaeger's own remote/adaptive sampling.** Still a head decision, so it cannot select on outcome.
- **A different backend with built-in tail sampling (Tempo, a vendor).** Out of proportion for a demo
  cluster; the collector is also what makes a later backend swap a config change (`adr/0025`'s
  second trigger), so this does not close that door.
