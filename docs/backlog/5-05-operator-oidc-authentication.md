# Operator authentication: OIDC, replacing the dev stub

- **Stage**: 5
- **Status**: ready
- **Depends on**: nothing from this stage's other items (backend-only), but blocks `5-06`'s console
  login and is therefore on the critical path for anything console-side

## Goal

`authorization.md`'s one remaining open question in the operator-authentication row gets closed: an
ADR confirms (or replaces) the OIDC working direction, and `POST /dev/operator-session` (the
Development-only stub since `1-06`) is replaced outright by real OIDC token validation - "replaces it
outright, not by evolving it," `authorization.md`'s own words, because the stub's trust model (trade an
operator id for a token, no password) has nothing in common with validating a token a real IdP signed.

## Context to read first

`authorization.md` in full, especially "Working direction: operator authentication" and its own
"Consequence this pins down early" paragraph (OIDC client config as a secret, never in the repo).
`adr/0016` (RBAC - unaffected by *how* an operator authenticates, only by *what claims* the resulting
token carries once validated). `realtime.md`'s "`/hubs/operator` authenticated by the operator's JWT" -
unchanged by this item; only who signs the JWT changes, `JwtSchemes.Operator`'s validation parameters
just point at a different issuer/key source. `3-06`'s signing-key-sharing finding
(`Auth:SigningKey`) - the per-process-random-key story this item replaces for the Operator scheme (the
Visitor scheme is untouched; visitors were never authenticated by this stub).

## Scope

- An ADR: confirms OIDC (or states why not, if research during this item surfaces a real reason to
  reconsider - unlikely, but the ADR is where that argument belongs if it exists) and picks a concrete
  identity provider for local development and the demo deployment. Author's decision, stated as an
  open question below with a recommendation.
- `Ago.Chat.Api`'s Operator JWT scheme (`AddJwtBearer(JwtSchemes.Operator, ...)`) validates against the
  chosen IdP's issuer/JWKS instead of the local `SigningCredentials` - `MapInboundClaims = false` and
  the rest of the existing validation-parameters shape stay, only the key source and issuer change.
  Claims mapping: the IdP's claims (subject, email, whatever the provider issues) map to an
  `OperatorId` + `SiteId` - state explicitly how a real IdP's identity becomes this project's own
  operator/site concepts (likely: the IdP is the identity source, an `operators` row lookup by a stable
  external-id claim resolves `OperatorId`/`SiteId`/roles, matching how `adr/0016`'s roles are already
  looked up per operator).
- `/dev/operator-session` removed - not deprecated, not left behind a flag; `Development`-only stubs in
  this project are replaced, never accumulated (`authorization.md`'s own precedent).
- Local-dev wiring: the chosen IdP running in the local k8s overlay (`ago-deploy`) or docker-compose
  loop, with a seeded test operator so `local-dev.md`'s manual verification flow keeps working without
  a real external IdP account.
- `docker/.env`/`infra-credentials`-style secret handling for the IdP's client id/secret - never
  committed (`repositories.md`).

## Out of scope

- The console's own login UI/redirect flow - `5-06`, the client half of this same OIDC exchange.
- Custom per-tenant role management - `adr/0016` already deferred this to a Stage 5 console surface
  (`5-08`), unrelated to *how* an operator authenticates.
- Visitor authentication - untouched; visitors were never behind this stub.

## Done when

- [ ] `adr/00XX` written and accepted, naming the concrete IdP and why.
- [ ] A real OIDC login (against the chosen IdP, local overlay) produces a token
      `Ago.Chat.Api`'s Operator scheme accepts, and `/dev/operator-session` no longer exists.
- [ ] `Ago.Chat.Integration.Tests`: a token from the real IdP resolves to the correct `OperatorId`/
      `SiteId`/role claims end to end through a real hub connection - not just JWT-validation-in-
      isolation, the same bar `1-06`'s original stub was proven against.
- [ ] A token from the *wrong* issuer, or an expired one, is rejected - proven, not assumed from
      `TokenValidationParameters`' defaults.
- [ ] `authorization.md`'s "Done when nothing here is open anymore" checklist gets its OIDC line
      checked, and the "Working direction" section is rewritten as shipped fact.
- [ ] `local-dev.md`/`k8s-local.md` updated with however a developer now gets a working operator
      session locally (seeded test operator + the IdP's own local login, or whatever the ADR settles
      on).

## Open questions

None - the author confirmed **Keycloak** for local development and the demo deployment (this file's
own recommendation: a real, widely-deployed OIDC provider rather than a test double, runs fine
alongside the existing local k8s overlay, and its admin API makes seeding a demo operator account
scriptable). The ADR this item writes still records the reasoning in full, not just the outcome.
