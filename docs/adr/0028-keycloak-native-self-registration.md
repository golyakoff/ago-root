# ADR-0028: Keycloak-native self-registration; `RequireKeycloakIdentity` stays distinct from `RequireOperatorIdentity`

- **Status**: Accepted
- **Date**: 2026-08-24
- **Stage**: 10

## Context

`10-01-self-registration-identity-flow.md`: a visitor must be able to reach a real signup flow and
land back holding a genuine, Keycloak-signed JWT whose `sub` matches no `operators` row yet - a
terminable authentication state `RequireOperatorIdentity` currently turns into a clean 403 for every
such token, by design (`adr/0022`). Two things need deciding: how the account itself gets created in
Keycloak, and how `Ago.Chat.Api` authorizes the one new endpoint (`10-02`'s bootstrap call) that a
caller in this state is allowed to reach.

## Decision

**(A) Keycloak's own native self-registration** (`registrationAllowed: true` on the realm), not
**(B)** `Ago.Chat.Api` calling Keycloak's Admin REST API from a console-native signup form.

This is the direct extension of `adr/0022`'s own already-accepted reasoning for rejecting self-issued
password auth at login time: "a real feature... that competes for review attention... for a problem
every OIDC provider has already solved correctly." (B) would reintroduce exactly that problem at
signup time - password collection, hashing, reset flows, email-verification dispatch - even though
`5-05` already avoided it at login time by validating Keycloak's token directly instead of minting
`Ago.Chat.Api`'s own. Building it twice, once at login and once at signup, for the same underlying
"an OIDC provider already does this correctly" argument would be the same mistake `adr/0022` already
named, just deferred to a second call site.

(A) also avoids a new class of secret this project has not had to hold before: Keycloak admin
credentials living in `Ago.Chat.Api`'s own configuration. `repositories.md`'s "no secrets, ever" rule
already has to be enforced against `docker/.env`'s Postgres/RabbitMQ/Redis/MinIO passwords and
Keycloak's own realm-import admin user; (B) would add a second Keycloak credential - one with
*write* access to the realm's user store, materially more sensitive than the read-only JWKS
discovery `Ago.Chat.Api` already depends on - to that same list, purely to save a browser redirect
`5-06`'s console already implements for login. Nothing about `10-01`'s own goal needs that trade.

**Extending `adr/0022`'s reasoning, not just restating it**: `adr/0022` weighed token exchange vs.
direct validation for an *already-authenticated* operator. This decision adds the observation that
the same "let the IdP own the parts of identity it already solved" argument applies one step earlier,
at *account creation* - Keycloak's hosted registration form already offers password strength rules,
duplicate-email detection, a reset flow, and (natively, though out of scope here per `10-01`'s own
Scope) reCAPTCHA - none of which `Ago.Chat.Api` would get for free by rolling its own signup form
against the Admin API. The console's role stays exactly what it already is for login (`5-06`): a
redirect out, and a callback handler for the token that comes back.

**`RequireKeycloakIdentity`**, a new authorization policy on the Operator JWT scheme, gates the one
endpoint this identity state is actually for (`10-02`'s `POST /api/v1/sites`). It accepts any token
that is signature/audience/lifetime-valid against Keycloak's JWKS - the same validation
`RequireOperatorIdentity` already requires - but, unlike `RequireOperatorIdentity`, does **not**
require `OperatorIdentityClaimsTransformation` to have resolved a matching `operators` row
(`RequireClaim(AgoClaimTypes.OperatorId)`). Mechanically: drop that one `RequireClaim` call.
Strictly weaker, and deliberately so.

**Why the two policies must stay distinct, not one relaxed into the other**: a token accepted by
`RequireKeycloakIdentity` proves exactly one thing - "a real person completed Keycloak's
login/registration flow, including its own email-verification gate" (the "Verify Email" required
action, `10-01`'s own Scope, enabled explicitly in the realm-import config below). It proves
*nothing* about site membership or RBAC permissions (`adr/0016`) - there is no `OperatorId`, no
`SiteId`, nothing `PermissionChecker` could resolve a role against. Relaxing `RequireOperatorIdentity`
itself (rather than adding a second, narrower policy) would silently widen every existing
operator-only route - the queue, conversation history, webhook management, attachment deletion - to
accept a caller who has never been granted a single permission on any site. `RequireKeycloakIdentity`
exists so that widening can never happen by construction: it is wired to exactly one route
(`10-02`'s bootstrap endpoint) and nothing reachable from it assumes `OperatorId`/`SiteId` claims
exist, the same way `ClaimsPrincipalExtensions.GetOperatorId()`'s own remarks already document for
`RequireOperatorIdentity`.

## Consequences

- One new authorization policy (`Program.cs`), no new authentication scheme - both policies run on
  the existing `JwtSchemes.Operator` scheme, which already validates directly against Keycloak's JWKS
  (`adr/0022`). The only difference between the two policies is which claims they additionally
  require after that validation succeeds.
- Realm-import config changes (`registrationAllowed: true`, the required-profile fields `5-05`'s own
  `VERIFY_PROFILE` gotcha already forces onto every seeded user, and the "Verify Email" required
  action) apply to every realm-import file this project maintains - the automated test suite's own
  Testcontainers-provisioned realm (`ago-chat`/`tests/Ago.Chat.Integration.Tests/keycloak-realm-import.json`,
  this repository) and the real local/demo deployment's realm
  (`ago-deploy/k8s/base/keycloak-realm-import.json`). This dispatch's own worktree scope covers only
  the former; the latter is a real, separate gap flagged in this stage's own handback, not silently
  skipped.
- No new secret, no new admin credential, no server-side password handling anywhere in
  `Ago.Chat.Api` - `10-02`'s bootstrap endpoint only ever reads a `sub` claim off an already-validated
  token, never a password.
- Abuse prevention for the registration form itself (spam accounts created directly through
  Keycloak, outside `Ago.Chat.Api`'s own request path) is explicitly deferred to Keycloak's own
  reCAPTCHA authenticator, not built here - a real, named deferral (`10-01`'s own Scope), not a
  silently dropped concern. The abuse surface this project's own code *does* guard -
  `10-02`'s bootstrap endpoint, reachable from `Ago.Chat.Api` - reuses `IRateLimiter` (`3-05`), keyed
  per-`sub` and per-IP.
- A caller who completes Keycloak's registration form but never calls `10-02`'s bootstrap endpoint is
  a real, authenticated Keycloak identity that resolves to nothing in this project - the same
  "terminable authentication state" `10-01`'s own Goal describes, now reachable for real. Nothing
  currently cleans this up (no orphaned-Keycloak-user sweep); flagged here as a fact about the shape
  of the system, not a defect this item's own scope was ever asked to close.

## Alternatives considered

- **(B) `Ago.Chat.Api` calls Keycloak's Admin REST API**, driven by a console-native signup form - see
  Decision above for why this was rejected. Revisit only if a real requirement surfaces that Keycloak's
  hosted registration form genuinely cannot express (e.g. collecting a business-specific field at
  signup time that has to land in this project's own database atomically with account creation) -
  nothing in `10-01`/`10-02`'s own scope needs that today.
- **Relaxing `RequireOperatorIdentity` itself** instead of adding `RequireKeycloakIdentity` - rejected;
  see "Why the two policies must stay distinct" above. The failure mode this avoids (every existing
  operator-only route silently accepting a non-operator token) is exactly the kind of change a
  reviewer would flag immediately if it showed up as a diff to the existing policy instead of a new,
  narrowly-scoped one.
- **A new, third authentication scheme** (rather than a second policy on the existing `Operator`
  scheme) - rejected as unnecessary indirection. Both policies validate the identical token against
  the identical JWKS; the only difference is which claims are required afterward, which is exactly
  what ASP.NET Core's policy layer (as opposed to its scheme layer) exists to express.
