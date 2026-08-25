# AGO Calendar: domain model and persistence

- **Stage**: 20
- **Status**: done (2026-08-25) — `ago-calendar` `feat/20-01-domain-and-persistence`; 89 tests green
  (16 architecture, 56 domain, 17 integration), zero build warnings
- **Depends on**: `20-00-repository-scaffold-and-platform-consumption.md`

## Goal

`Ago.Calendar.Domain` exists with real invariants for every entity the product needs — `Tenant`,
`Operator`, `Worker`, `Service`, `Calendar`, `Customer`, `WorkingHoursRule`, `Event` — and
`Ago.Calendar.Infrastructure.Postgres` persists them, migrated from scratch and verified the same way
`1-04`'s own `Stage1CreateChatSchema` was. This is Stage 20's own `1-01`/`1-04` combined: the shape,
not yet the booking behaviour that shape exists to support (`20-03`/`20-04`).

## Context to read first

The product spec this stage plans against, in full — every relationship and invariant named there is
a direct requirement, not a suggestion: `Tenant 1──*Calendar`, `Tenant 1──*Worker`, `Tenant 1──*Service`,
`Tenant 1──*Customer`, `Calendar *──*Worker`, `Worker *──*Service`, `Worker 1──*WorkingHoursRule`
(scoped to the pair `(Worker, Calendar)` — v1 is one worker in exactly one calendar, a deliberate
simplification stated explicitly below, not an oversight), and `Event *──1 Calendar, *──1 Worker,
*──0..1 Service, *──0..1 Customer` with `Event.Status ∈ {Available, PendingConfirmation, Booked,
Cancelled, NoShow, Blocked}`. `docs/architecture/clean-architecture.md`'s Domain rules — no public
setters, intention-revealing methods, time and identity passed in never read, domain events not wire
contracts — apply to every entity here exactly as they already do to `Ago.Chat.Domain`.
`docs/architecture/data-model.md`'s "Keys and indexes" section — UUID v7 ids, the same reasoning
applies here (time-ordered inserts). `docs/adr/0027-operator-identity-across-products.md` — `Operator`
here is a genuinely new entity, not a reference to anything in `Ago.Chat.Domain`; carries no
`active_chats`/capacity concept at all, since a pending-bookings queue (`20-04`) is not a
concurrent-conversation capacity limit. `docs/adr/0016-rbac-authorization-model.md` — the same
`Permission`/`Role` pattern this item's own `Operator` role model follows, with a new, independent
`resource:action` vocabulary (`booking:confirm`, `calendar:configure`, ...) — state the seeded v1 role
set explicitly, mirroring `1-05`'s single hardcoded `"Operator"` role for Stage 1.

## Scope

