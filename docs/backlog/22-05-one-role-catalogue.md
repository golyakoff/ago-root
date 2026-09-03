# One person, one role catalogue

- **Stage**: 22
- **Status**: ready
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

- [ ] A person granted `calendar:configure` on the account can act in the calendar without any row
      being created in a calendar-owned identity table.
- [ ] Revoking it stops them, and the delay is bounded and stated — not "eventually".
- [ ] The consumer is idempotent, proven by delivering the same event twice.
- [ ] No calendar handler reads a permission from a token.
