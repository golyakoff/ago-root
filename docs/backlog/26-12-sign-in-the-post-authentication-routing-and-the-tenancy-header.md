# 26-12 · Sign-in, the post-authentication routing, and the tenancy header

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-21, the first third of `plan.md`'s Phase 0 — "the shell that proves the hard
  parts". Its own words: the three things most likely to be wrong are not screens, and OIDC against
  Keycloak from a native client is the first of them.
- **Verified**: 2026-09-21 — the audience/realm facts checked directly (see `26-11`'s Verified line).
  The three-way routing, its fourth arm, and the `X-Ago-Active-Site` mechanism are read from
  `ago-android/docs/navigation.md` §"Sign-in, and the three-way routing that must not be simplified"
  and §Tenancy of `architecture.md`; `ago-console/src/api/activeSite.ts` is the console's own
  single-source-of-truth for that header and is the shape being ported.
- **Depends on**: `26-07`, `26-10`, `26-11`.

## What this item is

An operator signs in and ends up in the right place, holding a session that can make authenticated,
tenant-scoped calls. One promise, and it is deliberately not split further: a token with nothing that
proves it works, or a header plugin with no token to attach, are halves that cannot land green
(rule 15).

## Scope

- **AppAuth for Android, Authorization Code + PKCE, in a Custom Tab** against the `ago-android` client
  `26-11` created. Never an embedded WebView — that is the practice OAuth's own current best-practice
  document exists to stop, and it is why the dependency is here at all.
- **Tokens in `EncryptedSharedPreferences`.** The refresh token never leaves the device and never
  appears in a log at any level.
- **A Ktor client (OkHttp engine) in `:core:network`** attaching the bearer token, **reading the
  current token on every call rather than closing over one**. The access token is five minutes against
  a long SSO session, and `ago-console/src/realtime/calendarOperatorConnection.ts` carries the comment
  that names the bug (`5-16`) both existing clients reached independently. This client is written
  knowing it.
- **The three-way routing, with its fourth arm** (`navigation.md`'s diagram, `adr/0063`, `12-04`,
  `11-17`):
  - `GET /api/v1/operators/me` → `200`: an operator. Go on.
  - `403`: **not an answer yet.** Probe `GET /api/v1/owner/sites?limit=1` — accepted routes to the
    platform-owner terminal screen, refused routes to registration. Dropping this probe reproduces
    `12-04` exactly: it would offer a platform owner the site-registration form, whose button commits
    a `Site`, its roles and an `Operator` row with **no un-register path in the product**.
  - **Anything else — a `401`, a `5xx`, a network failure — is neither answer** and renders a retry.
    Folding it into either arm is `11-17`'s own correction.
- **The launch / sign-in screen**, which **names no deployment**. `navigation.md`: the hostname an
  earlier draft printed under the buttons is deliberately gone; the build variant's name belongs in
  Settings → О приложении (`26-17`), where a tester looks and an operator does not.
- **The platform-owner terminal screen** — an honest dead end with a link out to the web console,
  because the five owner routes are excluded (`scope-inventory.md` §2).
- **`GET /api/v1/me/tenancies`**, and a site picker before the app opens when there is more than one.
  One identity can hold operator seats at several sites (`adr/0068`).
- **`X-Ago-Active-Site` as a Ktor client plugin**, reading one source of truth the picker writes —
  attached to every authenticated REST call, **never threaded through call signatures and never
  duplicated per API module** (`architecture.md`). The header can only ever *narrow* what a request
  resolves to server-side, so a stale read costs one `403` and a retry and never a cross-tenant leak.
- **Sign-out**: discard the session and return to the launch screen. (`26-06` adds the device
  revocation that must happen *before* the token is discarded; the ordering is that item's to hold.)

## Out of scope

- The hub connection and its own query-string active-site equivalent — `26-13`.
- **The active-site *switcher*** in Settings — `26-17`. This item picks a site at sign-in; changing it
  later is a different screen and a different promise.
- The registration and invite screens themselves (`/onboarding`, `/redeem-invite`, `/invite/:code`).
  The routing arm that points at them lands here; the forms are a later wave.
- Any conversation screen, and the bottom navigation (`26-16`).

## Done when

- [ ] A real operator signs in on a **real phone** against the live API and reaches a placeholder
      "signed in" surface.
- [ ] An identity with no operator seat that **is** a platform owner reaches the terminal screen, and
      one that is neither reaches the registration arm — both proven against real identities, not
      mocked.
- [ ] A `5xx` or a dropped network during the `operators/me` probe renders a retry and **never** the
      registration form — proven with a fault-injected client, because this is the one arm that is
      wrong in a way that looks correct.
- [ ] An expired access token is refreshed and the retried call succeeds with no sign-in prompt.
- [ ] Every authenticated request carries `X-Ago-Active-Site` — asserted by a `MockEngine` test over
      the client itself, not by reading call sites.
- [ ] No token of any kind appears in logcat at any level, including verbose.
- [ ] `./gradlew ktlintCheck lint test` green; counts reported.
