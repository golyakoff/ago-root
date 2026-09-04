# ADR-0100: The caller names the calendar tenant, and the read that authorizes is the read that verifies it

- **Status**: Accepted
- **Date**: 2026-09-04
- **Stage**: 22

## Context

`22-05`/`adr/0093` deleted AGO Calendar's own `operators` table. A calendar operator is now a
subject whose grant arrives from `ago-chat` over `RoleAssignmentsChanged` and lands in
`role_assignment_projections`, keyed `(operator_id, tenant_id)`. Two rows for one subject is
therefore an ordinary representable state — the old model's one-row-per-subject unique index is
gone — and it is the state anyone who works for two shops reaches the moment both enable the
calendar.

`OperatorIdentityClaimsTransformation` asks that projection which tenant a validated `sub` acts in.
It refuses on zero matches and, since `22-05`, on more than one. Refusing rather than guessing is
right: there is no honest answer to "which of these two" without asking somebody. But a refusal here
means no `tenant_id` claim, so the `calendar-operator` policy rejects the principal and **every
calendar screen is absent** — which is also the console's designed rendering for "no permissions"
(`19-03`). A person with a real grant sees exactly what a person with no grant sees
(`backlog/22-14`).

Four earlier decisions constrain the fix.

- **`adr/0022`**: this host validates Keycloak's token and never mints a replacement. There is no
  token exchange and no place to stamp a chosen tenant into a credential at sign-in.
- **`adr/0068`/`13-07`**: `ago-chat` already faced this exact question — one identity, several
  tenancies — and answered it with an `X-Ago-Active-Site` request header plus a `GET
  /api/v1/me/tenancies` enumeration. `ago-console` already sends that header on every authenticated
  chat call and already renders a shop picker.
- **`adr/0093`**: tenancy and identity unify across the two products even though the domains stay
  apart. `RoleAssignmentsChangedConsumer` maps a chat `SiteId` straight onto a calendar `TenantId`:
  the two are the same value.
- **CLAUDE.md rule 8 / `caching.md`**: a write decision may never depend on a cached value, and
  Redis is never a source of truth. `edge.md`/`adr/0014` additionally rule out sticky sessions.

`tenant-isolation.md` classifies every tenant-carrying surface by where its tenant id comes from. Its
most carefully argued category is the one where the **caller names the tenant** — today only the
platform owner's four handlers, each gated by a policy that is the entire access-control story. Any
fix that lets an ordinary operator name a tenant adds the first non-owner member to that category.

## Decision

**The console names the tenant in the `X-Ago-Active-Site` request header, and
`IRoleAssignmentProjectionStore.ResolveTenantAsync` answers it out of that operator's own projection
rows — in the same single read that establishes the grant.**

```csharp
var granted = await db.Set<RoleAssignmentProjectionRecord>()
    .AsNoTracking()
    .AnyAsync(r => r.OperatorId == operatorId && r.TenantId == requested, cancellationToken);

return granted ? requested : null;
```

Both facts are in one `WHERE` clause, so there is no interval between "verified" and "used" and no
separate check a later refactor can drop. Four rules complete it:

1. **Named and held** → that tenant. **Named and not held** → `null`, and specifically *never* a
   fallback to a tenancy they do hold: answering "you asked for A, here is B" is worse than refusing.
2. **Not named, exactly one row** → that tenant, byte-for-byte the pre-`22-14` answer.
3. **Not named, zero or several rows** → `null`, unchanged.
4. A header that is not a `Guid` names no tenant, so it reads as *not named*.

The claim minted afterwards is therefore still something the database said. `tenant-isolation.md`'s
"a server-derived claim" category still describes `tenant_id`; what the caller chose is *which* of
several server-known tenants, never *whether*.

**The same header name as `ago-chat`, not a second one** — the value is one id, and two spellings of
one choice is one more thing that can drift.

`GET /api/v1/me/tenancies` on `Ago.Calendar.Api` enumerates the choice, gated by a new
`calendar-identity` policy (authenticated, nothing more) because the stricter operator policy is
precisely what a two-tenancy identity cannot yet satisfy. It takes no tenant from the caller at all:
the operator id is derived from the token's own `sub`.

