# Postgres persistence: EF Core writes, Dapper reads, first migration

- **Stage**: 1
- **Status**: ready
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

- [ ] `dotnet ef database update` (or the CI-equivalent migration bundle) against the `docker-compose`
      Postgres from `0-03` succeeds from empty.
- [ ] Integration tests pass against a real Testcontainers Postgres — not mocked
      (`testing.md`: "a mocked repository proves the test compiles, nothing more").
- [ ] `Ago.Chat.Architecture.Tests`' "only this project references Npgsql" rule (or the arch-test
      equivalent, add it if it does not exist yet) passes.
- [ ] `docs/architecture/data-model.md` updated if the actual schema diverges from what it currently
      describes (it is written as the "initial shape," so some divergence during real implementation
      is expected — reconcile it, do not let the doc go stale).

## Open questions

None.
