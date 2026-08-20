---
name: db-migration
description: Change the AGO Platform database schema - EF Core migrations, indexes, partitioning, keyset-friendly queries and Dapper read stores. Use when adding or altering a table, column, index, or any SQL.
---

# Changing the schema

Authoritative sources: `docs/architecture/data-model.md`, `adr/0004`, `adr/0011`.

## Rules before you touch the model

- Writes go through EF Core; reads go through Dapper read ports. Do not add a read path to the
  `DbContext` because it is convenient.
- Ids are UUID v7 from `IIdGenerator`. Never `Guid.NewGuid()` in application code.
- Every instant is `timestamptz` mapped to `DateTimeOffset`. No naive timestamps, no `timestamp`.
- Money, if it ever appears, is `numeric`, never floating point.
- Multi-tenancy is not optional: every table carries `site_id`, and every query filters by it.

## Making the change

1. Update the entity and its `IEntityTypeConfiguration` in the Infrastructure project. The Domain
   entity stays attribute-free - the mapping is an infrastructure concern.
2. Add the migration: `dotnet ef migrations add <StageVerbSubject> -p <infra project> -s <host>`.
3. **Read the generated migration.** EF will happily generate a table rewrite or a blocking index
   build; you are responsible for what it does, not EF.
4. Indexes, partial indexes, partitions, and any raw DDL go into the migration through
   `migrationBuilder.Sql`, never into a side script that will drift from the code.
5. Update `data-model.md` in the same change if the shape or an index rationale changed.

## Index and query rules

- Every new query path gets its index decided consciously; state which index serves it.
- Pagination is keyset (`WHERE ... < @cursor ORDER BY ... LIMIT n`). `OFFSET` is banned.
- Prefer partial indexes for queue-like queries (`WHERE state = 'waiting'`, `WHERE published_at IS NULL`) -
  they stay small, which is the point.
- Queue-claiming queries use `FOR UPDATE SKIP LOCKED`, batched, inside a transaction.
- Anything enforcing a guarantee gets a constraint, not just application code: unique
  `(conversation_id, sequence)` is the ordering guarantee's last line of defence.

## Safety

- Migrations are reversible, or explicitly marked one-way with a comment saying why.
- Never edit a migration that has been applied anywhere but your machine - add a new one.
- Additive-first for anything that will run against real data: add nullable column, backfill, then
  enforce. Even here, where "real data" is a demo, the habit is what a reviewer is looking for.
- Large backfills are batched with a cancellation check, not one giant `UPDATE`.

## Tests

- Integration test against a real Postgres via Testcontainers - migrations applied from scratch.
- If you added an index for a performance reason, add or update the query test that would notice its
  absence, and say plainly that the performance claim is unverified until Stage 7 measures it.

## MySQL awareness (Stage 9)

Anything you use that is Postgres-specific - `jsonb`, partial indexes, `timestamptz`, range
partitioning, `SKIP LOCKED` semantics - goes on the Stage 9 friction list in `data-model.md`. Using
them is fine and expected; hiding them is not.
