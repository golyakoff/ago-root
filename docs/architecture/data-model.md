# Data model

PostgreSQL is the only source of truth. Everything else is a cache, a queue, or a projection.

**This file covers two databases, not one.** Everything down to *Provider swap* is **AGO Chat**'s
schema; **AGO Calendar** has its own section near the end and its own separate database — no query in
either product can reach the other's tables (`adr/0027`), and no foreign key crosses between them.

*Why one file and not one per repository* (decided in `20-01`, since `ago-calendar` is the first
product that could have gone either way): every other architecture document here already spans both
products in place — `repositories.md` and `naming-and-structure.md` both gained `ago-calendar` rows in
`20-00` rather than sprouting per-repo copies — and `ago-root`'s stated job is to hold the rules and
decisions for the whole platform while the code lives elsewhere. Splitting this one file would make it
the first exception, and would put the two products' schemas where a reviewer comparing them cannot
see them side by side, which is exactly the comparison the platform claim invites. The cost is that
this page is now long and mixes two databases; the section heading below is the mitigation, not a
denial.

## Tables (initial shape - refined per stage)

- `sites` - the tenant. `id`, `public_key`, `allowed_origins[]`, `name` (**added in `10-02`** - a real
  gap that item's own scope anticipated: its Goal takes a site display name as a required
  registration input, but no such column existed before this stage. `text not null default ''`,
  additive/reversible - `Stage10AddSiteName`, `ago-chat`). **Shipped in `11-01`**: the `settings`
  placeholder named above was never actually built (the Stage 1 migration shipped `id`/`public_key`/
  `allowed_origins` only) - it is now two concrete columns, `widget_primary_color_hex text NULL` and
  `widget_position text NOT NULL DEFAULT 'bottom-right'`, added by `Stage11AddSiteWidgetConfig`
  (`Ago.Chat.Domain.WidgetConfig`, `adr/0029`'s two fixed fields). `widget_position` carries a `CHECK`
  constraint restricting it to `'bottom-right'`/`'bottom-left'` - cheap storage-level backstop for the
  `Position` enum, matching this table's own `Ago.Chat.Domain.Position`/`PositionConverter` mapping
  (kebab-case in the column, the CLR enum's own member names on the wire - the two boundaries are free
  to differ). **`created_at timestamptz NULL` added in `12-02`** (`Stage12AddSiteCreatedAt`,
  additive/reversible) - the same kind of real gap `name` records above: `12-02`'s owner overview needs
  a per-tenant creation time and this table had none, though `conversations`, `messages` and
  `attachments` all carry one. **Nullable with no default and no backfill, on purpose**: giving existing
  rows `DEFAULT now()` would stamp the demo tenant and every previously-registered site with the instant
  the migration ran and present that as fact. `null` means "not recorded"; the only writer is
  `RegisterSiteHandler`, from `IClock`.
- `visitors` - `id`, `site_id`, `first_seen_at`, `last_seen_at`, and nothing else.
  **Corrected in `16-01`**: this bullet listed a `token_hash` column that was never built. There is no
  such column in `Stage1CreateChatSchema`, in the EF model snapshot, or in `Visitor.cs`, and the string
  does not occur anywhere in `ago-chat` - the visitor token is a stateless signed JWT (`sub`, `site_id`,
  `kind`) that the server issues and validates but never stores. The browser is the only place a copy
  exists. The practical consequences run in both directions and both are worth knowing before designing
  against this table: there is nothing here to leak, and there is also no server-side handle to revoke
  (`adr/0034`'s "no deny-list, because there is no caller").
  No name, email or contact detail by design - the row identifies a returning browser, not a named
  person. **Qualified 2026-08-25**: that is true of these columns and misleading about the dataset,
  since `messages` next to it holds whatever the visitor typed, which in a support product routinely
  includes their own name and phone number. See `personal-data.md` for what the system actually holds
  and where; an identifier that reliably singles out a returning individual is also not the same thing
  as anonymous data.
- `operators` - `id`, `site_id`, `status` (`offline|online|away`), `capacity`, `active_chats`.
  **Shipped in `4-01`**: `active_chats` is not part of the `Operator` aggregate - EF maps it as a
  shadow property (`OperatorConfiguration`, `Ago.Chat.Infrastructure.Postgres`) purely so migrations
  see it; the only writer is the atomic compare-and-set
  `UPDATE operators SET active_chats = active_chats + 1 WHERE id = @id AND active_chats < capacity`
  (`concurrency.md`'s own statement, `OperatorCapacityStore`/`IOperatorCapacity`) and its symmetric
  release. Nothing ever loads `Operator` through EF's change tracker and saves it back, so there is
  no load-mutate-save path that could race the raw `UPDATE` - the shadow property is what makes that
  true by construction, not by convention.
  **Corrected in `6-09`**: the "symmetric release" above was, until then, a sentence this document
  asserted and no ordinary code path performed. `active_chats` went up on every automatic assignment
  and came back down only when an operator's *last connection anywhere* dropped (`4-04`'s
  `OperatorConversationReleaser`), so an operator who simply finished conversations one at a time
  ratcheted to zero usable capacity and the site's waiting queue stopped being served - found live by
  `7-04`'s `assignment-contention` run (`load/reports/2026-08-24-assignment-contention.md`), not by
  reading this page. The invariant the column now actually keeps, and the one to check any future
  change against: **`active_chats` equals the number of conversations currently `Assigned` to that
  operator whose `holds_capacity_claim` is true** - see the `conversations` bullet below and
  `adr/0033`.
- `conversations` - `id`, `site_id`, `visitor_id`, `operator_id?`, `state`
  (`waiting|assigned|closed`), `last_sequence`, `visitor_unread_count`, `operator_unread_count`,
  `operator_last_read_sequence`, timestamps. Optimistic concurrency uses Postgres's built-in `xmin`
  system column (`1-04`), not an extra column of our own to keep in sync by hand - which is also what
  lets the unread counters (`2-05`) use a plain load-mutate-save through the aggregate instead of a
  raw atomic `UPDATE`: a losing concurrent save throws rather than silently overwriting the other
  side's increment, and the broker's own redelivery is the retry.
  `operator_last_read_sequence` (`5-15`) is what makes that counter clearable without losing a
  message: mark-read moves the watermark and subtracts what it covers rather than zeroing, and the
  increment skips anything at or below it, so a message arriving in the same instant as a mark-read is
  still counted whichever of the two saves wins the `xmin` race. There is no visitor-side twin -
  nothing reads `visitor_unread_count` yet (`5-15`'s own Decisions section). No index: the column is
  only ever read as part of an aggregate already located by primary key.
  `holds_capacity_claim` (`6-09`, `adr/0033`) is the receipt for one `operators.active_chats` slot:
  true only for a conversation the automatic assignment engine assigned after `TryClaimAsync` actually
  took a slot, in that same transaction. A conversation an operator picked up by hand
  (`AssignConversationHandler`, behind `OperatorHub.JoinConversationAsync`) takes no slot and carries
  no receipt, which is why closing one must not decrement anything. `Close` and `ReleaseToQueue`
  consume the receipt as part of the same `SaveChangesAsync` as the state transition, so under `xmin`
  a claim cannot be released twice for one close and cannot be released for a close that lost its
  race. Deliberately an ordinary mapped property rather than a shadow property like
  `operators.active_chats` right above: that column has a raw-SQL writer an EF load-mutate-save could
  race, and this one has exactly one writer, the aggregate itself. No index - it is read only as part
  of an aggregate already located by primary key, or of one `GetAssignedToOperatorAsync` already
  materialises.
  **Migration `Stage6AddConversationCapacityClaim` also repairs existing rows**, which a schema
  migration normally has no business doing: it declares every currently-`Assigned` conversation to
  hold a claim and resets each operator's `active_chats` to exactly that count. Both halves have to
  run together, and the reason they run at all is that the pre-`6-09` leak is already baked into every
  deployed database - shipping the fix alone would leave every existing environment exactly as jammed
  as it is, because nothing in the new code path ever revisits a conversation that was already closed.
- `messages` - `id` (uuid v7), `conversation_id`, `sequence`, `author_kind`, `author_id`, `body`,
  `created_at`, `delivered_at?`, `read_at?`.
- `outbox` - `id`, `occurred_at`, `type`, `version`, `payload` (jsonb), `partition_key`,
  `correlation_id`, `published_at?`, `attempts`. See `adr/0005`. `version`/`correlation_id` were
  missing from the first cut - added once `2-04`'s dispatcher needed to reconstruct a complete
  `EventEnvelope` from a claimed row, since dropping `correlation_id` silently defeats its purpose.
- `inbox` - `message_id`, `consumer`, `processed_at`. The idempotency ledger for consumers.
- `roles` - `id`, `site_id`, `name`, `permissions` (`text[]`) - the RBAC model `adr/0016` added,
  built in `1-04`. No management API yet; `1-05`'s seed script and, **as of `10-02`**,
  `RegisterSiteHandler`'s bootstrap transaction (`Ago.Chat.Infrastructure.Postgres.SiteRegistrationRepository`)
  are the only writers - still no general role-management surface (`authorization.md`'s own note on
  this), just a second caller that seeds the same two fixed roles a real self-registered site needs
  instead of only a script-seeded demo one.
- `operator_roles` - `operator_id`, `role_id` - the join table; an operator can hold more than one
  role even though Stage 1 only ever grants the single seeded `"Operator"` role. **`10-02`**: a
  self-registered operator is granted both `"Operator"` and `"Admin"` immediately, the same
  `demo-admin` precedent `5-08`'s seed script already established, in the identical bootstrap
  transaction as `roles` above - `Site` + both `Role`s + `Operator` + both `operator_roles` rows
  commit together or not at all (`RegisterSiteHandler`'s own remarks on why this is deliberately
  wider than this file's usual "one aggregate per transaction" default, below).
- `attachments` (**shipped in `5-03`**) - `id` (uuid v7), `site_id`, `conversation_id`, `message_id?`,
  `object_key`, `content_type`, `size_bytes`, `state` (`pending|ready|deleted`), `created_at`,
  `thumbnail_key?` (**writer shipped in `5-04`** - `AttachmentThumbnailConsumer`; the column itself
  was reserved by `5-03`, unpopulated until then). Its own
  aggregate, not part of `Conversation` (`Ago.Chat.Domain.Attachment`'s own remarks) - it is created
  and later confirmed in its own transaction, never inside the message-write transaction
  (`MessageBatchWriter`, `4-05`), so folding it into `Conversation`'s aggregate boundary would break
  "one aggregate per transaction" the moment a HEAD-verify confirm needed to save without touching the
  conversation. `messages` gained a matching `attachment_id?` column the same change
  (`file-storage.md`: "message references the attachment, not the reverse" - that column is the real
  pointer a reader follows; `attachments.message_id?` is a denormalized second pointer that exists
  only so `5-04`'s orphan sweep can ask "which attachments were never linked to a message" with a
  plain `WHERE message_id IS NULL`, not an anti-join against `messages`). Neither column carries a
  foreign key to the other table - see Keys and indexes below.

## Keys and indexes

- Ids are **UUID v7** (time-ordered). Random UUIDs fragment B-tree inserts; a bigint sequence leaks
  counts and complicates multi-writer scenarios. Any deviation needs an ADR.
- `messages` unique `(conversation_id, sequence)` - enforces per-conversation ordering at the storage
  level and turns duplicate delivery into a no-op insert.
- History reads use **keyset pagination**:
  `WHERE conversation_id = @id AND sequence < @cursor ORDER BY sequence DESC LIMIT @n`.
  `OFFSET` is banned - it degrades exactly where this project is supposed to shine.
- `conversations` partial index on `(site_id) WHERE state = 'waiting'` for the assignment queue.
  **Shipped in `4-01`** (`ix_conversations_waiting`) - this replaced, not added to, EF's own default
  foreign-key index on `site_id`; the only other query filtering by a bare `site_id` in the codebase
  today is `roles`, an unrelated table, so nothing lost coverage. `WaitingConversationClaimQuery`
  (`Ago.Chat.Worker`) is the first real reader, proven with two concurrently open transactions
  actually skipping each other's locked rows, not just asserted from the SQL text.
- `outbox` partial index on `(id) WHERE published_at IS NULL` - the dispatcher must never scan
  already-published rows.

## Partitioning

**Changing, per `adr/0031` (decided 2026-08-25, built by `backlog/13-06`)**: `messages` becomes
multi-level — `PARTITION BY LIST (retention_class)` at the top, each class partitioned by month
exactly as below. The class is stamped from the tenant's tier when a message is written and never
changes, so a tier change moves no rows; the product statement is "history is kept according to the
plan it was written under". Every unique constraint widens by that column again, extending `adr/0019`
rather than reopening it. The rest of this section describes what is shipped today and stays true of
each class's own monthly grid.

**Shipped in `2-06`**: `messages` is `PARTITION BY RANGE (created_at)`, monthly. Rationale: bounded
index size, cheap retention (`DROP` a partition instead of a mass `DELETE`), and a concrete thing to
demonstrate.

`Stage2PartitionMessages` converts the table (rename old, create the partitioned replacement plus
the current month and the next two, copy every row across, drop the old table - Postgres cannot
`ALTER TABLE` a regular table into a partitioned one, `Migrations` below has the reason this is
marked one-way) and `PartitionMaintenanceJob` (`Ago.Chat.Worker`, `PeriodicTimer`, daily) keeps the
current month plus the next two always present afterward, via `CREATE TABLE IF NOT EXISTS ...
PARTITION OF` per partition - idempotent by construction, safe under a missed run or two `Worker`
replicas racing to create the same one.

**Consequence for the uniqueness guarantee** (`adr/0019`): Postgres requires every unique
constraint on a partitioned table - primary key included - to include the partition column. The
primary key becomes `(id, created_at)`, and the `(conversation_id, sequence)` unique index widens to
`(conversation_id, sequence, created_at)`. This is a real weakening: two racing inserts that
land in the same partition with different `created_at` values no longer collide at the storage
level. It is an acceptable one because this index was always the *last* line of defence
(`concurrency.md`) - the first is the `Conversation` aggregate's optimistic-concurrency
load-mutate-save on `xmin`, which still rejects the race that matters (two saves computing the same
`LastSequence`) regardless of what the `messages` index can see.

## Personal data

`personal-data.md` maps which of the tables above hold personal data, and is the file a schema change
updates when it adds a column that holds something about a person. Two properties recorded there are
load-bearing for erasure and are easy to break from here without noticing: `outbox.payload` and
`webhook_deliveries.payload` hold no message bodies, so message content **at rest in Postgres** exists
in exactly two places (`messages.body` and the object store) rather than in every copy an event-driven
system would otherwise scatter.

**Qualified by `16-01`**: "exactly two places" is true of this database and not of the whole system.
The realtime fan-out path publishes a full `MessageDto`, body included, as a persistent message on a
durable broker queue, so message text also exists transiently in RabbitMQ and durably in any node
queue left behind by a replaced pod. `personal-data.md` has the mechanism and the bound; it changes
nothing about this schema, but it does change what "delete the row and you are done" means.

## Access strategy

Writes go through EF Core, one aggregate per transaction, no lazy loading. Reads go through Dapper
with hand-written SQL returning DTOs. Rationale and trade-offs: `adr/0004`.

**One deliberate exception, `10-02`**: `RegisterSiteHandler`'s bootstrap transaction writes `Site` +
two `roles` rows + `Operator` + two `operator_roles` rows together, via
`ISiteRegistrationRepository.TryRegisterAsync` (`Ago.Chat.Application.Abstractions`) - a real,
multi-aggregate provisioning step, not an accidental widening. `1-05`'s seed script already produces
the identical shape non-transactionally (idempotent `ON CONFLICT DO NOTHING` SQL, harmless to
re-run); a real caller hitting `POST /api/v1/sites` gets exactly one attempt, so a partial failure
here must not leave a site with no roles or an operator that resolves to nothing. Every other write
in this codebase still follows the one-aggregate rule above unchanged.

**The one cross-tenant read, `12-02`**: `PlatformOverviewReadStore.ListSitesAsync`
(`IPlatformOverviewReadStore`) is the only query in `ago-chat` that is not scoped to a single
`site_id`. Every other read takes a tenant-scoped id and its `WHERE` clause cannot address another
tenant's rows; this one deliberately takes no site parameter, because "how many accounts exist and what
is each one doing" has no answer inside one tenant. It is safe for a structural reason rather than a
careful one: exactly one endpoint reaches it (`GET /api/v1/owner/sites`), gated exclusively by `12-01`'s
`RequirePlatformOwner` (`adr/0032`), which is satisfied only by a Keycloak *realm* role - no row in
`roles`/`operator_roles`, however broadly seeded, can satisfy it. Read-only: one `SELECT`, no write
surface for the owner exists.

Two things about its shape are worth recording here because the table definitions above do not make them
obvious:

- **`messages` carries no `site_id`.** The tenant is reachable only through `conversations`, so any
  per-site message aggregate is a join (`conversations` filtered by `site_id` via
  `ix_conversations_site_all`, then each conversation's messages on the
  `(conversation_id, sequence, created_at)` unique index).
- **A per-site message count must be time-bounded, not all-time.** Because `messages` is partitioned by
  `created_at` (above), a predicate on that column is what lets Postgres prune to the partitions the
  window covers; an all-time `COUNT(*)` or `MAX(created_at)` reads every partition that has ever existed
  and degrades for the life of the deployment. `12-02` uses a 30-day window - at most two monthly
  partitions - for both its message count *and* its "last activity", the latter being a real narrowing
  of what that field can mean (backlog `12-02` states it). The aggregates are computed per page row, so
  the work per request is bounded by the page size rather than by how many tenants exist.

## Migrations

**Verified**: `Stage1CreateChatSchema` (`1-04`) applied cleanly to a real Postgres (both the
`docker-compose` instance and a throwaway Testcontainers one), all tables/FKs/indexes landed as
designed, and `Ago.Chat.Integration.Tests` proves the unique `(conversation_id, sequence)` constraint
actually rejects a duplicate insert at the storage level. `Stage2AddOutboxAndInbox` (`2-02`) is
verified the same way: `outbox` and `inbox` are real tables (`adr/0005`, `adr/0017`), mapped through
`Ago.Platform.Persistence.Postgres`'s shared configuration rather than hand-rolled here - `outbox`
already has a real writer (`2-02`'s handlers). `inbox` gained its first real writer in `2-05`:
`UnreadCounterConsumer` stages its increment on the tracked `Conversation` and lets
`IInboxChecker.TryRecordAndSaveAsync` commit both in one `SaveChangesAsync` - proven live (real
Postgres, real RabbitMQ) that a redelivered event increments exactly once, not twice.
`Stage2AddConversationUnreadCounts` (`2-05`) adds `visitor_unread_count`/`operator_unread_count` to
`conversations`, both `integer not null default 0` - additive, reversible, no table rewrite.
`Stage5AddOperatorLastReadSequence` (`5-15`) adds `operator_last_read_sequence` the same way, and
deliberately does **not** backfill it from `last_sequence`: no operator has ever marked a conversation
read, so zero is the truthful value for every existing row, and claiming otherwise would be inventing
a fact. The visible consequence is intended - the first open after this ships clears the accumulated
backlog that `5-15` exists to fix.
`Stage2PartitionMessages` (`2-06`) is verified against a real Postgres (`Ago.Chat.Integration.Tests`,
via `PostgresFixture`'s from-scratch migration run): the rename-copy-drop conversion applies
cleanly, an insert landing in the current month succeeds without `PartitionMaintenanceJob` having run
first, and the widened `(conversation_id, sequence, created_at)` unique index still rejects a
duplicate insert post-partitioning. Explicitly one-way (`Down` throws) - see the Partitioning section
above for why reversing it is a data-recovery procedure, not a rollback.
`Stage4AddOperatorActiveChats`/`Stage4AddWaitingQueueIndex` (`4-01`) are both additive and reversible,
verified from-scratch the same way: `active_chats` lands as a genuine EF-visible shadow property
(confirmed by `OperatorCapacityStoreTests`' concurrent-claim proof actually reading/writing it), and
`ix_conversations_waiting` replaces the default FK index cleanly with no query regression found.
`Stage12AddSiteCreatedAt` (`12-02`) is additive and reversible, verified the same from-scratch way
(`PlatformOverviewFixture` migrates a fresh Postgres and then reads the column back through the real
query): one nullable `timestamptz`, no default, no backfill, no table rewrite.

EF Core migrations, one per change, named `<Stage><Verb><Subject>`. Rules:

- Always reversible, or explicitly marked one-way with a comment explaining why.
- Never edit a migration that has been applied anywhere but the local machine.
- Raw SQL (partitions, partial indexes, helper functions) goes into the migration via
  `migrationBuilder.Sql`, never into a hand-run script that will drift.

## AGO Calendar (Stage 20)

A **separate database**, in a separate repository, reached only by `Ago.Calendar.*` hosts. Built by
`20-01` (`Stage20CreateCalendarSchema`, `Ago.Calendar.Infrastructure.Postgres`). The reasoning behind
the two decisions that shaped it - how time is stored, and where the no-overlap guarantee lives - is
`adr/0049`; this section records the shape.

Everything above about **ids (UUID v7), `timestamptz`, keyset pagination, partial indexes for
queue-like predicates, EF for writes / Dapper for reads, and one aggregate per transaction applies
here unchanged**. What follows is only what is specific to this product.

### Tables

- `tenants` - `id`, `name`, `created_at`. The account holder. Structurally what `sites` is for AGO
  Chat and deliberately not that row (`adr/0027`).
- `operators` - `id`, `tenant_id`, `display_name`, `external_subject_id?` (unique when present, the
  same partial-unique shape `adr/0022` added to `ago-chat`'s own table). **No `capacity`, no
  `active_chats`, no `status`** - the absence is the point: `adr/0027` rejected a shared `Operator`
  precisely because a booking queue is a work list, not a set of simultaneous attachments, and nothing
  in this product routes to a *particular* operator.
- `roles` - `id`, `tenant_id`, `name`, `permissions text[]`; `operator_roles` - `(operator_id,
  role_id)`. `adr/0016`'s pattern with an independent vocabulary (`booking:confirm`, `booking:reject`,
  `booking:cancel`, `booking:mark_no_show`, `customer:read`, `customer:edit`, `calendar:configure`).
  **The v1 seeded role set, stated plainly the way `1-05` states AGO Chat's: exactly one role,
  `"Operator"`, holding all seven** - in a one-person business the tenant, the operator and the only
  worker are the same human, so an operator login that could not configure its own calendar would be
  unusable by the target customer. Unique on `(tenant_id, name)`, never on `name` alone. **No writer
  in production yet** - `Role.SeedOperatorRole` exists and the provisioning transaction that calls it
  is `20-06`, the same position `ago-chat`'s `roles` was in at `1-04`.
- `workers` - `id`, `tenant_id`, `display_name`, `is_active`. The person a customer books; not an
  operator, and possibly with no login at all.
- `services` - `id`, `tenant_id`, `name`, `duration_minutes int`. Whole minutes in an integer rather
  than a Postgres `interval`: the domain's own invariant is already "a whole number of minutes", and
  an integer column stays trivially comparable for `20-02`'s availability queries.
- `calendars` - `id`, `tenant_id`, `name`, `time_zone` (**IANA id as text, never an offset**),
  `buffer_minutes`, `is_published`, `created_at`. `buffer_minutes` is per calendar, not per service or
  per worker (the product spec's own decision), and is consumed by `20-02`; nothing reads it yet.
- `customers` - `id`, `tenant_id`, `phone`, `display_name?`, `notes?`, `no_show_count`,
  `first_seen_at`, `last_seen_at`. The lead card. **Unique `(tenant_id, phone)`** - the same person
  booking at two shops is two cards, and one tenant's notes must never surface in another's console.
  That index is also `20-03`'s find-or-create backstop, the same "storage backstop, not the primary
  mechanism" division `adr/0019` draws for chat's message sequence. Personal data: see
  `personal-data.md`.
- `working_hours_rules` - `id`, `worker_id`, `calendar_id`, `day_of_week` (stored as the name, not the
  ordinal - .NET's `Sunday = 0` versus the ISO week is a trap worth not setting), `starts_at`/`ends_at`
  as **`time` without a zone**. Wall clock, deliberately: see `adr/0049`. v1 allows one calendar per
  worker, enforced in the aggregate (`Worker.JoinCalendar`) and **not** as a unique index on
  `calendar_workers.worker_id`, so widening it later removes a check rather than reversing a
  constraint.
- `events` - `id`, `tenant_id`, `calendar_id`, `worker_id`, `service_id?`, `customer_id?`,
  `starts_at`/`ends_at` (`timestamptz`), `local_date` (`date`), `status`, `confirmation_deadline?`,
  `created_at`, plus `xmin`. **One row is both the free slot and the booking that takes it** - status
  transitions, never a second row (`adr/0049`). `tenant_id` is carried even though it is reachable
  through `calendar_id`, deliberately learning from this page's own record that `messages` carries no
  `site_id` and every per-tenant message question is a join forever.
- `calendar_workers` - `(calendar_id, worker_id)`; `worker_services` - `(worker_id, service_id)`. Both
  owned by the `Worker` aggregate, because the invariants they carry are statements about a worker.
- `outbox` / `inbox` - the platform's own tables (`adr/0017`), taken unchanged through
  `ApplyOutboxInboxConfiguration()`. **The first evidence that generalisation was real rather than an
  AGO-Chat-shaped guess**: a second product consumes it with one line and no change to the platform.
  No writer here yet; `20-05`'s SMS event is the first.

### Keys, indexes and the one constraint that matters

- `ix_events_available` - partial, `(calendar_id, starts_at) WHERE status = 'Available'`. The direct
  analogue of `ix_conversations_waiting`: proportional to what is bookable rather than to everything
  ever booked. Proven to be the index the planner reaches for, by `EXPLAIN` against a real Postgres -
  the same bar `4-01` set, and with the same honesty about what that does and does not show (it shows
  an index *can* serve the predicate; whether it is faster than a scan is a measurement, and no
  measurement has been made).
- `ix_events_pending_confirmation` - partial, `(tenant_id, confirmation_deadline) WHERE status =
  'PendingConfirmation'`. Serves both of `20-04`'s readers - the auto-confirm sweep and the operator
  queue - over the same small, short-lived set.
- `ix_calendars_published` - partial on `tenant_id WHERE is_published`.
- `ux_customers_tenant_phone`, `ux_roles_tenant_name`, `ux_operators_external_subject_id` (partial on
  `IS NOT NULL`).
- **`ex_events_worker_no_overlap`** - a GiST **exclusion constraint**, `EXCLUDE USING gist (worker_id
  WITH =, tstzrange(starts_at, ends_at, '[)') WITH &&) WHERE (status <> 'Cancelled')`, needing the
  `btree_gist` extension. This is the no-double-booking guarantee, and it is a constraint rather than
  application code for the reason `adr/0049` argues at length: an aggregate can enforce a rule about
  itself, and only the database can enforce one about the relationship between rows. `'[)'` matches
  `TimeSlot.Overlaps` exactly so adjacent slots do not collide; `Cancelled` is excluded because a
  cancellation frees the time, while `Blocked` and `NoShow` are not, because both still occupy the
  worker.
- Optimistic concurrency is `xmin` on `events`, mapped exactly as `1-04` mapped it on `conversations`.

### Migration

**Verified**: `Stage20CreateCalendarSchema` applies cleanly from scratch to a real Postgres
(Testcontainers, `Ago.Calendar.Integration.Tests`), and is **fully reversible** - including its two
hand-written `migrationBuilder.Sql` statements, which is the half a `DropTable`-only `Down` silently
gets wrong. The reversibility is a test that reverts to `"0"`, asserts the tables, the constraint and
the extension are all gone, re-applies, and asserts they are all back with no pending model changes.
The overlap guarantee is proven by two genuinely concurrent transactions racing for one worker's time,
with the loser refused by `23P01`; deleting the constraint from the migration turns exactly four tests
red, which was checked rather than assumed.

## Provider swap (Stage 9)

`Ago.Chat.Infrastructure.MySql` implements the same ports. Known frictions to document rather than
hide: `jsonb` vs `json`, UUID storage, `SKIP LOCKED` support, partitioning syntax, and
case-sensitivity of identifiers. The honest list of frictions is the point of the exercise.

**AGO Calendar adds the hardest entry on that list so far** (`20-01`): MySQL has neither exclusion
constraints nor range types, so `ex_events_worker_no_overlap` has no translation at all - a MySQL
adapter would need a different *mechanism* (a lock, or a serializable transaction), not different DDL.
Also Postgres-specific here: the partial indexes on `events`/`calendars`, `text[]` for
`roles.permissions`, `tstzrange`, and the `btree_gist` extension. Stage 9 is deprioritized
(`roadmap.md`), and this entry exists so that if it is ever revived nobody discovers the exclusion
constraint by hitting it.
