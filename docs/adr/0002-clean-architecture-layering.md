# ADR-0002: Clean Architecture layering and the dependency rule

- **Status**: Accepted
- **Date**: 2026-08-20
- **Stage**: 0

## Context

The project must demonstrate architectural competence, and must let PostgreSQL become MySQL and
RabbitMQ become Kafka without touching business logic (proven in Stage 9). Most tests must run
without infrastructure.

## Decision

Four layers - Domain, Application, Infrastructure, Hosts - with source dependencies pointing inwards
only. Ports are declared by their consumer and implemented further out. The rule is enforced
mechanically by `Ago.Chat.Architecture.Tests`, not by review discipline. The "what goes where" table lives
in `docs/architecture/clean-architecture.md`.

## Consequences

- The Stage 9 provider swap becomes a configuration change - the proof that the design is real.
- Domain and Application tests need no containers, so the fast suite stays fast.
- Cost: more projects, more indirection, and a genuine risk of ceremony for its own sake. Mitigated
  by ADR-0003 (one deployable pair, not microservices) and by recording deliberate deviations rather
  than pretending to purity.

## Alternatives considered

- **Layered n-tier over a shared EF model** - the classic, and the reason the provider swap would be
  impossible: business logic would reference persistence entities directly.
- **Vertical slices with no layer rule** - excellent for small feature-driven apps; it would remove
  the exact thing this project is meant to demonstrate.
- **Hexagonal / ports and adapters** - the same content under different names. "Clean Architecture"
  is the vocabulary reviewers expect, so we use it.
