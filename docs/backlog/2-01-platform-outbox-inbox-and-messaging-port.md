# Platform: outbox/inbox persistence plumbing and the messaging port

- **Stage**: 2
- **Status**: done - `Ago.Platform.Abstractions` and `Ago.Platform.Persistence.Postgres` build, pack
  (`dotnet pack Ago.Platform.slnx`, both `.nupkg`s produced alongside `Kernel`/`Hosting`), and are
  proven against a real Testcontainers Postgres, not a mock: 6/6 `Ago.Platform.Integration.Tests`
  green, including same-transaction-or-neither for the outbox writer (a forced `DbUpdateException` on
  the unrelated change rolls the outbox row back too) and duplicate-delivery-returns-false for the
  inbox checker (the second delivery's own staged work is discarded together with the duplicate
  insert). `Ago.Platform.Tests` 11/11, `Ago.Platform.Architecture.Tests` 2/2 including the extended
  "no `Ago.Chat.*` reference" rule now covering both new assemblies. `dotnet format --verify-no-changes`
  clean on every file this item touched - two pre-existing, untouched files
  (`Ago.Platform.Hosting/SystemClock.cs`, `Ago.Platform.Tests/SystemClockTests.cs`) fail it with
  `ENDOFLINE` on this machine due to a local CRLF checkout artifact unrelated to this change; worth a
  `.gitattributes` fix in its own small change, not folded in here.
- **Depends on**: nothing (builds on Stage 0's `Ago.Platform.Kernel`/`Hosting`, not on any Stage 1 chat code)

## Goal

`Ago.Platform` gains its first two projects with real behaviour beyond `Kernel`/`Hosting`:
`Ago.Platform.Abstractions` (the technical ports every product needs) and
`Ago.Platform.Persistence.Postgres` (a generic, product-agnostic outbox/inbox implementation any
`DbContext` can adopt). After this item, nothing in `Ago.Chat.*` has been touched yet - this is purely
`ago-platform` proving the mechanism in isolation, publishable and testable on its own.

## Context to read first

`docs/architecture/messaging.md` (the port shape and its honest limits), `docs/adr/0005-transactional-outbox.md`,
`docs/adr/0006-broker-abstraction.md` (both already Accepted - this item implements them, not
re-decides them), `docs/conventions/naming-and-structure.md`'s `ago-platform` layout,
`docs/architecture/clean-architecture.md` (qualifying rules - this is the rare case where new platform
abstraction *is* justified: two real callers already named in the roadmap, RabbitMQ now/Kafka later
and Postgres now/MySQL at Stage 9), `docs/adr/_template.md`.

## Scope

- `Ago.Platform.Abstractions`: `IEventPublisher`, `IEventConsumer`, `EventEnvelope` exactly as shaped
  in `messaging.md` (topic, partition key, at-least-once, explicit ack/nack/dead-letter, `Competing`
  vs `Broadcast` subscription mode). No RabbitMQ- or Kafka-specific type leaks through.
- `Ago.Platform.Abstractions`: `IOutboxWriter` - the port a product's Application-layer handler calls
  to stage an event for publishing, in the same unit of work as its own state change. Keep this
  synchronous from the caller's perspective (it stages an entity on the already-open `DbContext`
  change tracker; it does no I/O itself) - the existing per-request `SaveChangesAsync` a handler
  already calls is what makes "same transaction" true for free. Do **not** introduce a new
  `IUnitOfWork` abstraction to achieve this: every handler already saves through exactly one
  DI-scoped `DbContext` per request (verified in `SendVisitorMessageHandler` - `1-02`), so a second
  transaction-coordination concept would be solving a problem that does not exist yet
  (`clean-architecture.md`'s qualifying rules - premature generalisation).
- `Ago.Platform.Persistence.Postgres`: the generic `OutboxMessage`/`InboxRecord` EF entities and their
  `IEntityTypeConfiguration`s (columns exactly as `data-model.md` lists for `outbox`/`inbox`), plus a
  generic `EfOutboxWriter<TContext> : IOutboxWriter where TContext : DbContext` and a generic
  `IInboxChecker`/`EfInboxChecker<TContext>` for consumer-side dedup. Generic over `TContext` is what
  keeps this project product-agnostic without ever referencing `Ago.Chat.*` - a product's own
  `DbContext` opts in by including the shared configuration and registering the generic writer with
  its own concrete `DbContext` type in its own DI wiring (`Ago.Chat.Module`, not here).
- Write an ADR (`docs/adr/0017-...md`) recording the generic-over-`DbContext` shape chosen for the
  outbox/inbox writer, and the rejected alternative (each product hand-rolls its own outbox writer
  against the shared entity shape only). This is the first time a platform project carries real
  behaviour instead of pure primitives/contracts, which is exactly the kind of decision
  `clean-architecture.md` says needs one.
- `Ago.Platform.Architecture.Tests`: extend the platform's own arch-test list so
  `Ago.Platform.Persistence.Postgres` and `Ago.Platform.Abstractions` still never reference
  `Ago.Chat.*` (there is nothing to reference yet, but the rule should exist before there is).
- Unit/integration tests for the writer and checker against a real Testcontainers Postgres, using a
  throwaway test `DbContext` - proving the generic mechanism works before any product touches it.

## Out of scope

- RabbitMQ or any other broker adapter (`2-03`) - this item is publish-agnostic; nothing here talks to
  a broker.
- Anything in `Ago.Chat.*` - no outbox table in `ago-chat`'s own schema yet, no handler wired up
  (`2-02`).
- The outbox dispatcher loop (`SKIP LOCKED`, poll-plus-notify) - that reads the generic table this
  item defines, but the dispatcher itself is a `Ago.Chat.Worker` concern (`2-04`), not a platform one.
- Outbox row pruning/retention - `messaging.md` names it as a maintenance concern but no stage commits
  to it yet; do not invent a job for it here. **Committed to since 2026-08-24**: Stage 15's
  `15-04-retention-and-pruning-jobs.md` owns it. Still not this item's job - the note stands, it now
  names where the work went.

## Done when

- [x] `Ago.Platform.Abstractions` and `Ago.Platform.Persistence.Postgres` exist, build, and are
      included in `dotnet pack` output.
- [x] `EfOutboxWriter<TContext>` stages an `OutboxMessage` row on the context's change tracker with no
      I/O of its own; a test proves it and an unrelated entity change are persisted by exactly one
      `SaveChangesAsync` call, or neither is (real Postgres, not a mock - `testing.md`: "never mock the
      database").
- [x] `EfInboxChecker<TContext>` proves a duplicate `message_id` is detected and the second insert is a
      no-op, not an exception the caller must handle specially.
- [x] ADR-0017 written, `Accepted`, linked from `messaging.md`.
- [x] `Ago.Platform.Architecture.Tests` green, including the new "no `Ago.Chat.*` reference" rule.

## Open questions

None. The port shape and the outbox/inbox pattern are already decided (`adr/0005`, `adr/0006`); the
generic-over-`DbContext` implementation shape is this item's own ADR to write, not a blocking question
for the author.
