# One login, several tenants — a switcher instead of a second registration

- **Stage**: 13
- **Status**: done (2026-08-27)
- **Depends on**: `10-02-site-and-operator-registration.md` (shipped) — extends `RegisterSiteHandler`'s
  provisioning path rather than replacing it; this is exactly the "Stage 13, real requirements in hand"
  revisit that item's own Out of scope section named when it deliberately rejected a separate `Account`
  aggregate. **Touches `13-01-operator-invitations-and-seat-entitlement.md` (not yet built) — see Scope.**

## Why this exists, and why now

The author's own analogy (2026-08-27): buying a second domain at a registrar does not mean registering a
second account — you see a switcher between the domains one login administers, and each domain is still
billed on its own line. `10-02` built the opposite: one Keycloak identity resolves to at most one `Site`,
enforced by a database-level unique constraint, with a second `POST /api/v1/sites` from the same identity
refused `409`. That was the right call *then* — no second caller existed yet (`10-02`'s own Out of scope:
"introducing a new aggregate for a concept with exactly one caller today... flagged explicitly for whoever
plans Stage 13 to revisit with real requirements in hand, not solved here"). The requirement is now real.

**The author also explicitly decided (2026-08-27) that billing does *not* unify across a login's
tenancies** — no shared subscription, each `Site` keeps its own separate paid line, Fornex-style. That
decision is what keeps this item small: it removes the only reason a new `Account` aggregate would have
been worth its cost. There is nothing above `Site` to model. The "account" in the registrar analogy is
simply the Keycloak identity itself, now permitted to hold more than one `Operator` row.

## Context to read first

`docs/backlog/10-02-site-and-operator-registration.md` in full — the exact provisioning transaction this
item's registration change extends, and the Account-aggregate rejection this item is the deferred
revisit of. `docs/architecture/authorization.md`'s `OperatorIdentityClaimsTransformation`/
`ResolveOperatorIdentityHandler` section — **the one place `SiteId` is resolved, and the only place this
item's real mechanism lives**: it already re-resolves `OperatorId`/`SiteId` from the database on every
single request (it is not baked into the Keycloak-issued token, and it is not cached) — this item widens
what that resolution can return, it does not add a new resolution mechanism. `docs/architecture/
tenant-isolation.md` — the correctness property this item must not weaken: a request must never resolve
to a `SiteId` the calling identity is not an `Operator` of. `docs/adr/0016-rbac-authorization-model.md` —
roles stay tenant-local, unchanged by this item. `docs/adr/0032-*`/`docs/adr/0063-*` (platform owner) —
read to rule out, not to reuse: the platform owner is a different, read-only, single realm role with no
`operators` row at all; this item is ordinary multi-row RBAC, not a platform-owner extension.

## Scope

- **Migration** (`Stage13RelaxOperatorIdentityUniqueness`): `operators.external_subject_id`'s existing
  index (`IsUnique()`, globally, `OperatorConfiguration.cs`) becomes a composite unique index on
  `(external_subject_id, site_id)`. One identity, many `Operator` rows — at most one per `Site`, exactly
  as before *per site*. Additive and reversible; no existing row violates the new constraint, since every
  row today is already unique on the old, stricter key.
- **`RegisterSiteHandler`**: the "identity already resolves to an `operators` row anywhere → `409`" check
  is removed. A `sub` with an existing tenancy provisions another `Site` + two `Role` rows + one
  `Operator` row exactly the way a first-time caller does today — same one-transaction shape `10-02`
  already built, now callable more than once per identity.
- **New read**: list the calling identity's tenancies — `(SiteId, Site.Name)` pairs, ordered however is
  simplest to state (state the chosen order once implemented) — for the console switcher. State the final
  route/handler name once written; the natural home is beside `ResolveOperatorIdentityHandler`, since it
  is the same query with the `LIMIT`/uniqueness assumption removed.
- **The one real mechanism this item adds**: `ResolveOperatorIdentityQuery`/`ResolveOperatorIdentityHandler`
  gain an optional *requested* `SiteId`, sourced from a client-supplied request header (name it once
  chosen, e.g. `X-Ago-Active-Site`). When present, the handler resolves the `Operator` row matching
  `(sub, requestedSiteId)` and rejects the request (401/403 — state which) if no such row exists — **never**
  silently falls back to a different one of that identity's tenancies, since that would be exactly the
  cross-tenant misdirection `tenant-isolation.md` forbids. When absent, or when the identity has exactly
  one tenancy, resolution is byte-for-byte what it is today — **every existing single-tenant operator
  (which today means every operator that exists) sees zero behavioural change**, proven as a regression
  test, not assumed. This stays exactly as stateless as the resolver already is: no new cookie, no
  server-side session, no change to how the Keycloak-issued token itself is validated — the header is
  read fresh on every request, the same way `sub` already is.
- **`OperatorHub`/`VisitorHub`**: no code change — both already read `Context.User.GetSiteId()` from
  whatever the claims transformation resolved for that connection; a tenant switch is a hub reconnect
  (the console already reconnects on other claims-affecting events), not a new code path.
- **Console**: a switcher rendered only when the tenancy list has more than one entry, persisting the
  chosen `SiteId` (e.g. `localStorage`, the same durability class `ago-widget`'s own session storage
  already uses for comparable per-origin state) and attaching it as the header on every API/hub call once
  chosen. A single-tenant operator sees no new UI at all.
- **`docs/backlog/13-01-operator-invitations-and-seat-entitlement.md` gets a short note, not a rewrite**:
  that item's own Scope (written before this one, still `ready`, not yet built) explicitly carries
  forward `10-02`'s "one identity, one site" constraint into invite redemption ("a `sub` that already
  resolves to an `operators` row on *any* site... is rejected `409` here too... this codebase's operator
  model has no concept of one identity holding rows on more than one site, and this item does not
  introduce one"). This item makes that sentence false. Add a dated note pointing whoever builds `13-01`
  at this item, so the redemption handler relaxes the same check `RegisterSiteHandler` relaxes here,
  rather than silently reintroducing the single-tenant assumption through the other door.
- **`docs/adr/0068-*`** (pre-assigned, free — see `docs/adr/README.md`): records the header +
  per-request-re-resolution mechanism, why it needed no new session/cookie machinery, and why no
  `Account` aggregate was introduced (billing stays per-`Site`, the author's own 2026-08-27 decision).

## Out of scope

- **Any billing/subscription unification across a login's tenancies.** Explicitly rejected by the author:
  each `Site` keeps its own separate subscription. `13-02`/`13-04` stay keyed by `SiteId` exactly as
  already planned — this item changes nothing about how billing is scoped.
- **A new `Account`/organisation aggregate.** `10-02` weighed one and rejected it for lack of a second
  caller; this item supplies the caller but the author's own billing decision above removes the only
  reason one would still be worth its cost. If a real cross-site concept ever needs modelling above
  `Site` — shared billing, a shared operator directory — that is new, separately-justified scope, not
  built speculatively here.
- **Inviting other people into a `Site` one already administers.** That is `13-01`'s own job (still
  `ready`, unbuilt) — a `Site` having several operators. This item is the opposite direction: one
  identity reaching several `Site`s it administers. The two combine (an identity could hold an invited
  seat on one `Site` and have registered another itself) but neither requires the other.
- **Any change to RBAC, tenant data isolation, or `OperatorHub`/`VisitorHub`'s own authorization logic.**
  None of those change — they keep reading `GetSiteId()`/`GetOperatorId()` exactly as today, unaware the
  identity behind either claim may now have more than one tenancy.
- **A UI for discovering or joining a public tenant.** Registering a new `Site` (`RegisterSiteHandler`)
  remains the only way an identity gains a tenancy, same as `10-02` — this item only lets that path be
  called more than once per identity and adds a way to switch between the results.

## Done when

- [x] `Ago.Chat.Integration.Tests`: a single real Keycloak-signed identity calls `POST /api/v1/sites`
      twice and ends up with two `Site` rows and two `Operator` rows (`external_subject_id` equal,
      `site_id` different) — verified by querying the rows directly, not just asserting two `201`s.
      Also proven live, against the deployed cluster: `demo-admin` registered a real second `Site`
      through the running API, `201`, no `409`.
- [x] A request carrying the active-site header for a `Site` the calling identity holds **no** `Operator`
      row on is refused, not silently resolved against a different one of that identity's tenancies or
      against the wrong site — a real permission-boundary test, since getting this wrong is a cross-tenant
      hole, `tenant-isolation.md`'s own worst-case failure mode.
- [x] A pre-existing, single-tenant identity (e.g. `demo-operator`) resolves identically with the header
      absent as it did before this item — a real regression test proving zero behavioural change for
      every operator that exists today, not an assumption.
- [x] A multi-tenant identity switching the header between its two `Site`s gets the correct, distinct
      `SiteId`/`OperatorId` claim pair each time, proven against a real `RequireOperatorIdentity`-gated
      route (e.g. the queue), not asserted from the handler alone.
- [x] Console: the switcher renders only when `GET` (the tenancy list) returns more than one entry;
      picking a different tenancy changes the active `Site` for every screen that reads it (queue,
      widget settings, etc.) without a fresh login; a single-tenant operator's console renders with no
      switcher visible at all — proven by a DOM test, and live: registering `demo-admin`'s second `Site`
      made the switcher appear against the real deployment on the very next load.
- [x] `docs/adr/0068-*` written and indexed, recording the mechanism and the no-`Account`-aggregate
      decision.
- [x] `docs/backlog/13-01-operator-invitations-and-seat-entitlement.md` carries the dated cross-reference
      note described in Scope.
- [ ] `docs/architecture/authorization.md`'s `OperatorIdentityClaimsTransformation` section updated to
      describe the widened resolution (optional requested site, fallback rule, the "never misdirect"
      guarantee) — **not done**, left as a real, small, named doc gap rather than silently skipped.

## What live verification found that no test did

Automated tests proved the mechanism correct in isolation; deploying it and actually registering a
second `Site` under one identity for the first time surfaced two real defects neither review nor the
test suite had reached, both from the identical root cause — every operator that existed before this
item had exactly one tenancy, so nothing before now had ever exercised the genuinely-more-than-one path
live:

- **The operator hub raced `PermissionsProvider`'s async tenancy resolution.** React mounts effects
  child-first; `OperatorConnectionProvider` (a child of `PermissionsProvider`) started the hub
  unconditionally on mount, before the parent's own effect had resolved and published the active-site
  signal. Invisible for a single tenancy (the resolver's fallback treats an absent signal identically to
  an explicit one when there is only one to choose from) — real for two. Fixed: the hub now waits for
  `usePermissions().tenancies` to resolve before connecting (`golyakoff/ago-console#40`).
- **`OperatorConnection`'s constructor froze the hub's URL — including the `activeSite` query
  parameter — before the signal could exist.** The first fix alone was not sufficient: it deferred
  *when* `start()` was called, not *when the connection object itself, and its URL, were built* — and
  `stop()`/`start()` on this class always reuses the same underlying `signalR.HubConnection` by design.
  Fixed: the connection is now built lazily, inside `start()`, the first time it actually runs
  (`golyakoff/ago-console#41`).

Both shipped and redeployed the same session; the live browser check that found them was rerun clean
afterward (`Operator hub: Live`, no negotiate errors).

## Not verified

**`docs/architecture/authorization.md` was not updated** — the one Done-when box left unchecked above.
A real, small, named gap, not silently dropped.

## Open questions

None. The only real product question — whether billing unifies across a login's tenancies — was decided
by the author on 2026-08-27 (no). The mechanism follows directly from how `OperatorIdentityClaimsTransformation`
already works today (per-request DB re-resolution, no token mutation), which this item widens rather than
replaces.
