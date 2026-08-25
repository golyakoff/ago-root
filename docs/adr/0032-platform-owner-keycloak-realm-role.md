# ADR-0032: The platform owner is a Keycloak realm role, deliberately outside the per-site RBAC model

- **Status**: Accepted
- **Date**: 2026-08-25
- **Stage**: 12

## Context

Stage 12 introduces a fourth kind of caller: the **platform owner** — the author acting as operator of
the service itself rather than of any one tenant. `12-02`/`12-03` will give that caller a cross-tenant
query and a console view; this decision is only about how the identity is represented and recognised,
because that is where the security-relevant choice actually is. A bug here leaks every tenant's data to
whoever ends up holding the identity, so the boundary has to be *provably* separate from the per-site
RBAC model, not a permission that happens to be granted broadly.

Two existing decisions constrain it, and they pull in the same direction:

- **`adr/0016`**: "a `Role` is a named set of permissions, scoped to one `site_id` — a role is
  tenant-local, so two sites' roles are independent assignments." The check itself happens in
  `Application`, where "a handler resolves the caller's permissions for the relevant site/resource."
  Every permission check in this codebase is anchored to exactly one `site_id`. A platform owner needs
  "every site," and there is no site to anchor an owner check to.
- **`adr/0022`**: an operator's identity comes from Keycloak, and `OperatorIdentityClaimsTransformation`
  turns a validated `sub` into `OperatorId`/`SiteId` by finding the matching `operators` row. The
  platform owner is not an `Operator` row, so that transformation has nothing to find and nothing to say.

`5-08` makes the trap concrete. It shipped a second built-in role, `"Admin"`, holding
`site:configure`/`site:manage_operators`/`attachment:delete`, and `demo-admin` is seeded with it. An
admin operator can already see *every conversation for their own site*. "Every conversation for every
site" looks, from a distance, like the same thing with the scope widened — and widening it inside the
existing model is exactly what must not happen.

## Decision

**A dedicated Keycloak realm role, `platform-owner`, checked directly from the validated JWT's
`realm_access.roles` claim.** No `operators` row is created or consulted; no `site_id` is ever involved;
`IPermissionChecker` is never called.

Concretely, in `ago-chat`:

- **`RequirePlatformOwner`**, a third authorization policy on the existing `JwtSchemes.Operator` scheme
  (`Ago.Chat.Api/Program.cs`) — additive, same scheme, same Keycloak JWKS validation as
  `RequireOperatorIdentity` and `RequireKeycloakIdentity`. `adr/0028` already settled why a second
  *policy* rather than a second *scheme* is the right shape: "both policies validate the identical token
  against the identical JWKS; the only difference is which claims are required afterward, which is
  exactly what ASP.NET Core's policy layer exists to express." That argument applies unchanged to a third.
- **`PlatformOwnerRequirement` / `PlatformOwnerAuthorizationHandler`** (`Ago.Chat.Api/Auth/`) — the
  handler parses the `realm_access` claim (Keycloak emits a JSON *object*, so a plain `RequireClaim`
  cannot express this: it can only compare whole claim values, which here would mean matching a
  serialized JSON blob exactly) and succeeds only if its `roles` array contains the exact string
  `platform-owner`.
- **The role name is a compile-time constant, not configuration.** A configurable name would introduce a
  "key missing or empty" state, and the only safe reading of that state is "deny everyone" — a
  fail-closed branch that has to be written correctly today and kept correct forever, with an empty
  configured value matching an empty role string as the obvious way to get it wrong once. A constant has
  no such state: nothing to omit, nothing to leave blank, nothing a deployment's own configuration can
  widen. Revocation does not need configurability either — it is removing the role assignment in
  Keycloak's admin console, which needs no code change and no redeploy.
