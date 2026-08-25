# Platform owner identity and access control

- **Stage**: 12
- **Status**: done — `adr/0032`
- **Depends on**: nothing new architecturally — reuses `5-05`'s Keycloak realm and `adr/0022`'s
  direct-JWT-validation shape unchanged. The new pieces are a realm role and one new authorization
  policy, not a new identity architecture.

## Goal

A fourth kind of caller — the **platform owner**, the author acting as operator of the service itself
rather than of any one tenant — becomes a real, provable authentication and authorization state. After
this item, a request or hub connection carrying a token for the designated owner identity is accepted
by a new `RequirePlatformOwner` policy; every other identity, including an operator holding `5-08`'s
per-site `"Admin"` role, is rejected by it. This item builds the access-control boundary only — it
creates no queries and no UI (`12-02`/`12-03`'s job) — but it is where the real security decision lives:
a bug here leaks every tenant's data to whoever ends up holding this identity, so the boundary has to be
provably separate from the per-site RBAC model, not a permission that happens to be granted broadly.

## Context to read first

`docs/architecture/authorization.md` in full — the three-actor table (Visitor/Operator/
Webhook-integration) and, specifically, the sentence this item has to reconcile with: `adr/0016`'s "a
role is tenant-local, so two sites' roles are independent assignments." A platform owner needs
"every site," which that sentence structurally cannot express without redesigning `Role`. `docs/adr/0016-rbac-authorization-model.md`
in full, especially "The check happens in `Application`... a handler resolves the caller's permissions
for the relevant site/resource" — every existing permission check is anchored to one `site_id`; there is
no site to anchor an owner check to. `docs/adr/0022-oidc-keycloak-operator-authentication.md` — the
claims-transformation pattern (`OperatorIdentityClaimsTransformation`, resolve at request time from a
validated Keycloak token) this item deliberately does **not** reuse, and why: that transformation's
whole job is "find the `operators` row for this `sub`," and the owner is not an `Operator` row. `docs/backlog/10-01-self-registration-identity-flow.md` —
the closest existing precedent for this item's shape: a new, narrower authorization policy added
*alongside* `RequireOperatorIdentity` on the same JWT scheme, not a new scheme, with an explicit
statement of why the two policies must stay distinct. `docs/backlog/5-08-console-attachments-and-admin-role.md` —
the site-scoped `"Admin"` role this item must be provably distinct from; an admin operator today can see
every conversation *for their own site*, nothing more, and this item must not accidentally widen that.
`docs/architecture/repositories.md`'s "Everything is public" / "no secrets, ever" section — why the
owner-role *assignment* itself must never live in a committed file.

## Scope

- **An ADR** (`adr/00XX`) deciding the owner-identity mechanism, with a firm recommendation rather than
  an open toss-up — the same "state the final decision, revisit only if implementation finds a real
  reason to prefer the alternative" shape `10-01`'s own ADR item used:
  - **Recommended: a dedicated Keycloak realm role** (e.g. `platform-owner`), assigned in the same
    realm every operator already authenticates against, checked directly from the validated JWT's
    `realm_access.roles` claim. No `operators` row is created or consulted for this check; no `site_id`
    is ever involved. This reuses the one identity provider the project already trusts (`adr/0022`) and
    needs no new infrastructure, no new secret class, and no parallel auth system.
  - **Rejected: a special "applies to every site" sentinel on the existing `Role`/`Permission` model**
    (e.g. a `Role` with `site_id = null` meaning "all sites"). Would require `PermissionChecker` and
    every future per-site call site to special-case a wildcard scope, which breaks the exact invariant
    `adr/0016` was written to hold ("a role is tenant-local") for the sake of one caller — precisely the
    "speculative structure, one caller" trade `clean-architecture.md` warns against, except backwards:
    here it would be *retrofitting* speculative generality onto an already-shipped, deliberately narrow
    model instead of avoiding it up front.
  - **Rejected: a hardcoded operator id or config value checked directly in application code**,
    bypassing Keycloak. Reintroduces exactly the problem `adr/0022` already rejected once for operator
    login ("a real feature... for a problem every OIDC provider has already solved correctly") — and
    worse here, since what it grants is cross-tenant access to every site's data, with no revocation
    story beyond redeploying a config change. A Keycloak realm-role assignment is revocable from
    Keycloak's own admin console with no code change and no redeploy.
  - State explicitly, in the ADR, why this is **not** `5-08`'s `"Admin"` role under a different name: an
    Admin operator is still an `Operator` row, still resolved through `OperatorIdentityClaimsTransformation`,
    still scoped to exactly one `site_id`, and still checked through `PermissionChecker`'s per-site
    permission resolution. The platform owner has none of that — no `Operator` row, no `site_id`, no
    `PermissionChecker` involvement at all. The two must remain structurally incapable of being confused
    with each other, not just conventionally kept apart.
- **A new authorization policy, `RequirePlatformOwner`**, added to the existing Operator JWT scheme
  (`JwtSchemes.Operator`) — additive, same scheme, not a new one, matching `10-01`'s own precedent for
  why a narrower policy belongs next to `RequireOperatorIdentity` rather than behind a separate identity
  mechanism: the owner logs in through the exact same Keycloak realm and the exact same console login
  page every operator uses (`5-05`), only with a different realm role attached to their Keycloak user.
  The policy accepts a signature-valid Keycloak token whose `realm_access.roles` contains the owner role
  name, and nothing else — it must not require, and must not trigger, `OperatorIdentityClaimsTransformation`.
- **Realm-import config**: define the `platform-owner` realm role. For local development, assign it to
  one fixed, clearly-named test identity — matching `1-05`/`adr/0022`'s "fixed ids, not random ones"
  precedent for deterministic local seeding. The real assignment (granting this role to the author's own
  Keycloak account on the demo/production realm) is a manual action taken in Keycloak's own admin
  console, never committed to this repository — the same reasoning `repositories.md` already applies to
  every other credential, extended to a role grant that confers cross-tenant read access.
- State explicitly in the ADR that nothing prevents more than one Keycloak user from holding this role
  in principle (e.g. a future co-owner) — the code makes no "exactly one owner" assumption, it only
  checks for the role's presence; whether more than one identity ever holds it is entirely a Keycloak
  admin-console decision outside this item's scope.

## Out of scope

- Any UI or API for granting/revoking the owner role — a Keycloak admin-console action, matching how
  `5-08`'s own `"Admin"` role already has "no grant surface... only via the seed script" and this item
  does not change that pattern, only extends it to a role that isn't even in this codebase's own
  `roles` table.
- The cross-tenant query and the console view themselves — `12-02` and `12-03`.
- Any owner *action* beyond authenticating and being recognized (suspending a site, editing another
  tenant's config, granting "bonus features" — the phrase `adr/0023`'s Context used when first naming
  this surface). Nothing in `roadmap.md`'s Stage 12 done-when asks for write access; this item builds
  the boundary a future action-taking item would sit behind, not the actions themselves.

## Done when

- [x] `adr/00XX` written and accepted, naming the Keycloak-realm-role mechanism and explicitly stating
      why it is structurally distinct from `5-08`'s per-site `"Admin"` role and from `adr/0016`'s
      per-site `Role`/`Permission` model. — `adr/0032`.
- [x] Keycloak realm-import config: the `platform-owner` realm role exists, assigned to one fixed local
      test identity for automated tests and manual local verification. — **Partly different from as
      written, deliberately.** The role is *defined* in both realm-import files this project maintains
      (`ago-chat/tests/Ago.Chat.Integration.Tests/keycloak-realm-import.json` and
      `ago-deploy/k8s/base/keycloak-realm-import.json`) and *assigned* only in the first, to the fixed
      `platform-owner-test` identity that exists solely inside a Testcontainers container. It is
      assigned to nobody in `ago-deploy`'s file, because that one file is the *same* file the compose
      loop, the local k8s overlay **and the public demo realm** (`auth.reserve-me.ru`) all import — this
      item's own scope note assumed local dev and the demo had separate realm configs, and they do not.
      Every credential in that file is committed to a public repository, so a committed grant of a role
      conferring cross-tenant access would be exactly the leak this item exists to prevent. Manual local
      verification therefore needs one admin-console click first (Realm roles → `platform-owner` → Users
      in role), which is the same manual action the real grant already required.
- [x] `RequirePlatformOwner` policy exists on `JwtSchemes.Operator`, independent of
      `OperatorIdentityClaimsTransformation`. — `Ago.Chat.Api/Program.cs`, backed by
      `PlatformOwnerRequirement`/`PlatformOwnerAuthorizationHandler` (`Ago.Chat.Api/Auth/`). "Independent
      of" means *does not depend on*, not *does not run*: `OperatorIdentityClaimsTransformation` is a
      global `IClaimsTransformation` and still runs for any token on this scheme, resolving nothing for
      an owner identity. The owner test user deliberately has no `operators` row, so the passing test is
      itself the proof of independence.
- [x] `Ago.Chat.Integration.Tests`: three real tokens against `RequirePlatformOwner` — (1) a token
      carrying the `platform-owner` realm role passes; (2) an ordinary operator token, including one
      holding `5-08`'s `"Admin"` role, is rejected; (3) a Keycloak token with no matching `operators` row
      (`10-01`'s `RequireKeycloakIdentity`-eligible state) is also rejected. All three prove the policy
      is checking the realm role specifically, not merely "any valid Keycloak token" or "any token with
      elevated site permissions." — `PlatformOwnerPolicyTests` (six real-token cases, including the
      mirror direction: the owner token is *rejected* by `RequireOperatorIdentity`, and the `demo-admin`
      token is proven to hold `site:configure` against `PermissionChecker` before being rejected), plus
      `PlatformOwnerAuthorizationHandlerTests` for the fail-closed shapes a real Keycloak never mints
      (absent/non-JSON/non-array/case-different claim).
- [x] `docs/architecture/authorization.md`'s actor table gains a fourth row (**Platform owner**),
      matching how every other authentication mechanism in this table was recorded as fact once shipped.

## Open questions

None — the mechanism follows directly from the existing Keycloak infrastructure (`adr/0022`) and from
`adr/0016`'s own explicit site-scoping limit, which rules out expressing "every site" inside the
existing RBAC model without weakening the invariant that model was built to hold.
