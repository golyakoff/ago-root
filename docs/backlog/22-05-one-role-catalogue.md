# One person, one role catalogue

- **Stage**: 22
- **Status**: done (2026-09-03), `ago-chat#156` + `ago-calendar#31`
- **Depends on**: `22-02`, `22-03`

## What changes

The calendar stops holding identity. Three tables go — `operators`, `roles`, `role_assignments` — and
what replaces them is a **projection** of the account side's role assignments, replicated over the
outbox that already exists.

`ago-faq` is the reference: it has **no** identity tables at all (`FaqModuleTask` and `KnowledgeBase`
are its only two), and `FaqModulePage` gates on chat's own `usePermissions()`. The calendar is the
product that predates that pattern.

## Why a projection and not claims (decided 2026-09-03)

Every enforcement point reads the fact **inside its own transaction**:

- Rule 8 forbids a write decision reading a cache, and a write gated on a token claim is exactly that.
- A revoked permission carried in a claim stays valid until the token expires.
- It matches what chat already does — `adr/0016`'s RBAC resolves per request from the database, not
  from the token. So this is a second instance of a shipped mechanism, not a new one.

The cost is one event contract and one idempotent consumer. The saving is that **no second mechanism
is needed for menu gating** — the projection answers that question too.

## Why the schema half is smaller than it looks

Measured rather than assumed: only **`role_assignments`** references the calendar `Operator`.
`calendar_memberships` hangs off `WorkerId`, not an operator, and no other table has an operator
foreign key. So three tables drop and one projection table appears.

The weight is in the code, not the schema: 46 files in `Ago.Calendar.Application` touch a permission.

The two vocabularies are **disjoint by prefix** — `booking:*`, `calendar:*`, `customer:*` against
`conversation:*`, `site:*` — so the seven calendar strings join the account catalogue **unchanged**.
That is the single largest saving in this stage and it exists by luck rather than design.

## Done when

- [x] A person granted `calendar:configure` on the account can act in the calendar without any row
      being created in a calendar-owned identity table. — there is no such table left to create a row
      in: `operators`, `roles` and `operator_roles` are dropped.
- [x] Revoking it stops them, and the delay is bounded and stated — not "eventually". — **sub-second
      normally, bounded above by five seconds**: chat's outbox dispatcher publishes on `LISTEN`/`NOTIFY`
      with a 5-second fallback poll, then one broker hop and a consumer commit. No new latency source
      — that was already this path's bound for every other event on it. The checker itself adds no
      window of its own, proven by restaging an empty set and asserting the *very next* request is
      refused.
- [x] The consumer is idempotent, proven by delivering the same event twice. — twice over: the event
      carries a complete set so a replay stages identical values, and the inbox ledger refuses a
      duplicate `message_id` and rolls the redundant stage back with it.
- [x] No calendar handler reads a permission from a token. — proven structurally rather than by
      inspection: `Ago.Calendar.Application` references neither ASP.NET Core nor `System.Security.Claims`,
      so a handler *cannot* read a claim.

## Outcome

Done 2026-09-03. `ago-chat#156` (the account side) merged first, `ago-calendar#31` second.

**A snapshot, not a delta, and that is the decision the rest rests on.** `RoleAssignmentsChanged`
carries one subject's complete current permission set for one site. Ordering is guaranteed only per
subject (rule 6), so a consumer applying "granted" and "revoked" deltas out of order would land on the
wrong state **permanently, with no way to notice**. A snapshot is naturally idempotent and order-safe,
and revocation is the same fact becoming empty rather than a second kind of event — which is why
operator removal needed no special path.

**`OperatorId` stopped being database-assigned without becoming a mechanical rewrite.** It is now a
deterministic RFC 9562 name-based UUIDv5 over the Keycloak `sub`, hand-implemented because no .NET
runtime exposes a version-5 constructor. Rule 2 bans `Guid.NewGuid()` in Domain for non-determinism,
not for touching `Guid`: the same input always gives the same output, with no I/O. Keeping the type
and changing only its provenance is what let roughly forty-six Application files that pass an
`OperatorId` around stay untouched — the same judgement `22-03` made for `TenantId`.

### Two things taken deliberately, both with a price

**The contract was taken early, against this stage's own step 8.** The rollout order says drop the
calendar's identity tables only *once the projection has been serving real traffic, so the rollback
target still exists while it matters*. Here the drop lands in the same migration as the projection.
The reason is that `ago_calendar` holds zero rows in production, so nothing is destroyed — but the
price is real and is recorded rather than left to be discovered during an incident: **after this
migration, rolling back to the previous calendar image requires running `Down()` first**, because the
old image reads tables that no longer exist.

**The architecture test gained an exemption.** `MessageOpacityRule` now skips `Ago.Chat.Domain.Permission`
— the opposite of the coincidental word collisions its existing exemption list holds, because that type
now names booking vocabulary *on purpose*. What the rule protects is untouched: message content stays
opaque, and the scan of Domain/Contracts for `slot`/`service` still runs and would still catch a
booking-shaped field on a wire contract.

### What it left behind

- **`22-13`** — registering `AddRabbitMqMessaging` in `CalendarModule` made broker settings mandatory
  for **both** calendar hosts, including the API, which never dials the broker. Neither manifest carried
  them and the network policy blocked the pods. Found reading the module, not in the report.
- **`22-14`** — a subject with calendar permissions on two tenants now resolves to no tenant, so the
  calendar is simply absent for them. Newly representable: the old model had one row per subject with a
  unique index.
- **Not proven end to end.** No real broker round trip exists anywhere in `22-05`. The chat side proves
  the row is staged in the right transaction and the calendar side proves the consumer projects
  correctly; nothing yet proves a publish reaches that consumer. `22-13`'s smoke check is the first
  thing that will say so out loud.