- **The realm role is *defined* in every realm-import file this project maintains and *assigned* in
  none of them that a network can reach.** `ago-deploy/k8s/base/keycloak-realm-import.json` defines the
  role and grants it to nobody; `ago-chat/tests/Ago.Chat.Integration.Tests/keycloak-realm-import.json`
  defines it and grants it to one fixed local identity, `platform-owner-test`, which only ever exists
  inside a throwaway Testcontainers container. The real grant — this role on the author's own Keycloak
  account — is a manual admin-console action, never committed (`repositories.md`, "no secrets, ever").

**Why this is not `5-08`'s `"Admin"` role under another name.** An admin operator is an `Operator` row,
resolved through `OperatorIdentityClaimsTransformation`, scoped to exactly one `site_id`, and checked
through `PermissionChecker`'s per-site permission resolution. The platform owner has none of those: no
`Operator` row, no `site_id`, no `PermissionChecker` involvement at all. The two are not merely kept
apart by convention — they are *structurally incapable of being confused*, because
`PlatformOwnerAuthorizationHandler` reads exactly one input (a claim Keycloak signs) and that input is
not writable by anything in this system. No `INSERT` into `roles` or `operator_roles`, however broad,
can reach it. Conversely, the owner identity has no `operators` row, so `RequireOperatorIdentity`
rejects the very token `RequirePlatformOwner` accepts — the separation runs in both directions, and both
directions have a test.

**Fail-closed by construction.** The handler calls `context.Fail()` explicitly on every non-matching
path rather than merely declining to succeed. An explicit failure is sticky for the whole policy
evaluation, so a second handler registered for the same requirement later — by accident or by a
well-meaning refactor — cannot grant what this one denied. A missing `realm_access` claim, a claim that
is not JSON, a `roles` value that is not an array, and a role name differing by case all land there.
There is no configuration state, no default, and no "unset means allow": the only way to pass is to hold
a role a Keycloak administrator granted by hand.

**More than one holder is allowed in principle.** The code makes no "exactly one owner" assumption — it
checks for the role's presence, nothing more. Whether a second identity (a future co-owner) ever holds
it is entirely a Keycloak admin-console decision, outside this ADR's scope.

## Consequences

- One new authorization policy and one authorization handler; no new authentication scheme, no new
  secret, no new infrastructure. Keycloak is already a trusted dependency (`adr/0022`).
- **`adr/0016`'s "a role is tenant-local" invariant survives untouched.** The platform owner is not
  expressed in that model at all, so nothing in `PermissionChecker` or any per-site call site has to
  learn about a wildcard scope. That is the whole point: the invariant holds because the new concept was
  put outside the model rather than bent into it.
- **`adr/0016`'s "the check happens in `Application`" is not violated, but it also does not apply.** That
  rule is about resolving a caller's permissions against this system's own site-scoped data, which is a
  business decision and belongs in `Application`. Recognising the platform owner reads nothing from this
  system at all — it is a property of the validated token, decided before any use case runs, the same
  place `RequireOperatorIdentity` and `RequireKeycloakIdentity` already sit. When `12-02` adds a
  cross-tenant *query*, that query's own rules are `Application`'s business as usual.
- Cost accepted knowingly: authorization for this one caller is now readable in two places rather than
  one — Keycloak's realm configuration (who holds the role) and this repository (what the role admits).
  A reviewer cannot see the grant by reading the code. That is deliberate and is the same trade
  `adr/0022` already accepted for operator identity itself; the alternative (a grant visible in the
  repository) is strictly worse, since a committed grant on a public repository *is* the leak.
- `OperatorIdentityClaimsTransformation` still runs for an owner token — it is a global
  `IClaimsTransformation`, not something a policy opts into — and resolves nothing, because there is no
  matching `operators` row. That is harmless (one extra database read on owner requests, a surface that
  currently has no endpoints at all) and is asserted by test rather than assumed: the owner test
  identity deliberately has no `operators` row.
