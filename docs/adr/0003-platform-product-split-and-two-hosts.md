# ADR-0003: Platform/product split, modular monolith, two hosts

- **Status**: Accepted — item 3 (two hosts) amended by `adr/0013`
- **Date**: 2026-08-20
- **Stage**: 0

## Context

AGO Chat is the first product; AGO Ads is planned. Connection-holding must scale independently from
background work. The whole thing must stay operable by one person on a laptop cluster.

## Decision

1. Split code into `Ago.Platform.*` (no domain knowledge) and `Ago.<Product>.*`. Products depend on
   the platform; the platform never references a product - enforced by an arch test.
2. Keep it a **modular monolith**: one solution, shared assemblies, no service-to-service HTTP.
3. Deploy **two hosts**: `Ago.Chat.Api` (connections, commands, queries) and
   `Ago.Chat.Worker` (consumers, outbox dispatch, assignment, jobs). Products plug into both
   through `IProductModule`.
4. The hosts never call each other synchronously - the broker and the database are the only paths.

## Consequences

- Independent scaling and restarts without distributed transactions or service discovery.
- Adding AGO Ads is additive: its own repository and hosts consuming the same platform packages,
  with no platform edits.
- A reviewer sees the microservice trade-off understood rather than cargo-culted.
- Cost: a platform boundary attracts premature abstraction. Mitigation: the qualifying rules in
  `clean-architecture.md` - ambiguous code stays in the product until a second consumer exists.
- Cost: both hosts ship the same binaries, so any change redeploys everything.

## Alternatives considered

- **Microservices per capability** - the "impressive" choice and dishonest at this size: the effort
  would go into plumbing instead of the concurrency and data work the CV needs to show.
- **A single host doing everything** - simplest, but consumer load and connection load then share a
  process and the interesting scaling story disappears.
