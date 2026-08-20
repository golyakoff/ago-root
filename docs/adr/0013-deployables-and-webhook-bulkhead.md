# ADR-0013: Three deployables, split by failure profile, and outbound webhooks as a bulkhead

- **Status**: Accepted
- **Date**: 2026-08-20
- **Stage**: 6

## Context

The system has three genuinely different workloads. Holding tens of thousands of WebSockets is
latency-sensitive and memory-bound. Background consumption is throughput-bound and restart-tolerant.
Calling a shop's CRM over HTTP is bound by *someone else's* reliability: a receiver that hangs for 30
seconds cannot be fixed, only contained.

There is also a temptation, common in portfolio projects, to split the domain into many services to
have somewhere to demonstrate resilience patterns. That produces distributed transactions and an
operations burden that a reviewer will read as inexperience.

## Decision

Exactly three deployables for AGO Chat, each justified by a distinct failure and load profile:

| Deployable | Scales with | Failure profile |
|---|---|---|
| `Ago.Chat.Api` | concurrent connections | must stay responsive; sheds load, drains on deploy |
| `Ago.Chat.Worker` | queue depth | restart-tolerant, at-least-once, catches up |
| `Ago.Chat.Webhooks` | third-party latency | expected to be slow and failing; must not affect the others |

The domain is **not** split into services. Conversations, presence, assignment and files remain one
module inside these processes (ADR-0003).

Resilience patterns are applied where a boundary genuinely exists (`architecture/resilience.md`):
per-endpoint circuit breaker, per-tenant concurrency cap, layered timeouts, jittered retry, DLQ and a
delivery log in the webhook dispatcher; breaker-with-fallback on Redis; timeouts and retries on
storage and the broker; no breaker on PostgreSQL, because there is no degraded mode for the source
of truth.

## Consequences

- A slow CRM cannot consume resources belonging to the message pipeline - the bulkhead is a process
  boundary, which is the honest form of it.
- Circuit breaker, bulkhead and backoff get demonstrated against a dependency that actually misbehaves,
  which is worth far more in review than the same patterns applied between two of our own services.
- Webhooks bring their own surface: signatures, delivery logs, tenant-visible failures, replay.
- Cost: a third image, a third set of manifests, dashboards and alerts.
- Cost: the outbox and the broker now feed two different consumer families with different SLAs, so
  DLQ handling has to be per-family rather than global.

## Alternatives considered

- **Dispatch webhooks from the Worker** - no new deployable, and one hanging third party degrades
  message persistence. The failure this whole ADR exists to prevent.
- **Full microservices per domain capability** - maximum surface for patterns, at the cost of
  distributed transactions, N deployments to operate solo, and a reviewer concluding the split was
  fashion rather than analysis.
- **A service mesh for retries and breakers** - correct in a large organisation; here it would hide
  the mechanisms that are the point of the project. Named in the README as the production alternative.