- The local/demo realm-import file grants the role to nobody, so a freshly imported realm has *no*
  platform owner until someone assigns it by hand. Manual verification of `12-03`'s console view will
  need that assignment first. Failing closed on a fresh import is the correct default and is not a defect.
  Two operational facts that go with it, both verified against a real Keycloak rather than assumed:
  the demo/local Keycloak runs `start-dev --import-realm` with no persistent volume, so the whole realm
  is re-imported on every pod restart and a hand-made grant **does not survive one**; and Keycloak's
  import strategy is `IGNORE_EXISTING`, so on any Keycloak whose realm *does* persist, adding a role to
  this file does not create it - it has to be created by hand there too.
- Found live while verifying the realm import, worth recording because it fails the *whole server*
  rather than the role: Keycloak's role `description` column is `varchar(255)`, and an over-long
  description aborts startup with a Liquibase `DataException` before any realm exists ("Value too long
  for column DESCRIPTION"). The explanation of why the role is defined-but-unassigned therefore lives
  in this ADR and in `authorization.md`, with only a short pointer in the JSON.
- **Not built here**: any owner *action* (suspending a site, editing another tenant's config), any UI or
  API for granting/revoking the role, and the cross-tenant query itself. This ADR builds the boundary a
  future action-taking item sits behind.

## Alternatives considered

- **A "applies to every site" sentinel on the existing `Role`/`Permission` model** (e.g. a `Role` with
  `site_id = null` meaning "all sites"). Rejected. It would require `PermissionChecker` and every future
  per-site call site to special-case a wildcard scope, breaking the exact invariant `adr/0016` was
  written to hold, for the sake of one caller. `clean-architecture.md` warns against speculative
  structure with one caller; this is that warning backwards — *retrofitting* speculative generality onto
  an already-shipped, deliberately narrow model. Worse, it would make the failure mode silent: a
  wildcard-scoped row is an ordinary-looking row, and any bug in the "is this scope null?" branch is a
  cross-tenant leak that looks like a normal RBAC grant in the database.
- **A separate `platform_owners` table in this project's own database.** Rejected. It answers the
  representation question but not the revocation or provisioning one: granting and revoking would need
  either a UI (explicitly out of scope) or a hand-written `UPDATE` against production, and the grant
  would live in the same database whose contents the role exists to protect. Keycloak already owns
  "which humans exist and what they are," and this is exactly that question.
- **A hardcoded operator id, an allow-list of subject ids, or any config value checked in application
  code**, bypassing Keycloak. Rejected, and it is the alternative most worth naming explicitly because it
  is the cheapest to build. It reintroduces the problem `adr/0022` already rejected once for operator
  login ("a real feature... for a problem every OIDC provider has already solved correctly") — and worse
  here, because what it grants is cross-tenant access to every site's data with no revocation story
  beyond redeploying a config change. It also creates precisely the misconfiguration state this decision
  otherwise does not have: an empty or missing allow-list has to mean "nobody," and the day it is read as
  "no restriction" is the day every authenticated caller is the owner. A Keycloak realm-role assignment
  is revocable from Keycloak's own admin console, with no code change and no redeploy.
- **A protocol mapper flattening `realm_access.roles` into a simple string claim**, so a plain
  `RequireClaim` could express the check without any JSON parsing. Rejected as a worse trade of the same
  kind `adr/0022` already made when it refused to push `OperatorId`/`SiteId` into the token: it moves
  part of the security decision into IdP configuration a reviewer cannot see by reading the repository,
  and it makes the check depend on a mapper existing in every realm this ever runs against. Twenty lines
  of parsing in a tested handler is the more legible half of that trade.
- **Relaxing or reusing `RequireOperatorIdentity` / `RequireKeycloakIdentity`.** Rejected on `adr/0028`'s
  own reasoning, which applies verbatim: a policy that widens is a change every existing route inherits.
  `RequirePlatformOwner` is strictly narrower than both and is wired to nothing yet, so it can widen
  nothing by construction.
