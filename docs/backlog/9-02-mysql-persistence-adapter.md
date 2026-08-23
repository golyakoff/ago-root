# Ago.Chat.Infrastructure.MySql: the same ports, the full current schema

- **Stage**: 9
- **Status**: ready
- **Depends on**: `1-04-postgres-persistence.md` (the baseline schema and the port shapes this adapter
  re-implements), `2-01-platform-outbox-inbox-and-messaging-port.md` (outbox/inbox tables and the
  generic `EfOutboxWriter<TContext>`/`EfInboxChecker<TContext>` writer this adapter must opt into,
  `adr/0017`), `2-05-unread-counter-consumer-and-idempotency.md` (the `visitor_unread_count`/
  `operator_unread_count` columns and the load-mutate-save-on-a-concurrency-token pattern they depend
  on), `2-06-messages-partitioning.md` (`messages` partitioned by `created_at`), `4-01-waiting-queue-
  and-capacity-model.md` (the `active_chats` shadow property and the raw compare-and-set `UPDATE` it
  requires), `5-04-attachment-thumbnails-and-orphan-sweep.md` (the `attachments` table's final shape,
  `thumbnail_key` included), `6-03-webhook-registration-and-delivery-history.md` (`webhook_endpoints`/
  `webhook_deliveries`, the newest tables in the schema) - this adapter mirrors the *complete* schema
  as these items left it, not Stage 1's subset

## Goal

`IConversationRepository`, `IConversationReadStore`, and every other port
`Ago.Chat.Infrastructure.Postgres` currently implements have a second real adapter, backed by an
actual MySQL database, that a caller cannot tell apart by behaviour: the full schema exists, every
constraint that matters (unique `(conversation_id, sequence, ...)`, the outbox/inbox idempotency
ledger, the operator capacity compare-and-set, partitioned `messages`) holds, and
`Ago.Chat.Integration.Tests`/`Ago.Chat.Concurrency.Tests` pass against it exactly as they do against
Postgres. This is the other half of Stage 9's claim: that `adr/0004`'s write/read split was a real
port, not an accidental Postgres-shaped one.

## Context to read first

