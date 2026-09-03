# ADR-0093: Tenancy and identity unify across products; domains stay apart

- **Status**: Accepted
- **Date**: 2026-09-03
- **Stage**: 22
- **Supersedes**: part of ADR-0027 (its tenancy/identity half; the domain-separation half stands) and
  part of ADR-0091 (its per-product-console premise)

## Context

`adr/0027` decided that each product defines its own `Operator`, its own table, its own RBAC
vocabulary, unified only through a Keycloak `sub`. It named the cost in its own Consequences:
*"provisioning an operator for both products is two actions, not one"*, and a unified queue is
*"more expensive than it would have been under Variant A."* Nothing was missed. The seam was bought.

Three forces have since acted on that purchase.

**The purpose changed.** That ADR's closing argument is that separation *"reinforces the platform
claim... a harder and more honest proof that the platform/product boundary holds."* That is an
argument about demonstrating an architecture. Since 2026-09-02 the project is selling AGO Chat to a
paying client, and the person paying meets the seam as a defect rather than as a proof.

**A third product shipped and did not follow it.** `19-03` (2026-08-31, one week after `adr/0027`)
built `ago-faq` with **no `tenants`, no `operators`, no `roles`** - its only two tables are
`FaqModuleTask` and `KnowledgeBase`. It scopes by the chat `SiteId` directly as its own value type;
its console screens live in `ago-console` (`FaqModulePage`) gated by chat's own `usePermissions()`,
reading their own backend through an optional second origin. No ADR recorded that, so the project has
been running two contradictory patterns with no record of either winning.

**The form the customer is sold is one thing.** The intended flow is a feature list on the tenant's
own settings screen - Telegram bot, MAX bot, WhatsApp, *master calendar for N masters* - where the
calendar is one checkbox among channels. `SubscriptionTierBands` derives a tier from seat count, so
the calendar is not a tier; it is an add-on with its own dimension.

Two constraints bound any answer. `Ago.Platform.*` **ships as NuGet packages** (`adr/0012`), so it
can hold a type but not a row. And rule 8 forbids a write decision reading a cache, so any fact a
product enforces inside a transaction must be local to that transaction.

## Decision

**Domains stay apart. Tenancy, identity, the role catalogue and the console unify.**

`adr/0027` made two decisions in one document. Only one survives re-weighing.

1. **Separate domains - kept, unchanged.** `Worker`, `Event`, `Service`, `WorkingHoursRule` are
   concepts `Ago.Chat.Domain` has no reason to grow. Each product keeps its own repository, its own
   schema and its own API origin. Variant A - one database, one bounded context - stays rejected for
   `adr/0027`'s own reason.
2. **Separate tenancy and identity - superseded.** Concretely:
   - **The account is one row.** A product scopes by its id and does not mint tenancy of its own.
   - **One person is one Keycloak subject and one row on the account side.** A product holds no
     `operators` table.
   - **One role catalogue, on the account side.** The two vocabularies are disjoint by prefix
     (`booking:*`/`calendar:*`/`customer:*` against `conversation:*`/`site:*`), so one catalogue
     carries both with no renaming.
   - **A product reads permissions from a projection replicated into its own database**, not from a
     token claim - so every enforcement point reads the fact inside its own transaction (rule 8), and
     a revoked permission does not survive until a token expires.
   - **One console.** A product's screens live in `ago-console`, permission-gated, talking to that
     product's own API origin, absent rather than broken when it is not configured. This is
     `19-03`'s shipped shape, named here as the pattern rather than left as one product's habit.

**A product's tenancy row *equals* the account id rather than being replaced by it.** The row stays:
in AGO Calendar nine tables hold a foreign key to it, and a granted quota has to be readable inside a
calendar transaction. Keeping it also keeps a product provisionable standalone - a door worth not
welding shut, at the price of a table that had to exist anyway.

**Hostnames follow.** `adr/0091` settled *"the bare product name is that product's console, `-api` is
its API"*; its premise is a console per product, which this ADR removes. Replaced by: **a hostname is
either the console (`office.`), one product's API (`<product>-api.`), or a thing that is not ours to
name.** Bare product names disappear.

## Consequences

- **AGO Calendar is the outlier and pays the migration.** Three identity tables drop, a projection
  appears, an SPA changes repository, and two hostnames retire. Stage 22 is nine items for one
  product catching up with a pattern the newest product already had.
- **The window for doing it cheaply is open now and closes on its own.** `ago_calendar` holds eleven
  migrations and zero rows: no data migration and no customer to disturb - until the first tenant
  exists.
- **Tenant lifecycle becomes cross-product work**, and this is the honest cost. Suspension needs a
  local `active` flag kept fresh, because rule 8 forbids asking the account side at booking time.
  Erasure spans two databases over at-least-once delivery and must be *provable*, not merely sent
  (`personal-data.md`, `16-03`). Export gathers from both. **None of this is caused by the decision
  above** - two schemas buy it, and it appears under every alternative here, including the rejected
  platform-hosted tenant.
- **A projection is machinery.** One event contract and one idempotent consumer per product, plus a
  staleness bound that has to be a stated number rather than "eventually".
- **`adr/0027`'s claims-transformation duplication argument still holds** and is untouched: the
  five-line mapping stays per-product, because the row shape it maps into is the part that differs.
- **The platform gains nothing.** No new package, no new deployable, no `Ago.Platform.Tenant`. What
  unifies is the account side, which is product code.

## Alternatives considered

- **Leave `adr/0027` as it is and hide the seam** - cross-links between two consoles, provisioning in
  two places, roles assigned twice. Rejected: it is what exists, and it is what the customer
  experiences as a defect. `adr/0027` itself flagged the cross-product convenience as *"a real gap,
  named"* and *"not scoped anywhere yet"* - it has been unscoped for ten days.
- **Variant A: one database, one bounded context.** Still rejected, for `adr/0027`'s reason -
  `repositories.md`'s test for a separate repository, and a merged context that cannot later be
  split. The domain half of that ADR was right.
- **Hoist `Tenant` (or `Account`) into `Ago.Platform.*`** - the option the author proposed directly,
  and the one most teams would reach for. Rejected on a mechanical ground rather than a purity one:
  **the platform ships as NuGet packages**, so a `Tenant` there is a shared *type* with no shared
  *data* and nothing unifies at runtime. Unifying for real needs either a schema both products read
  (which is Variant A) or a new deployable on every request path - and rule 8 pushes the data back
  into each product regardless, since no transaction can read another service. It also fails
  `clean-architecture.md`'s platform test, which `adr/0027` already applied to reject a shared
  `Operator`: a tenant carrying tier, seat limit and entitlements *is* a domain concept.
- **A separate `Account` aggregate on the chat side**, renaming `Site`. Considered and **deferred**,
  not rejected: `Site` is already an account in substance (`Id`, `PublicKey`, `Name`, `CreatedAt`,
  `Tier`, `SeatLimit` - nothing chat-specific), and `10-02` and `13-07` both declined the aggregate,
  the second with real requirements in hand. The rename touches `SiteId` in 458 of `ago-chat`'s 1067
  files and buys nothing this decision needs. A naming debt, recorded, not paid here.
- **Permissions in the token instead of a projection.** Simpler and rejected: a revoked permission
  stays valid until the token expires, and a write gated on a claim is a write decision reading a
  cache. `adr/0016`'s RBAC already resolves per request from the database, so the projection is a
  second instance of a shipped mechanism rather than a new one.
