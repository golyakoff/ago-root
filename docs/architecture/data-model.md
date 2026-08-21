# Data model

PostgreSQL is the only source of truth. Everything else is a cache, a queue, or a projection.

## Tables (initial shape - refined per stage)

- `sites` - the tenant. `id`, `public_key`, `allowed_origins[]`, settings.
- `visitors` - `id`, `site_id`, `token_hash`, first/last seen. Anonymous, no PII by design.
- `operators` - `id`, `site_id`, `status` (`offline|online|away`), `capacity`, `active_chats`.
- `conversations` - `id`, `site_id`, `visitor_id`, `operator_id?`, `state`
  (`waiting|assigned|closed`), `last_sequence`, timestamps. Optimistic concurrency uses Postgres's
  built-in `xmin` system column (`1-04`), not an extra column of our own to keep in sync by hand.
- `messages` - `id` (uuid v7), `conversation_id`, `sequence`, `author_kind`, `author_id`, `body`,
  `created_at`, `delivered_at?`, `read_at?`.
- `outbox` - `id`, `occurred_at`, `type`, `version`, `payload` (jsonb), `partition_key`,
  `correlation_id`, `published_at?`, `attempts`. See `adr/0005`. `version`/`correlation_id` were
  missing from the first cut - added once `2-04`'s dispatcher needed to reconstruct a complete
  `EventEnvelope` from a claimed row, since dropping `correlation_id` silently defeats its purpose.
- `inbox` - `message_id`, `consumer`, `processed_at`. The idempotency ledger for consumers.
- `roles` - `id`, `site_id`, `name`, `permissions` (`text[]`) - the RBAC model `adr/0016` added,
  built in `1-04`. No management API yet; `1-05`'s seed script is the only writer.
- `operator_roles` - `operator_id`, `role_id` - the join table; an operator can hold more than one
  role even though Stage 1 only ever grants the single seeded `"Operator"` role.

## Keys and indexes

- Ids are **UUID v7** (time-ordered). Random UUIDs fragment B-tree inserts; a bigint sequence leaks
  counts and complicates multi-writer scenarios. Any deviation needs an ADR.
- `messages` unique `(conversation_id, sequence)` - enforces per-conversation ordering at the storage
  level and turns duplicate delivery into a no-op insert.
- History reads use **keyset pagination**:
  `WHERE conversation_id = @id AND sequence < @cursor ORDER BY sequence DESC LIMIT @n`.
  `OFFSET` is banned - it degrades exactly where this project is supposed to shine.
- `conversations` partial index on `(site_id) WHERE state = 'waiting'` for the assignment queue.
- `outbox` partial index on `(id) WHERE published_at IS NULL` - the dispatcher must never scan
  already-published rows.

## Partitioning

`messages` is `PARTITION BY RANGE (created_at)`, monthly, with partitions created ahead of time by a
maintenance job. Rationale: bounded index size, cheap retention (`DROP` a partition instead of a mass
`DELETE`), and a concrete thing to demonstrate. Introduced in Stage 2, before data volume makes it
awkward.

## Access strategy

Writes go through EF Core, one aggregate per transaction, no lazy loading. Reads go through Dapper
with hand-written SQL returning DTOs. Rationale and trade-offs: `adr/0004`.

## Migrations

**Verified**: `Stage1CreateChatSchema` (`1-04`) applied cleanly to a real Postgres (both the
`docker-compose` instance and a throwaway Testcontainers one), all tables/FKs/indexes landed as
designed, and `Ago.Chat.Integration.Tests` proves the unique `(conversation_id, sequence)` constraint
actually rejects a duplicate insert at the storage level. `Stage2AddOutboxAndInbox` (`2-02`) is
verified the same way: `outbox` and `inbox` are real tables (`adr/0005`, `adr/0017`), mapped through
`Ago.Platform.Persistence.Postgres`'s shared configuration rather than hand-rolled here - `outbox`
already has a real writer (`2-02`'s handlers); `inbox` has the table and the ledger's unique
constraint, but no writer until `2-05`'s consumer exists.

EF Core migrations, one per change, named `<Stage><Verb><Subject>`. Rules:

- Always reversible, or explicitly marked one-way with a comment explaining why.
- Never edit a migration that has been applied anywhere but the local machine.
- Raw SQL (partitions, partial indexes, helper functions) goes into the migration via
  `migrationBuilder.Sql`, never into a hand-run script that will drift.

## Provider swap (Stage 9)

`Ago.Chat.Infrastructure.MySql` implements the same ports. Known frictions to document rather than
hide: `jsonb` vs `json`, UUID storage, `SKIP LOCKED` support, partitioning syntax, and
case-sensitivity of identifiers. The honest list of frictions is the point of the exercise.