- Domain entities and value objects, each with real constructors/factory methods rejecting invalid
  state (`clean-architecture.md`'s "no such thing as a validated-somewhere-else entity"):
  - `Tenant` — the account holder; configures everything else, never a booking-flow participant itself.
  - `Operator` — created by a `Tenant`, resolved from Keycloak's `sub` via its own
    `OperatorIdentityClaimsTransformation` (copied from `adr/0022`'s pattern, per `adr/0027` — a new,
    small file in this repository, not a shared one).
  - `Worker` — belongs to exactly one `Tenant` (never two, stated as a real invariant the constructor
    enforces, not just documented); `Calendar`/`Service` memberships are separate many-to-many joins.
  - `Service`, `Calendar` (carries `BufferMinutes`, the per-calendar spacing config — not per-service,
    not per-worker, a deliberate choice stated in the product spec).
  - `Customer` — the lead card: name, notes, booking history reference, no-show flag, keyed by phone
    number; no account, no password.
  - `WorkingHoursRule` — scoped to `(WorkerId, CalendarId)`; v1 enforces exactly one calendar per
    worker at the domain level (a factory-method invariant, not just an unenforced convention) — state
    explicitly, in the response, that this is the deliberate simplification the product spec names, not
    an accidental ceiling, and that widening to M:N later is additive (a new join table plus relaxing
    this one constructor check), not a rewrite, matching `clean-architecture.md`'s own "promotion is
    cheap" framing applied to loosening rather than tightening a rule.
  - `Event` — the central type. `Event.Status` transitions are intention-revealing domain methods
    (`Event.Claim(customerId, now, confirmationDeadline)` for `Available → PendingConfirmation`,
    `Event.Confirm(now)`, `Event.Reject(now)`/`Event.Cancel(now)`, `Event.MarkNoShow(now)`), each
    rejecting the wrong starting state the same way `Conversation.AssignTo` already does in
    `Ago.Chat.Domain`. State explicitly, in the response, why `Event` is one row with a status column
    rather than a separately-modelled "slot" plus a separately-modelled "booking" — the product spec's
    own reasoning (a real `WHERE Status = 'Available'` compare-and-set inside a transaction is the
    booking claim itself, not a cache check or an application-level optimistic lock,
    `CLAUDE.md` rule 8) is the one to restate here, not reinvent.
- Migrations (`Stage20CreateCalendarSchema` or split per the `db-migration` skill's own guidance on
  when one migration is too much): `tenants`, `operators` (with `external_subject_id`, nullable, unique
  when present — the same shape `adr/0022` added to `ago-chat`'s own `operators` table), `workers`,
  `services`, `calendars`, `customers`, `working_hours_rules`, `events`, plus the `calendar_workers`
  and `worker_services` join tables. Ids are UUID v7 throughout (`data-model.md`'s own rule, applies
  unchanged). `roles`/`operator_roles` mirroring `ago-chat`'s own RBAC tables, seeded with one v1 role
  (state its exact name/permission set once written, matching `1-05`'s precedent for stating this
  plainly rather than leaving it implicit).
- Indexes: at minimum a partial index on `events` for `WHERE status = 'Available'` scoped by
  `(calendar_id, starts_at)` — the read `20-03`'s booking claim needs, mirroring
  `ix_conversations_waiting`'s own reasoning (`data-model.md`) applied to a different query shape.
- `Ago.Calendar.Application.Abstractions` gains the read/write ports this layer's own use cases will
  need (`ITenantRepository`, `IOperatorRepository`, ... following `IConversationRepository`'s own
  "shaped by the use case, not the storage engine" rule) — declare only what `20-02`/`20-03`/`20-04`
  actually call, not a speculative full CRUD surface for every entity.

## Out of scope

- Any use case beyond what a domain-only slice needs for its own tests (create a tenant, add a worker,
  transition an event through its states) — the real booking/materialization use cases are `20-02`
  onward.
- The console or any HTTP surface — `20-06`.
- Widening `WorkingHoursRule` to M:N workers-per-calendar — named above as a deliberate v1 limit, not
  this item's job to relax.

## Done when

- [x] `Ago.Calendar.Domain.Tests`: every entity's invariants are proven — a `Worker` cannot belong to
      two tenants, an `Event` cannot transition from `Booked` back to `Available`, `WorkingHoursRule`
      rejects a second calendar for the same worker, `Event.Claim` on an already-`PendingConfirmation`
      row throws the same class of state-invariant exception `Conversation.AssignTo` already
      establishes the pattern for.
      Done: 56 tests, no infrastructure. "Cannot belong to two tenants" is enforced in the two ways it
      is actually broken — `Worker.JoinCalendar`/`Worker.Offer` take the whole related aggregate, not
      an id, so the cross-tenant check is an invariant rather than something each caller must remember.
      Includes `DaylightSavingTimeTests` (`America/New_York`, not `Europe/Moscow` — Russia has not
      observed DST since 2014, so a Moscow-only test would pass against code storing a fixed offset),
      which `date-and-time.md` asks for by name.
- [x] Migration applies cleanly to a real Postgres (Testcontainers), reversible or explicitly marked
      one-way with a stated reason, matching `data-model.md`'s own migration rules.
      Done: `Stage20CreateCalendarSchema`, **fully reversible including its two hand-written
      `migrationBuilder.Sql` statements** — `MigrationReversibilityTests` reverts to `"0"`, asserts the
      tables, the exclusion constraint and the `btree_gist` extension are gone, re-applies, and asserts
      all three are back with no pending model changes.
- [x] `Ago.Calendar.Integration.Tests`: the partial `Available`-status index is actually used by the
      query it exists for (confirmed the same way `4-01`'s own waiting-queue index was — `EXPLAIN`
      output or an equivalent concurrency proof, not asserted from the migration text alone).
      Done: `EXPLAIN` under `SET LOCAL enable_seqscan = off` names `ix_events_available`, and the same
      for `ix_events_pending_confirmation`. Stated honestly in the test: this shows an index *can*
      serve the predicate, not that it is faster than a scan — that would be a measurement, and none
      was made.
- [x] `docs/architecture/data-model.md` gains a short "AGO Calendar" section (or a pointer to wherever
      `ago-calendar`'s own copy of this doc lives, if this project's docs end up split per-repository —
      state which, once decided) recording the schema shape and the reasoning above, matching how this
      file already documents `ago-chat`'s own schema in full.
      **Decided: one file, in `ago-root`, not a per-repository copy.** Every other architecture
      document here already spans both products in place (`repositories.md` and
      `naming-and-structure.md` both gained `ago-calendar` rows in `20-00`), `ago-root`'s stated job is
      to hold the rules for the whole platform while code lives elsewhere, and a split would put the
      two schemas where a reviewer comparing them cannot see them side by side. The file now opens by
      saying it covers two databases.
- [x] Beyond the original list: `docs/architecture/personal-data.md` gains AGO Calendar's three
      personal-data rows. Not in this item's scope as written, and required by the `db-migration`
      skill's own rule — `customers.phone` is the most directly identifying column either product has.

## Decisions taken while building this

Recorded here because they were judgment calls, not mechanics.

- **`adr/0049`** covers the two that were worth arguing about, as one ADR because they cannot be made
  independently: *what time is stored in what* (instants on `events`, wall clock on
  `working_hours_rules`, one IANA zone on `calendars` as the single bridge, nothing about the
  customer's zone), and *where the no-overlap guarantee lives* (a GiST exclusion constraint, because
  an aggregate can enforce a rule about itself and only the database can enforce one about the
  relationship between rows).
- **The CLR type is `BookingCalendar`, the table is still `calendars`.** A type named `Calendar` in
  `Ago.Calendar.Domain` is unreferenceable from any other project in the repository: from inside
  `Ago.Calendar.Infrastructure.*` the simple name resolves to the enclosing *namespace* `Ago.Calendar`
  before a `using`-imported type is considered (CS0118 — reproduced deliberately before renaming
  rather than assumed). The alternatives were a `using` alias in every consuming file, which this
  project's conventions rule out, or qualifying every reference. Nothing leaks to the schema.
- **`events` carries `tenant_id`** even though it is reachable through `calendar_id` — learning from
  this repository's own record that `messages` carries no `site_id` and every per-tenant message
  question is a join forever. `20-04`'s tenant-wide pending queue would be exactly that join.
- **The v1 seeded role is one role, `"Operator"`, holding all seven permissions** including
  `calendar:configure`, because the product spec's own framing is that one person is the tenant, the
  operator and the only worker. Stated in `Role`, asserted in a test, and recorded in `data-model.md`.
- **The platform package pin moved 0.16.0 → 0.18.0** in the same branch (`7-09`/`adr/0046`'s telemetry
  split). One line, because no host here ever called `AddPlatformObservability`; `Ago.Calendar.Worker`
  deliberately takes **no** `Ago.Platform.Observability` reference, and its restore graph now resolves
  **zero** OpenTelemetry packages where `20-00`'s Open questions section counted eight.

## Deliberately left for later

Named so the next item does not have to work out what is missing.

- **`20-02`**: the materialiser itself, and with it the only code that converts wall clock to instants
  (`CalendarTimeZone` → `TimeZoneInfo`, in Infrastructure). Also the Dapper read store for
  availability — `adr/0004`'s read side needs a read model, and this item builds none, which is why
  Dapper is not even a package reference yet.
- **`20-03`**: `IEventRepository` deliberately has **no** `TryClaimAsync`. The atomic
  `UPDATE ... WHERE status = 'Available'` is that item's centrepiece, and its port's shape depends on
  decisions it has not made — whether the claim shares a transaction with the customer's
  find-or-create, and what a loser gets back. What this item ships is what makes either shape safe:
  `xmin` on `events`, the exclusion constraint, and the two translated exceptions
  (`EventConcurrencyConflictException`, `SlotOverlapException`).
- **`20-04`**: the confirmation sweep and the operator queue. Their index
  (`ix_events_pending_confirmation`) exists and is proven; the job does not. `Event.Confirm`
  deliberately does not check the deadline — the sweep confirms after it and an operator may confirm
  before it, so the timing rule belongs to the caller.
- **Re-offering a vetoed slot.** No transition back to `Available` exists on `Event`. The product spec
  leaves "released or cancelled, depending on how close the start is" to implementation, and a
  transition built before that decision would be a guess with a customer's booking attached.
- **`20-06`**: the provisioning transaction that writes the seeded role, this product's own
  `OperatorIdentityClaimsTransformation`, and `IPermissionChecker`. `roles`/`operator_roles` therefore
  have no production writer yet — the same position `ago-chat`'s own `roles` was in at `1-04`.
- **`20-05`**: the first outbox writer. The tables exist from this migration (one line,
  `ApplyOutboxInboxConfiguration()`), so that item does not have to change the schema to send its
  first SMS.
- **No `IServiceRepository`-style CRUD beyond what has a named caller**, no read models, no use cases,
  no HTTP surface, and no `deploy` overlay — this item is the shape, not the behaviour.

## Open questions

None — the entity list, relationships, and the "`Event` is one real row, not a computed slot" design
decision are all fixed by the product spec this stage plans against; nothing here is left for this
item's own judgment beyond ordinary schema/migration mechanics already covered by `data-model.md`'s
existing rules.
