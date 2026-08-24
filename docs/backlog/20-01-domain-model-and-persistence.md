# AGO Calendar: domain model and persistence

- **Stage**: 20
- **Status**: ready
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

- [ ] `Ago.Calendar.Domain.Tests`: every entity's invariants are proven — a `Worker` cannot belong to
      two tenants, an `Event` cannot transition from `Booked` back to `Available`, `WorkingHoursRule`
      rejects a second calendar for the same worker, `Event.Claim` on an already-`PendingConfirmation`
      row throws the same class of state-invariant exception `Conversation.AssignTo` already
      establishes the pattern for.
- [ ] Migration applies cleanly to a real Postgres (Testcontainers), reversible or explicitly marked
      one-way with a stated reason, matching `data-model.md`'s own migration rules.
- [ ] `Ago.Calendar.Integration.Tests`: the partial `Available`-status index is actually used by the
      query it exists for (confirmed the same way `4-01`'s own waiting-queue index was — `EXPLAIN`
      output or an equivalent concurrency proof, not asserted from the migration text alone).
- [ ] `docs/architecture/data-model.md` gains a short "AGO Calendar" section (or a pointer to wherever
      `ago-calendar`'s own copy of this doc lives, if this project's docs end up split per-repository —
      state which, once decided) recording the schema shape and the reasoning above, matching how this
      file already documents `ago-chat`'s own schema in full.

## Open questions

None — the entity list, relationships, and the "`Event` is one real row, not a computed slot" design
decision are all fixed by the product spec this stage plans against; nothing here is left for this
item's own judgment beyond ordinary schema/migration mechanics already covered by `data-model.md`'s
existing rules.