## Consequences

**Positive.** The defect closes: a person with two grants reaches both calendars and sees each one's
data. A one-tenancy operator is unaffected — the header they send resolves to their single tenancy,
and with no header rule 2 is the old code path unchanged. Nothing about the console's URLs, routes or
screens changes, and no migration was needed. `ago-console` gained no second switcher: the shop
picker `13-07` already shipped now steers both products, which is what `adr/0093`'s unified tenancy
was for.

**Negative, and this is the real cost.** An ordinary operator can now name a tenant. That moves
`Ago.Calendar.Api` into `tenant-isolation.md`'s caller-chosen category, whose whole point is that it
needs more care than the others — one method now carries a property the rest of the product used to
get by construction. If `ResolveTenantAsync`'s requested branch is ever rewritten to trust its
argument, the resulting hole is a cross-tenant one. `IPermissionChecker` is a genuine second defence
(it refuses per action against the resolved tenant), but relying on it would be relying on a defence
that was never designed to be the last one; the integration test asserts the refusal has an **empty
403 body**, precisely so that "refused by the policy" cannot silently become "refused by the
permission check".

Two smaller costs. The refusal is a bare `403` with no body, so a person who lands on a stale link
naming a shop they no longer work for gets a blank screen rather than a sentence — mitigated only on
`/calendar`, where the console now asks the tenancies endpoint and names the shops that do have a
calendar. And this product now has a route reachable with no tenant resolved at all; there is exactly
one, and its policy is named so a second one cannot appear by accident.

**Divergence from `ago-chat`, deliberately.** That product treats an unrecognised active-site signal
as "no site requested", arguing it can only fail to narrow. Here it would fail to narrow straight
into the single-tenancy fallback, so a request that asked to act in tenant A would quietly act in
tenant B. This product refuses instead. Two transformations that look alike now behave differently on
one input, which is a maintenance hazard worth naming.

## Alternatives considered

**A path segment — `/api/v1/console/tenants/{tenantId}/...`.** The most explicit option, cacheable,
and the shape `ago-chat` already uses for its eleven client-supplied-`siteId` route groups. It lost
on blast radius and on the one-tenant case: every console route and every client call site changes,
each route becomes independently responsible for verification (which is exactly the mistake `17-01`
found in `AssignConversationHandler` — the permission check passed and the object still belonged to
another tenant), and the URLs of the overwhelmingly common single-tenant operator get worse to fix a
minority case. One chokepoint that cannot be forgotten beats thirty that can.

**Re-issuing the tenant as a claim at sign-in.** The most conventional answer, and what most teams
would reach for. It lost on `adr/0022`: this host validates Keycloak's token and mints nothing, so
carrying a chosen tenant in a credential means either a token-exchange service this project
deliberately deleted, or Keycloak learning about `tenant_id` — a product concept in an identity
provider. It also makes switching shops a re-authentication, and the state it optimises for
(a stable choice) is the state that already works.

**A server-side "current tenant" per session.** Redis is present and this would be a few lines. It
lost outright on rule 8: the tenant is the input to every authorization decision in this product, so
caching it is caching an authorization fact. It also needs an invalidation story for a revocation and
gives the API server state where `adr/0014` deliberately left it none.

**Reusing `ago-chat`'s `GET /api/v1/me/tenancies` instead of adding one here.** Tempting, since the
ids are the same and the console already calls it. Rejected: chat lists every shop a person
administers, and a shop only has a calendar once the module is provisioned *and* the grant has
crossed the broker. Asking one product where another product's data is would be guessing on its
behalf — the same category of guess this ADR refuses everywhere else.

**Refusing to create the second grant at all** — the item's own alternative: one person, one tenant,
by policy, enforced loudly at the moment of granting. Defensible, and it needs no header. It lost on
the product: a person who works for two shops is an ordinary customer, not an edge case, and the
enforcement would have to live in `ago-chat`'s granting path for a constraint only `ago-calendar`
has. The author decided for the switcher on 2026-09-04.
