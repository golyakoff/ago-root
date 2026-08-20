# Postgres persistence: EF Core writes, Dapper reads, first migration

- **Stage**: 1
- **Status**: done — 74 tests across the solution (was 63 after `1-02`), including 10 new
  `Ago.Chat.Integration.Tests` against a real Testcontainers Postgres, and a new
  `PersistenceBoundaryTests` arch rule (13 arch tests total, was 12). Migration applied for real to
  the `docker-compose` Postgres from `0-03`, schema inspected directly with `psql`. Three real bugs
  found by running this, all fixed:
  - EF's own convention silently claimed `_messages` as `Messages`'s backing field too, colliding
    with the explicit field-targeted navigation - `builder.Ignore(c => c.Messages)` fixed it.
  - FK columns need the *same CLR type* as the principal key after conversion, not just the same
    underlying database type - `RoleRecord.SiteId`/`OperatorRoleRecord.OperatorId` had to become the
    Domain id types, not raw `Guid`, for `HasForeignKey` to accept the relationship.
  - Dapper's constructor-binding needs exact type matches: Npgsql returns `timestamptz` as a
    UTC-kinded `System.DateTime` over raw ADO.NET (not `DateTimeOffset` - that conversion is EF's own
    provider doing work Dapper never sees), so the read-model row type used `DateTime`, converted to
    `DateTimeOffset` explicitly before crossing back into `IConversationReadStore`.
  - Also caught, unrelated to Postgres: every PK column landed as `Id` instead of `id` at first
    (missing `HasColumnName` on the id property in every configuration) - fixed before the first
    migration was even generated.
- **Depends on**: `1-02-application-use-cases.md`

## Goal

`Ago.Chat.Infrastructure.Postgres` (currently an empty scaffold) implements `IConversationRepository`
via EF Core and `IConversationReadStore` via Dapper, backed by a real migration that creates
`sites`, `visitors`, `operators`, `conversations`, `messages` — the Stage 1 subset of
`data-model.md`'s initial shape (no `outbox`/`inbox`, no partitioning — Stage 2).

## Context to read first

`docs/architecture/data-model.md`, `docs/adr/0004-*`, `docs/adr/0016-*` (the RBAC model this schema
must also represent — `data-model.md` predates it), `docs/architecture/clean-architecture.md`
(Infrastructure section), `docs/runbooks/local-dev.md` (the Postgres container this runs against).

## Scope

- EF Core `AgoChatDbContext` + `IEntityTypeConfiguration<T>` per entity — mapping lives here, never
  attributes on the Domain types.
- `messages` unique constraint on `(conversation_id, sequence)` — turns duplicate delivery into a
  no-op insert at the storage level, per `data-model.md`, even though nothing retries yet in Stage 1.
- `conversations.version` as an EF concurrency token (`xmin` or an explicit column — pick one, note
  why in a comment) — the domain entity itself carries no such field (`1-01`).
- `roles` (site-scoped, `id`, `site_id`, `name`, `permissions[]` or a join table — pick the simpler
  shape for exactly one row's worth of data) and `operator_roles` (or a column on `operators` if a
  join table is overkill for one role — implementation detail, decide while writing it): the schema
  `adr/0016`'s RBAC model needs. Not exposed by any Domain/Application port beyond
  `IPermissionChecker` (`1-02`) — no repository for managing roles yet, since nothing manages them.
- One EF Core migration, named `Stage1CreateChatSchema` (`data-model.md`'s naming rule), reversible.
- `IConversationRepository` implementation: load aggregate + its messages, save via `SaveChangesAsync`
  inside one transaction — one aggregate per transaction (`data-model.md`).
- `IConversationReadStore` implementation: hand-written SQL, keyset pagination
  (`WHERE conversation_id = @id AND sequence < @cursor ORDER BY sequence DESC LIMIT @n`), `OFFSET`
  banned.
- `Ago.Chat.Integration.Tests` (new project — first one in the repo): Testcontainers-managed
  Postgres, migrations applied once per collection (`testing.md`). Proves: the unique constraint
  actually rejects a duplicate `(conversation_id, sequence)`, keyset pagination returns pages in the
  right order and stops correctly, and a full save-then-reload round-trip preserves every field.

## Out of scope

- Outbox table and dispatch — Stage 2.
- `messages` partitioning — Stage 2 ("before data volume makes it awkward," not before there is any
  data at all).
- MySQL — Stage 9.

## Done when

- [x] `dotnet ef database update` (or the CI-equivalent migration bundle) against the `docker-compose`
      Postgres from `0-03` succeeds from empty.
- [x] Integration tests pass against a real Testcontainers Postgres — not mocked
      (`testing.md`: "a mocked repository proves the test compiles, nothing more").
- [x] `Ago.Chat.Architecture.Tests`' "only this project references Npgsql" rule (added -
      `PersistenceBoundaryTests`) passes.
- [x] `docs/architecture/data-model.md` updated if the actual schema diverges from what it currently
      describes (it is written as the "initial shape," so some divergence during real implementation
      is expected — reconcile it, do not let the doc go stale).

## Open questions

None.
