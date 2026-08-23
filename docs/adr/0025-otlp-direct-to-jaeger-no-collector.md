# ADR-0025: Direct OTLP export to Jaeger, no collector

- **Status**: Accepted
- **Date**: 2026-08-24
- **Stage**: 7

## Context

`7-01` wires each host's OTLP exporter. The exporter can either send spans straight to Jaeger's own
OTLP receiver, or through an OTel Collector sitting in between as a separate deployable.

## Decision

Each host exports OTLP directly to Jaeger (`Otel:Exporter:Endpoint`, deployed in `7-03`). No
collector. `resilience.md`'s own "no service mesh, keep mechanisms visible" instinct applies
identically here: a collector earns its place once there is more than one telemetry backend to fan
out to, or a cross-host sampling decision to centralize, and there is neither today.

## Consequences

Simpler topology: no extra deployable, no extra hop's own failure mode, no shared bottleneck between
every host's exporter. The cost: no batching/backpressure decoupling between a host and Jaeger beyond
what the OTLP exporter itself does, and no single point to add tail-based sampling or fan out to a
second backend later without revisiting every host's own config.

## Alternatives considered

- **OTel Collector (agent or gateway).** Rejected for now — no second backend exists to justify it,
  the same reasoning `resilience.md` already gives for not adopting a service mesh. Revisit if a
  second telemetry backend or centralized sampling becomes real.
