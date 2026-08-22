# ADR-0022: OIDC via Keycloak replaces the operator dev-auth stub

- **Status**: Accepted
- **Date**: 2026-08-23
- **Stage**: 5

## Context

`authorization.md`'s "Working direction: operator authentication" named OIDC as the intended
mechanism from Stage 1 onward, with `POST /dev/operator-session` (`1-06`) standing in until Stage 5 -
a `Development`-only endpoint that trades a bare operator id for a signed JWT, no password, no proof
of identity at all. That stub was always meant to be replaced outright, not evolved: its trust model
(anyone who knows an id can become that operator) has nothing in common with validating a token a real
identity provider signed.

Two things need deciding: which IdP, and how a token that IdP issues becomes this project's own
`OperatorId`/`SiteId` concepts, since an external IdP has no notion of either.

## Decision

**Keycloak** is the IdP, for local development and the demo deployment alike - a real, widely-deployed
OIDC provider rather than a test double, runs as one more container next to Postgres/RabbitMQ/Redis/
MinIO in the existing compose loop and k8s overlay, and its own admin API/realm-import makes seeding a
deterministic demo operator scriptable the same way `1-05`'s Postgres seed already is.

**Token flow**: the console (`5-06`) redirects to Keycloak (Authorization Code + PKCE, the standard
SPA flow), Keycloak issues an access token, the console presents that token to `Ago.Chat.Api` exactly
where an operator token was presented before (`Authorization` header for HTTP,
`?access_token=` on the hub connection - `realtime.md`'s existing mechanism, unchanged). There is
**no token exchange**: `Ago.Chat.Api` does not mint its own replacement token after validating
Keycloak's. `JwtSchemes.Operator`'s `AddJwtBearer` now points `Authority` at Keycloak's realm instead
of a local `SigningCredentials` key - JWKS discovery and signature validation come from Keycloak
directly, the same `MapInboundClaims = false` and lifetime/issuer validation shape stays.

**Claims mapping**: Keycloak's token proves *who this person is to Keycloak* (`sub`, a Keycloak-issued
subject id) - it says nothing about `OperatorId` or `SiteId`, concepts Keycloak has never heard of. A
new `IClaimsTransformation`, registered once and running after JWT validation, does the same kind of
lookup `adr/0016`'s `PermissionChecker` already performs at request time: given the validated
principal's `sub`, find the `operators` row whose new `external_subject_id` column matches it, and add
`OperatorId`/`SiteId` claims onto the principal from that row. A principal already carrying `site_id`
(the Visitor scheme's own self-issued tokens) is left untouched - the transformation only acts on a
token that lacks it, which is exactly the set of tokens that came from Keycloak rather than
`Ago.Chat.Api` itself. No match means no `OperatorId` claim is added; a `RequireClaim` policy on the
Operator scheme rejects the request cleanly (403 / hub abort) rather than a downstream
`ClaimsPrincipalExtensions.GetOperatorId()` throwing on a missing claim.

Role/permission resolution is **unchanged**: `PermissionChecker` still resolves `operator_roles`/
`roles` per `(OperatorId, SiteId)` at check time, exactly as `adr/0016` shipped it. Nothing about *how*
an operator authenticates changes *what* the resulting principal is allowed to do.

**Visitor scheme untouched**: visitors were never behind the stub this ADR removes, and nothing here
changes how a visitor token is issued or validated.

## Consequences

- `POST /dev/operator-session` and `JwtTokenService.IssueOperatorToken` are deleted outright, not
  deprecated - matching `authorization.md`'s own "replaces it outright, not by evolving it."
- `operators` gains one column (`external_subject_id`, nullable text, unique when present) - additive,
  reversible, no data to backfill (Stage 1 never had real operator identities to preserve).
- A new local dependency: Keycloak, one more container in the compose loop and the k8s overlay,
  provisioned by realm import rather than a runtime admin-API script, so the demo operator's Keycloak
  user id is deterministic (a fixed UUID, the same "fixed ids, not random ones" precedent `1-05`'s
  Postgres seed already established) and `create-demo-tenant.sh` only needs to write that same fixed
  value into `operators.external_subject_id`, never call Keycloak's admin API at seed time.
- `Ago.Chat.Api` now depends on Keycloak being reachable at startup (JWKS discovery) for the Operator
  scheme to validate anything - a new operational dependency the health checks must account for.
- Cost accepted knowingly: an `IClaimsTransformation` doing a database read on every authenticated
  operator request is one more round trip per request than reading `sub` directly did. Not cached -
  `PermissionChecker`'s own per-check lookup already pays this cost on the same request path, so this
  is not a new order of magnitude, and premature caching here would be optimizing before `nfr.md` has
  a real number to justify it (`CLAUDE.md`: "measure or stay silent").

## Alternatives considered

- **Token exchange** (validate Keycloak's token once, mint `Ago.Chat.Api`'s own internal JWT exactly
  like the stub did, use that everywhere downstream) - rejected. It would keep every other piece of
  the app (hub auth, `ClaimsPrincipalExtensions`, the multi-scheme routes `5-03` added) completely
  unaware anything changed, which is real simplicity - but it re-introduces a second self-issued
  token type Stage 5 was specifically trying to retire, and duplicates session/expiry logic Keycloak
  already provides correctly. Direct validation is more standard OIDC practice and is what a reviewer
  familiar with the pattern would expect to see.
- **Claims embedded in the Keycloak token itself** (a protocol mapper or user attribute pushing
  `OperatorId`/`SiteId` into the token Keycloak issues, so `Ago.Chat.Api` never queries its own
  database for them) - rejected. It couples Keycloak's own configuration to this project's schema
  (an `OperatorId` is meaningless to Keycloak, invented purely for our own tables), and moves "how do I
  find this operator's site" out of application code and into IdP configuration a reviewer cannot see
  by reading the repository. The database lookup keeps that mapping where every other piece of
  business logic already lives.
- **Self-issued password auth** (a password table in `ago-chat`'s own database) - already rejected in
  `authorization.md`'s original working-direction note; not revisited here, since nothing about
  researching this item surfaced a reason to reconsider.
- **Entra ID / Auth0** instead of Keycloak - both are real OIDC providers and would work architecturally
  identically to Keycloak from `Ago.Chat.Api`'s side (only `Authority` changes). Rejected for local
  development specifically: both are hosted SaaS with no realistic self-hosted-in-compose story,
  which would make the "runs fine alongside the existing local k8s overlay" property false. Keycloak's
  own container image exists precisely for this.