`docs/architecture/data-model.md` in full, especially its "Provider swap (Stage 9)" section - the
friction list it already names (`jsonb` vs `json`, UUID storage, `SKIP LOCKED` support, partitioning
syntax, case-sensitivity of identifiers) is the starting checklist, not the complete one; this item's
job is to find out what else is on it. `docs/adr/0004-postgres-ef-writes-dapper-reads.md` in full -
the actual contract being proven ("PostgreSQL is the only source of truth" becomes "the configured
provider is," everything else about the write/read split must survive unchanged).
`docs/adr/0011-utc-datetimeoffset-everywhere.md` - already flags "MySQL handles offsets differently
from `timestamptz`... that friction goes on the Stage 9 list," read before writing a single column
mapping. `docs/adr/0017-generic-outbox-inbox-writer.md` in full - states directly that "Stage 9's
MySQL swap reuses the same generic writer/checker unchanged - only the underlying `DbContext`'s
provider changes"; this item is where that claim gets tested for real, and where it is reported
honestly if it turns out not to be quite true. `docs/backlog/1-04-postgres-persistence.md` - the
reference for what implementing these ports for real actually involves, including its own Status note
of three real bugs `1-04` found by running it (an EF backing-field collision, FK CLR-type mismatches,
Dapper's exact-type binding for timestamps) - the kind of finding this item should expect its own
equivalents of, not assume away. `docs/architecture/concurrency.md`'s statement on `xmin`-based
optimistic concurrency and `data-model.md`'s explanation of why `active_chats` is a raw compare-and-set
`UPDATE`, never a load-mutate-save - MySQL has no `xmin` equivalent, so the concurrency-token mechanism
for `conversations` needs a real replacement, decided and justified here, not silently dropped.
`docs/backlog/2-06-messages-partitioning.md` - `PartitionMaintenanceJob` (`Ago.Chat.Worker`) currently
issues Postgres-specific raw SQL (`CREATE TABLE ... PARTITION OF`) directly; this item needs a MySQL
equivalent (`ALTER TABLE ... ADD PARTITION` / `REORGANIZE PARTITION` - MySQL's partitioning DDL is
genuinely different, not a syntax variant) reachable the same way every other provider-specific
behaviour is - behind a port, selected by `Persistence:Provider`, never a provider `if` inside
`Ago.Chat.Worker` itself (`clean-architecture.md`'s Hosts rule: hosts select implementations by
configuration, they do not branch on provider).

## Scope

- `Ago.Chat.Infrastructure.MySql` project (`naming-and-structure.md` already reserves the name),
  referencing `Ago.Chat.Application` + `Ago.Chat.Domain` only - same boundary
  `Ago.Chat.Infrastructure.Postgres` holds today.
- A NuGet package choice for the MySQL EF Core provider (state which one and why hand-rolling
  `IDbConnection`/Dapper-only access would be strictly worse here - `CLAUDE.md`'s "do not add a NuGet
  package without saying what it replaces" rule applies to this choice the same as any other).
- `AgoChatMySqlDbContext` + `IEntityTypeConfiguration<T>` per entity, reproducing every table
  `Ago.Chat.Infrastructure.Postgres` currently maps: `sites`, `visitors`, `operators` (with
  `active_chats` as the equivalent shadow property, written only by the same kind of atomic
  compare-and-set `UPDATE`, never through the change tracker), `conversations` (with a real
  optimistic-concurrency token - MySQL has no `xmin`; decide and justify the replacement, e.g. an
  application-managed `version` integer column incremented on every save, or a MySQL `TIMESTAMP(6)`
  auto-update column wired as an EF concurrency token - state which and why in a comment, the same way
  `1-04` documented its own `xmin` choice), `messages` (partitioned, MySQL `RANGE COLUMNS` syntax),
  `outbox`/`inbox` (opting into the generic `EfOutboxWriter<TContext>`/`EfInboxChecker<TContext>` from
  `adr/0017` - the point of that ADR's genericity is that this should need no new writer code, only DI
  wiring; if it turns out to need more, that gap itself is a finding for `9-04`), `roles`/
  `operator_roles`, `attachments`, `webhook_endpoints`/`webhook_deliveries`.
- `IConversationRepository` implementation: same load-aggregate-plus-messages, save-via-
  `SaveChangesAsync`-in-one-transaction shape as the Postgres adapter.
- `IConversationReadStore` implementation: hand-written SQL via Dapper against MySQL, same keyset-
  pagination shape (`WHERE conversation_id = @id AND sequence < @cursor ORDER BY sequence DESC LIMIT
  @n`) - `OFFSET` stays banned regardless of provider.
- `IOperatorCapacity` (`data-model.md`'s own naming - `OperatorCapacityStore` is the Postgres
  implementation's name, so the MySQL one wants an equally direct name, e.g.
  `MySqlOperatorCapacityStore`) implementation: the same atomic compare-and-set `UPDATE ... WHERE
  active_chats < capacity` pattern, in MySQL's own SQL dialect, proven under the same concurrent-claim
  test shape `4-01`'s own tests use.
- A MySQL equivalent of `PartitionMaintenanceJob`'s partition-ensuring DDL, reachable behind a small
  port implemented by each persistence adapter (see Context above) rather than a provider branch in
  `Ago.Chat.Worker`.
- One EF Core migration bundle (MySQL's own migration history, separate from the Postgres one, per
  provider - two providers cannot share one `Migrations` folder), reversible where the Postgres
  equivalent is and one-way where it is (the partitioning conversion stays one-way, for the same reason
  stated in `data-model.md`).
- `Ago.Chat.Integration.Tests` and `Ago.Chat.Concurrency.Tests` run against this adapter: either a new
  Testcontainers MySQL fixture selected alongside the existing Postgres one (test-project-level
  parameterization, run both in the same CI job) or the exact same test classes run twice with a
  provider parameter - decide the shape that keeps one set of test *bodies* proving one set of
  behavioural guarantees against two real databases, not two parallel and silently-diverging test
  suites (`testing.md`: "never mock the database").
- `docs/architecture/data-model.md`'s "Provider swap (Stage 9)" section: update from a forward-looking
  list of expected frictions to a statement of what was actually found, the same way `1-04` closed out
  Stage 1's schema documentation.

## Out of scope

- Kafka - `9-01`, independent of this item (`roadmap.md`'s own note that the two adapters are logically
  independent).
- Making MySQL the active provider anywhere, or the config switch itself - `9-03`.
- Any change to `IConversationRepository`/`IConversationReadStore`/`IOperatorCapacity`'s port shape.
  If this adapter finds the port cannot honestly express something MySQL needs, that is a finding for
  `9-04`, not a silent port edit here - matching `9-01`'s own rule for the messaging port.
- Retention/dropping old partitions - still nobody's committed requirement, per `2-06`'s own Out of
  scope, unchanged by adding a second partitioned-table implementation.
- A management API for `roles`/`operator_roles` - still nothing manages them beyond `1-05`'s seed
  script, unchanged by this item; the MySQL adapter reproduces the schema, not new behaviour around it.

## Done when

- [ ] `Ago.Chat.Integration.Tests` passes against a real Testcontainers MySQL: the unique
      `(conversation_id, sequence, ...)` constraint rejects a duplicate insert, keyset pagination
      returns pages in the right order, a full save-then-reload round-trip preserves every field, the
      outbox/inbox idempotency ledger works (a redelivered event increments an unread counter exactly
      once, mirroring `2-05`'s own proof), and the partitioned `messages` table accepts inserts into the
      current month without `PartitionMaintenanceJob`'s MySQL equivalent having run first.
- [ ] `Ago.Chat.Concurrency.Tests` passes against MySQL: the operator-capacity compare-and-set proof
      (many workers racing to assign, no operator ever exceeds capacity) and the conversation
      optimistic-concurrency proof (two concurrent saves computing the same `LastSequence`, one throws)
      both hold on this provider, not assumed from the Postgres result.
- [ ] `Ago.Chat.Architecture.Tests`' "only this project references [MySQL client library]" rule extended
      to cover the new project, the same boundary `PersistenceBoundaryTests` already enforces for
      `Ago.Chat.Infrastructure.Postgres`.
- [ ] `docs/architecture/data-model.md`'s "Provider swap (Stage 9)" section updated with what was
      actually found - real frictions, not the pre-written checklist restated as if it were the finding.
- [ ] `CHANGELOG.md` entry / version note if this ships from `ago-chat` alongside a package version, or
      a plain commit note if `ago-chat` does not version the way `ago-platform` does (confirm which
      applies before writing the entry).

## Open questions

None. The ports and the schema they must reproduce are already settled by the items listed in
`Depends on`; this item implements against them and reports honestly wherever MySQL cannot honour
something Postgres could without a visible workaround.
