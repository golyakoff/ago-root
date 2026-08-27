# ADR-0068: One identity may hold several tenancies, resolved per request, never baked into the token

- **Status**: Accepted
- **Date**: 2026-08-27
- **Stage**: 13

## Context

`10-02` gave every Keycloak identity at most one `Site`, enforced by a global-unique index on
`operators.external_subject_id`, and deliberately rejected introducing an `Account` aggregate above
`Site` for lack of a second real caller. The author's own domain-registrar analogy (2026-08-27) named the
real caller: one login administering several separately-billed tenants, switching between them, the same
shape a registrar account manages several domains. The author also decided, the same day, that billing
does **not** unify across a login's tenancies — each `Site` keeps its own subscription. That second
decision removes the only reason an `Account` aggregate would have been worth its cost here: there is no
cross-`Site` concept left to model. What remains is narrower — an identity resolving to more than one
`Operator` row — and the question this ADR actually answers is *where the "which tenancy is active right
now" fact lives*.

`OperatorIdentityClaimsTransformation` (`Ago.Chat.Api/Auth`) already resolves `OperatorId`/`SiteId` from
the validated principal's `sub` by querying Postgres **on every request** — it is `IClaimsTransformation`,
not a token claim Keycloak issues, and nothing caches its result across requests. `OperatorHub`/
`VisitorHub` and every REST handler in `Ago.Chat.Api` read the resolved claims from `Context.User`, never
re-deriving `SiteId` themselves. That existing shape is the whole reason this ADR's answer is small.

## Decision

`ResolveOperatorIdentityQuery` gains an optional `RequestedSiteId`, populated from a client-supplied
request header (`X-Ago-Active-Site` or equivalent — name finalised in implementation) rather than from
any server-side session state. `ResolveOperatorIdentityHandler`:

- With the header **absent**, or when the identity has exactly one tenancy: resolves exactly as before
  this ADR — the single matching `Operator` row, or none. No behavioural change for any operator that
  exists today.
- With the header **present**: resolves the `Operator` row matching `(sub, RequestedSiteId)` and *only*
  that row. If no such row exists — the identity is not an operator of the requested site — the request
  is refused, never silently resolved against a different tenancy the identity does hold. Misdirecting a
  request to the wrong tenant, even accidentally, is exactly the failure `docs/architecture/
  tenant-isolation.md` names as this system's worst-case bug; an explicit refusal is the only acceptable
  behaviour on a mismatch.

No new session, cookie, or server-side state of any kind. The Keycloak-issued token is untouched — it
still proves only `sub`; it never learns about tenancies. The console persists the operator's last choice
client-side (e.g. `localStorage`) purely as a UX convenience and resends it as the header on every call;
losing that state costs nothing worse than the switcher defaulting to asking again.

`operators.external_subject_id`'s unique index widens from global to composite `(external_subject_id,
site_id)` — the schema-level expression of "at most one `Operator` row per identity per `Site`," which
was already true of every row that has ever existed, so the migration is additive with nothing to
backfill.

No `Account`/organisation aggregate is introduced. The identity itself is the account; `Site` remains the
sole tenant boundary `docs/vision.md` names.

## Consequences

**Positive**: the mechanism is exactly as stateless as the code it extends — no new infrastructure, no
new failure mode around session/cookie expiry or invalidation, no change to how Keycloak or the token
validation pipeline works. `OperatorHub`/`VisitorHub`, every existing permission check, and RBAC's
tenant-local role scoping (`adr/0016`) are all unaware anything changed; they keep reading
`GetSiteId()`/`GetOperatorId()`. The blast radius is concentrated in one query/handler pair, one console
switcher, and one migration.

**Negative**: the active-tenant header is a value the client controls and must therefore never be
trusted as authorization by itself — every request still re-checks that the resolved `(sub, SiteId)` pair
actually has an `Operator` row before anything downstream trusts `Context.User.GetSiteId()`. A future
reader adding a new claims-resolution path must preserve that check; this ADR's refusal-on-mismatch rule
is the one invariant this whole design leans on. A malformed or forgotten header on a rare hand-built
client call silently falls back to "no requested site" behaviour (today's default resolution) rather than
erroring loudly — acceptable because that fallback can never *widen* access, only fail to narrow it, but
worth naming as a real, deliberate trade rather than an oversight.

**Neutral**: billing, entitlements, and any future per-tenant limit continue to key on `SiteId` alone,
completely unaware an identity may administer more than one. Nothing about seats, tiers, or Stage 13's
other items changes shape because of this decision.

## Alternatives considered

- **A server-side session pinning the active tenant** (a second, app-issued cookie set by a "switch"
  endpoint). Rejected: the resolver already re-queries Postgres on every request with no caching layer to
  invalidate, so a session would be new state solving a problem that does not exist — and it would be the
  one piece of this whole design not already proven in production by every request this API serves today.
- **Baking multiple tenancies into the Keycloak-issued token itself** (a custom Keycloak protocol mapper
  listing an identity's sites). Rejected: `SiteId` has never been a Keycloak-native concept in this
  system — it is resolved by `Ago.Chat.Api` from its own database, deliberately, so that granting or
  revoking a tenancy never requires a Keycloak realm change or a token refresh. Moving multi-tenancy into
  Keycloak would re-couple two things this codebase has kept apart since `adr/0016`.
- **An `Account` aggregate above `Site`, owning many `Site`s.** The design `10-02` already weighed and
  rejected for lack of a caller. The caller now exists, but the author's own no-shared-billing decision
  removes the one property (a cross-`Site` concept worth modelling) that would have justified the cost.
  Revisit only if a real cross-`Site` concept appears later — shared billing, a shared operator directory
  — neither of which exists today.
- **Widening `RegisterSiteHandler`'s uniqueness check but leaving `13-01`'s invite-redemption path
  untouched.** Rejected as an inconsistency, not a real option: `13-01` (unbuilt, `ready`) explicitly
  carries `10-02`'s single-tenant assumption into its own redemption handler. Left alone, it would
  silently reintroduce the constraint this ADR removes through a second door. `13-07`'s own backlog item
  leaves `13-01` a dated note rather than rewriting it now, since `13-01` is not being built in this
  change — but the inconsistency is named here so it cannot be missed later.
