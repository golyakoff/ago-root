# ADR-0193: Health probes are not traced, and trace volume is controlled by a head-sampling ratio

- **Status**: Accepted
- **Date**: 2026-10-15
- **Stage**: 26

## Context

`adr/0057` measured that Jaeger's in-memory ring of 10000 traces turned over in about an hour on a
quiet host, and that the volume was dominated by Kubernetes liveness/readiness probes and Prometheus
scrapes. A trace of `GET /healthz` answers no question anyone asks; it only evicts the traces that
would. `0057` bounded retention by memory; it did not address what fills the bound.

## Decision

1. **`/healthz*` and `/metrics` are never traced.** Dropped in the ASP.NET Core instrumentation's
   filter, matched by path segment. There is **no configuration key**: nobody has asked for probe traces,
   and an option nobody has asked for is a branch to test and document. Request *metrics* still count them.
2. **`Otel:Sampling:Ratio`** (0..1, default `1`) sets head sampling for new root traces, as
   `ParentBased(TraceIdRatioBased)`. A request carrying a `traceparent` keeps its parent's decision, so a
   trace is never recorded in half the services it crosses. Out-of-range values fail startup.
3. **The default stays `1`.** No host is asked to sample until a measured volume problem says so.

## Consequences

**Positive.** The ring holds real work for far longer than an hour on the same host; no behaviour change
for a host that sets nothing beyond the probe filter.

**Negative.**

- Head sampling decides before the outcome is known, so a ratio below `1` can drop the one slow or failing
  request. Preferring errors needs tail sampling, which needs a collector this project does not run.
- A probe that is itself slow or failing leaves no trace; its signal is the metric and the probe result
  in the kubelet's events.
- Both are in `Ago.Platform.*` `0.21.0`, so a host only gets them by taking that version (`26-337`).

## Alternatives considered

- **A `Otel:Tracing:IgnorePaths` list.** Rejected: configurable noise filtering is a general feature
  with no second user. Two fixed paths cost less than the option.
- **Sampling probes at a low ratio instead of dropping them.** Rejected: the question a probe trace could
  answer is "was the probe slow", which the probe's own duration metric already answers.
- **Tail sampling in an OpenTelemetry Collector.** Rejected for now: it would solve the error-preference
  gap, but adds a component to run for a volume problem that the two steps above already remove.
