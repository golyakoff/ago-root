# Self-service signup: identity flow and Keycloak provisioning

- **Stage**: 10
- **Status**: blocked
- **Depends on**: nothing new architecturally — reuses `5-05-operator-oidc-authentication.md`'s
  Keycloak realm-import mechanism and `adr/0022`'s shared-realm, resolve-at-request-time claims model
  unchanged. The new pieces are a realm setting and one new authorization policy, not a new identity
  architecture.

## Goal

A visitor can reach Keycloak's own registration form (linked from `ago-console`, `10-03`), complete
it, and land back holding a real Keycloak-signed JWT whose `sub` matches no `operators` row yet — a
genuine, terminable authentication state, instead of the dead end `adr/0022`'s `RequireOperatorIdentity`
policy currently produces for every such token (a clean 403, by design, for anyone who was never meant
to reach that far). This item makes the *identity* half of self-service signup possible for the first
time; it does not create the `Site`/`Operator` rows themselves (`10-02`'s job) and it does not build any
console UI (`10-03`'s job).

## Context to read first

`docs/architecture/authorization.md` in full — the three-actor table and the "Operator" row's exact
resolution mechanism (`OperatorIdentityClaimsTransformation`, resolved from `sub` at request time, no
claim added when nothing matches). `docs/adr/0022-oidc-keycloak-operator-authentication.md` — read
its Alternatives section closely; the reasoning that rejected self-issued password auth applies
directly to the choice this item has to make below. `docs/adr/0016-rbac-authorization-model.md` —
unaffected by this item, confirming role/permission resolution stays exactly as-is once an operator
exists. `docs/architecture/data-model.md`'s `operators` row (`external_subject_id`, nullable, unique
when present — the column this item's new operators eventually populate, in `10-02`).
`docs/backlog/5-05-operator-oidc-authentication.md`'s "New gap surfaced" note — Keycloak 26's
declarative user-profile silently attaches an implicit `VERIFY_PROFILE` required action unless
`email`/`firstName`/`lastName` are set, found live on the *seeded* demo operator; self-registration
collects these fields directly from a real visitor this time, and the realm's registration form
config needs the same fields required, not left to Keycloak's default, or the exact same failure mode
recurs on a real signup instead of a seed script.
`docs/architecture/repositories.md`'s "Everything is public" / "no secrets, ever" section — relevant to
why this item's recommended design avoids giving `Ago.Chat.Api` a new Keycloak admin credential to
protect.

## Scope

- **An ADR** deciding between two real, structurally different alternatives:
  - **(A) Keycloak's own native self-registration** (`registrationAllowed: true` on the realm).
    Keycloak collects and hashes the password, offers its own reset/verification flows, and
    `Ago.Chat.Api` never sees a password or calls Keycloak's admin API. The console only needs to link
    to Keycloak's hosted registration page and handle the redirect back — the same shape it already
    uses for login (`5-06`).
  - **(B) `Ago.Chat.Api` calls Keycloak's Admin REST API** server-side, driven by a single
    console-native signup form (site name, email, password collected in `ago-console` itself, no
    redirect to Keycloak at all).
  - **Recommendation: (A).** It is the direct extension of `adr/0022`'s own already-accepted
    reasoning for rejecting self-issued password auth ("a real feature... that competes for review
    attention... for a problem every OIDC provider has already solved correctly") — (B) would
    reintroduce exactly that problem at signup time even though `5-05` already avoided it at login
    time. (A) also avoids a new class of secret this project has not had to hold before: Keycloak
    admin credentials living in `Ago.Chat.Api`'s own configuration, one more thing `repositories.md`'s
    "no secrets, ever" rule has to be enforced against on every future change to that host. State the
    final decision in the ADR; if research during implementation finds a real reason to prefer (B),
    the ADR is where that argument belongs, matching `5-05`'s own precedent for how these ADRs are
    written.
- **A new, narrower authorization policy** on the Operator JWT scheme — e.g. `RequireKeycloakIdentity`
  — accepting any token that is signature-valid against Keycloak's JWKS, *without* requiring
  `OperatorIdentityClaimsTransformation` to have found a matching `operators` row. This is strictly
  weaker than the existing `RequireOperatorIdentity` policy and must never replace it on an existing
  route — it exists solely to gate the one new bootstrap endpoint `10-02` adds. State explicitly, in
  the ADR or the policy's own code comment, why the two must stay distinct (a route protected by the
  weaker policy accepts a token that proves *nothing* about site membership or permissions — it proves
  only "a real person completed Keycloak's login/registration flow").
- **Realm-import config**: `registrationAllowed: true`, plus whichever user-profile fields Keycloak's
  declarative profile requires at registration time to avoid the exact `VERIFY_PROFILE` gotcha `5-05`
  found live (state the fields explicitly once implemented, matching that file's own level of detail).
- **Abuse prevention, stated explicitly, not left implicit**: Keycloak's hosted registration form sits
  outside `Ago.Chat.Api`'s own request path, so this project's `IRateLimiter` (`3-05`) and the edge's
  coarse per-IP limits (`edge.md`) do not cover it directly. Two things follow, both stated here so a
  later session does not have to rediscover them: (1) spam-account creation *through Keycloak itself*
  is bounded only by whatever Keycloak's own registration flow offers (it supports a reCAPTCHA
  authenticator natively) — configuring that is explicitly **out of scope** below, a real, named
  deferral, not a silently dropped concern; (2) the actual abuse surface this project's own code must
  guard is `10-02`'s bootstrap endpoint, which *is* reachable from `Ago.Chat.Api` — that endpoint reuses
  `IRateLimiter`, keyed per-`sub` and per-IP, with a conservative default capacity (a configurable
  bucket parameter, the same `3-05` precedent for "hardcode sane defaults... per-site overrides are a
  later, explicitly-scoped feature," not a performance claim `nfr.md` would need a number for).

## Out of scope

- Actually creating `Site`/`Operator`/`Role` rows once a Keycloak identity exists — `10-02`.
- The console's signup entry point, redirect, and callback handling — `10-03`.
- Configuring Keycloak's reCAPTCHA (or any other bot-detection) authenticator on the registration flow
  — a real, named deferral (see Scope above), not forgotten. Purely realm configuration; adding it
  later touches nothing in `Ago.Chat.Api` or `ago-console`.
- Deciding email verification's actual requirement — that is this item's own blocking Open question
  below, not something scoped around it. The realm-import change this item makes is written so that
  toggling Keycloak's "Verify Email" required action is a one-line config change either way, not a
  redesign, once the author decides.

## Done when

- [ ] `adr/00XX` written and accepted, naming the chosen provisioning path (A or B) and the reasoning,
      and stating explicitly why `RequireKeycloakIdentity` and `RequireOperatorIdentity` must remain
      two distinct policies rather than one relaxed into the other.
- [ ] Keycloak realm-import config: `registrationAllowed` enabled, required profile fields set to avoid
      `5-05`'s `VERIFY_PROFILE` gotcha, and the email-verification setting matching the Open question's
      resolution below.
- [ ] `Ago.Chat.Integration.Tests`: a token minted for a freshly self-registered Keycloak user (a `sub`
      absent from `operators`) is accepted by `RequireKeycloakIdentity` and rejected by the existing
      `RequireOperatorIdentity` — proving the two policies are genuinely distinct enforcement points,
      not the same check under a different name.
- [ ] `docs/runbooks/local-dev.md` gains a short section: how to complete Keycloak's self-registration
      form against the local realm (or mint an equivalent token directly, matching `5-05`'s own
      "Getting a working operator session locally" curl-based precedent) for testing `10-02`/`10-03`
      without a real browser flow every time.
- [ ] `docs/architecture/authorization.md`'s actor table gets a note once this item ships, matching how
      every other authentication change to this table has been recorded as fact once shipped.

## Open questions

- **Email verification before the account is usable.** Two real options: Keycloak's "Verify Email"
  required action gates the caller from reaching `10-02`'s bootstrap endpoint until confirmed, or
  verification is not enforced at signup and a visitor gets full access immediately. `roadmap.md`'s
  "everyone starts on the free tier" framing suggests low friction matters, but nothing in this
  repository states the author's actual trust-versus-friction preference for a real signup flow, and
  this is a genuine product decision — it changes what a real visitor experiences, not just an
  implementation detail hidden behind a toggle. **Blocking**: this item does not start implementation
  until the author answers it, since the realm-import config and this item's own Done-when both depend
  on which answer wins.
