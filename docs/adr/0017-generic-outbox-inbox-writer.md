# ADR-0017: Outbox/inbox writer is generic over DbContext, not per-product

- **Status**: Accepted
- **Date**: 2026-08-21
- **Stage**: 2

## Context

`adr/0005` decided the outbox row must be written in the same transaction as the state change it
describes. `naming-and-structure.md` already names `Ago.Platform.Persistence.Postgres` as the project
holding "UoW, transactions, outbox/inbox plumbing" - generic, reusable platform code, not something
`Ago.Chat.Infrastructure.Postgres` owns for itself. This is the first time a platform project carries
real behaviour rather than pure primitives (`Kernel`) or a pure contract (`Hosting`'s
`IProductModule`), so the shape of that behaviour needs to be decided deliberately rather than emerge
from whatever the first caller happens to need.

The concrete question: every product owns its own `DbContext` (`AgoChatDbContext` today, a MySQL
equivalent at Stage 9). The outbox/inbox writer needs to add rows to *that* context's change tracker
so the product's own `SaveChangesAsync` call persists them atomically alongside the product's own
change - but the platform must never reference `Ago.Chat.*` (`clean-architecture.md`, `adr/0003`).

## Decision

`Ago.Platform.Persistence.Postgres` ships:

- `OutboxMessage` / `InboxRecord`: plain EF entities plus `IEntityTypeConfiguration<T>` for both,
  matching `data-model.md`'s column shapes exactly. A `ModelBuilderExtensions.ApplyOutboxInboxConfiguration()`
  extension lets a product's own `OnModelCreating` opt in with one line.
- `EfOutboxWriter<TContext>` and `EfInboxChecker<TContext>`, both generic over `TContext : DbContext`,
  implementing `IOutboxWriter`/`IInboxChecker` from `Ago.Platform.Abstractions`. Neither ever names a
  concrete `DbContext` type - genericity over `TContext` is what keeps this product-agnostic without
  needing a compile-time reference to any product's assembly.
- A product's own DI wiring (`Ago.Chat.Module`, never the platform) is the only place a concrete type
  argument (`AgoChatDbContext`) is supplied, via `services.AddOutboxInbox<AgoChatDbContext>()`. This is
  the same seam `IProductModule` already establishes: the platform defines shape, the product's own
  host-adjacent wiring is where a concrete type meets it.
- Both writer and checker only ever **stage** entities on the tracked context; neither calls
  `SaveChangesAsync` on its own for the outbox side. `IInboxChecker.TryRecordAndSaveAsync` is the one
  exception, by necessity: detecting "this is a duplicate" is only knowable from the unique-constraint
  outcome of an actual save, so the consumer's own work must already be staged on the same context
  before calling it - the method name says so on purpose, so a caller cannot use it without noticing
  that it commits.

## Consequences

- A product opts in with two lines (`ApplyOutboxInboxConfiguration()` in `OnModelCreating`,
  `AddOutboxInbox<TContext>()` in DI) and gets the same durability guarantee every other product gets,
  with zero duplicated table-mapping or transaction code.
- Stage 9's MySQL swap reuses the same generic writer/checker unchanged - only the underlying
  `DbContext`'s provider changes, which this design never had to know about in the first place.
- Cost: the generic-over-`DbContext` shape is less immediately readable than a hand-written
  `AgoChatOutboxWriter` would be for a reader seeing only `ago-chat` - the trade is explicit here so a
  future reader of `Ago.Chat.Module`'s DI registration is not left wondering why the writer takes a
  type argument.
- `IInboxChecker.TryRecordAndSaveAsync` saving on the caller's behalf is a deliberate asymmetry with
  `IOutboxWriter.Enqueue` (which never saves). A consumer that forgets this and calls
  `dbContext.SaveChangesAsync()` again afterward does nothing harmful (a no-op second save), but a
  consumer that calls it *before* staging its own work breaks the same-transaction guarantee silently -
  `2-05`'s implementation and its tests exist to catch exactly that mistake once, not to make it
  structurally impossible.

## Alternatives considered

- **Each product hand-rolls its own outbox writer against the shared `OutboxMessage` entity shape
  only** (platform ships the entity and configuration, not the writer). Simpler to read per-product,
  and avoids the generic-type-argument indirection. Rejected: it duplicates the exact same four lines
  of staging code in every product from Stage 9 onward for no behavioural difference, and
  `naming-and-structure.md` already committed to the writer living in the platform project, not just
  the schema.
- **A real `IUnitOfWork` abstraction with explicit `BeginTransaction`/`Commit`.** Rejected for now: no
  handler in `ago-chat` needs a transaction spanning more than one `DbContext.SaveChangesAsync` call
  (`2-01`'s backlog item verified this against `SendVisitorMessageHandler`), so introducing the concept
  would be solving a problem this codebase does not have yet (`clean-architecture.md`'s qualifying
  rules). Revisit if a future handler genuinely needs multi-context coordination.
