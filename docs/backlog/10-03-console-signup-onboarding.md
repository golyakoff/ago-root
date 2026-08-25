# Console signup and onboarding UI

- **Stage**: 10
- **Status**: **built and tested; one manual step outstanding, and it is outstanding for a reason a
  session cannot remove.** The screens shipped with `ago-console` `ead191e` (2026-08-24) and this
  pass added the behaviour tests they never had, three small defects' worth of fixes, and the two
  statements the Scope below asks for in writing (how state (b) is detected, and what is checked
  client-side versus server-side). What is *not* done is the first Done-when box: a real browser
  completing Keycloak's registration form end to end. An agent cannot type a password into a login
  form, so the walk stops one field short - see Outcome for exactly where, and for what was verified
  live instead.
- **Depends on**: `10-01-self-registration-identity-flow.md` (the Keycloak registration entry point
  and the "authenticated but not yet an operator" token state this UI must detect), `10-02-site-and-operator-registration.md`
  (the endpoint this form calls)

## Goal

A visitor with no `ago-console` session can reach a public "Sign up" entry point, complete Keycloak's
own registration form, land back in `ago-console` holding a token the console recognises as
"authenticated, but not yet an operator" — a state `5-06`/`5-07`'s existing login flow never had to
handle, since every token it saw before this item belonged to an already-provisioned operator — and
complete a short "set up your site" form (site name, embed origin) that calls `10-02`'s endpoint before
being routed into the normal queue view exactly as a returning operator would be.

## Context to read first

`docs/adr/0023-console-framework-react.md` — it names three console surfaces (the operator console,
tenant self-service configuration starting with `6-03`, and an internal operations view), and all three
assume an already-authenticated operator. **This item is explicitly a fourth surface `adr/0023` did not
anticipate: a public, pre-account, pre-authentication route inside `ago-console`.** State this plainly
in whatever this item writes, since a later session reading `adr/0023` alone would not expect a public
unauthenticated route to exist in this repository at all. `docs/backlog/5-06-console-framework-and-scaffold.md`
— the existing login/callback handling this item extends rather than replaces (routing shell: login →
queue → conversation view). `docs/backlog/5-07-console-conversation-experience.md` — the queue view this
flow must end at, unchanged. `docs/architecture/realtime.md` — confirms nothing about the console's
existing token-to-hub-connection wiring changes; this item only changes what happens *before* that
wiring runs for a first-time caller.

## Scope

- A public route (no auth guard) presenting a "Sign up" link/button that redirects to Keycloak's
  registration endpoint (`10-01`'s realm config) — not a console-built form. The console never collects
  a password; that stays entirely on Keycloak's hosted page, matching `10-01`'s own recommendation.
- Callback handling: after Keycloak redirects back with a token, the console's existing "resolve who I
  am" step must distinguish **three** states, not the two it handles today: (a) a token that resolves
  to a real operator — existing behaviour, route to the queue, unchanged; (b) a token that authenticates
  against Keycloak but resolves to no operator (`10-01`'s `RequireKeycloakIdentity`-eligible state) —
  new: route to the "finish setting up your site" form; (c) no token, or an invalid one — existing "go
  log in" behaviour, unchanged. State explicitly, once implemented, how (b) is actually detected
  client-side — the console must not re-derive server-side authorization logic itself (e.g. inspecting
  JWT claims directly to guess whether an operator exists); prefer a cheap, purpose-built check or
  reading the specific error/response shape `10-02`'s endpoint's own contract already provides.
  **Answered below** — "How state (b) is detected client-side", in Outcome.
- The onboarding form itself: site display name, one embed origin. State explicitly what this item
  validates client-side versus what `10-02` already validates server-side — client-side checks are
  UX-only (e.g. "looks like a URL, please try again"), never the actual source of truth for what gets
  accepted, matching how every other form in this codebase already treats client/server validation.
  **Answered below** — "What is validated client-side versus server-side", in Outcome.
- On success, route into the same queue view `5-07` built, exactly as a normal login would — no
  separate "new operator" branch anywhere downstream of this point; onboarding is a one-time detour
  into the same destination every login already reaches.

## Out of scope

- Anything about which fields Keycloak's own hosted registration page shows (email, password, confirm
  password) — that page belongs to Keycloak, not this console, per `10-01`.
- Editing the site's `allowed_origins` after signup, registering a second site, inviting additional
  operators — none of these exist anywhere yet (`10-02`'s own Out of scope), so there is nothing here
  to build a UI for.
- A design-system pass beyond what `5-06`'s scaffold already established. `5-06` deferred visual polish
  until there was a concrete screen to apply it to; this item is that screen, but a full design pass is
  still not this item's job — reuse whatever `5-07` already established for form/button styling. **Note
  added 2026-08-24**: that turned out to be seventeen lines of CSS, and `11-05-console-design-
  foundation.md` is the pass that fixes it — this screen gets retrofitted there, so it is still not this
  item's job.

## Done when

- [ ] Manually verified against the local cluster, the same "verified live, not asserted" bar
      `5-06`/`5-01` used: a real browser completes Keycloak's registration form, lands back in
      `ago-console` in the new onboarding state (not silently treated as a login failure), completes
      the site-setup form, and ends up in the queue view able to see its own (empty) waiting queue.
      **Half of this was walked for real (2026-08-25) and half cannot be, by an agent** — see
      "What was verified live, and where it stops" below. This box stays unticked deliberately
      rather than being reworded to match what was achievable.
- [ ] A returning, already-provisioned operator's normal login is unaffected — proven by running
      through `5-06`'s existing login flow once this item is merged, confirming state (a) still routes
      exactly as it did before this item existed. **Same blocker**: signing in as `demo-admin` means
      typing that account's password. Covered automatically instead (state (a) routes to the queue,
      and does so on the server's answer rather than on anything in the token), which is a weaker
      claim than the live one and is not offered as a substitute for it.
- [x] CI build+lint stays green, matching `5-06`'s own precedent for what this repository automates
      versus verifies by hand for `ago-console`. `npm test` is now in that workflow too (added
      2026-08-25), so the tests below gate PRs rather than merely existing.

## Outcome

### How state (b) is detected client-side — the statement the Scope asks for

`CallbackPage` calls `resolveOperatorState(accessToken)` (`ago-console/src/api/operatorsApi.ts`),
which issues `GET /api/v1/operators/me` — `5-08`'s existing endpoint, gated by
`RequireOperatorIdentity` — and maps the *status code*:

| answer | state | destination |
|---|---|---|
| `200` | (a) an operator | `/` — the queue, unchanged |
| `403` | (b) a real Keycloak identity, no `operators` row | `/onboarding` |
| the code exchange itself rejected | (c) no valid token | the existing "sign-in failed" screen |
| anything else (`401`, `5xx`, network) | *no state* | the same "sign-in failed" screen |

**This is a read of the server's decision, not a re-derivation of it.** The `403` is produced by
`RequireOperatorIdentity`'s `RequireClaim(OperatorId)`, and that claim exists only when
`OperatorIdentityClaimsTransformation` resolved the token's `sub` against `operators` — server-side,
per request, `adr/0022`'s model. The console decodes no JWT and inspects no claim: the token it holds
carries nothing about operators, by design, and a test asserts the routing still works with a token
that carries nothing at all. No new endpoint was added either; `10-02`'s contract offers no
"does an operator exist for me" call, and `5-08`'s already answers exactly that question as a side
effect of its own policy. The cost is one duplicate `GET /api/v1/operators/me` on a state-(a) login
(once here, once in `PermissionsProvider`), stated rather than optimised away.

**It fails closed in both directions, which is the half that is easy to get wrong.** Neither `401`
nor `500` is read as "not an operator yet": an expired token, or an API outage, would otherwise route
an established operator into the signup form, where `10-02` would answer their registration with a
`409`. And nothing is routed optimistically — while the answer is in flight the callback shows its
spinner, because "not yet known" is not an answer. Same rule `PermissionsContext` already states for
permissions and `12-03`'s `useOwnerEligibility` for the owner view.

### What is validated client-side versus server-side

`OnboardingPage.validate()` checks two things and only for UX: the site name is not blank, and the
embed origin parses as a URL with an `http:`/`https:` scheme. `10-02`'s `RegisterSiteHandler` and its
origin validator are the actual gate, and the console deliberately does *not* mirror their full rule
(no path/query/fragment, port and trailing-slash normalisation). So `https://shop.example.com/embed`
is sent, refused server-side, and the server's own `detail` text is what the visitor reads — there is
a test whose whole purpose is to fail if someone "improves" that by moving the real rule into the
browser. Every other refusal (`Site.InvalidName`, `Site.RateLimited`, an unrecognised failure) is
surfaced in the server's wording too, so a new rejection reaches the visitor without a console
release. The one code the console *branches* on is `Site.AlreadyRegistered` — see below.

### Three defects found and fixed while writing the tests

- **The "Sign up" button could do nothing, silently, forever.** The redirect was fired as
  `void keycloakRegistrationRedirect()`, and that call fetches Keycloak's discovery document before
  it can build anything. Keycloak down, realm renamed, network gone — the rejection was discarded and
  the page did not change. The one person this affects is a visitor with no account, who has no
  operator to ask. It now says so, and can be retried.
- **The registration URL was derived by `String.replace`, which fails open.** With no match,
  `replace` returns the string unchanged — so an `authorization_endpoint` anywhere but the expected
  path would have sent a visitor with no account to the *login* page. The derivation moved into
  `ago-console/src/auth/registrationUrl.ts`, matches on the URL's *pathname* (a realm at
  `auth.<domain>` — which is this project's own, `adr/0026` — would be corrupted by a substring match
  on the whole URL), and throws rather than substituting the wrong destination.
- **`Site.AlreadyRegistered` was a dead end built out of a success.** Reaching `/onboarding` with a
  site already registered is ordinary — a bookmark, the back button, a second tab — and `10-02`
  answers that with a `409`. The form rendered it as an error whose only exit was signing out. It now
  routes to the queue: the server just said the caller is an operator, which is the same answer
  `resolveOperatorState` reads at the callback, arrived at from the server's own stable `type` code
  rather than a client-side guess. Plus a real double-submit guard — a single-input form still
  submits on Enter, so a disabled button was a presentation of the rule and not the rule.

### The tests

`ago-console` 122 tests / 13 files → **155 / 18**. Five new files:
`auth/registrationUrl.test.ts` (5), `api/operatorState.test.ts` (6), `pages/CallbackPage.test.tsx`
(6), `pages/SignupPage.test.tsx` (5), `pages/OnboardingPage.test.tsx` (11). No new npm package —
`11-08`'s `src/testing/dom.tsx` is reused unchanged. `typecheck`, `lint`, `test`, `build` green.

**Every one of the 33 is failed by at least one deliberate break** — 23 breaks in total, each applied
and reverted, because `11-08` found one of its own tests certifying nothing. The ones worth naming:
swapping the callback's two destinations fails 3; catching the resolution error into "assume a fresh
signup" fails 1; reading any refusal as state (b) fails 2; deriving the state from the token instead
of asking the server fails 5; restoring the swallowed redirect failure fails 1; putting a password
input on the console's own signup page fails 1; making the client's validation warn-and-post-anyway
fails 4; and reimplementing `10-02`'s origin rule in the browser fails 1.

### What was verified live, and where it stops

Driven for real in a browser against the local Keycloak (`ago-chat` realm, the running compose/k8s
loop), 2026-08-25:

- `/signup` renders for a visitor with **no session at all** — the fourth surface `adr/0023` did not
  anticipate, outside `RequireAuth` and outside both operator providers.
- Clicking "Sign up" lands on Keycloak's own hosted **Register** form, at
  `…/protocol/openid-connect/registrations`, carrying the same `state`, `code_challenge`,
  `code_challenge_method=S256` and `redirect_uri` the login request would have — and showing the
  required `Email` / `First name` / `Last name` fields `10-01` configured to avoid `5-05`'s
  `VERIFY_PROFILE` gotcha. This is the piece that could only ever have been proven against a real
  discovery document.
- `/onboarding` with no session redirects to Keycloak's **`auth`** endpoint (`RequireAuth`, `5-06`,
  unchanged) — the two paths are genuinely different destinations, not one URL with a flag.

**It stops at the password field, and that is a hard stop, not an omission.** Completing the form
means typing a password, which this agent does not do. Everything after it — the verification mail
(now real, `10-05`/`adr/0040`), the link, the callback exchanging the code, the `403` routing to
`/onboarding`, the site form, and the queue — is untested by hand and rests on the automated tests
above plus `10-02`'s own passing integration suite. What remains is one uninterrupted browser session
by a human: register with a throwaway address, verify from Mailpit, finish the site form, land in the
queue, then sign in again as an existing operator and confirm state (a) still goes straight there.

### No server-side change is needed, and one observation for whoever owns `ago-chat`

Nothing in this item required a change to `ago-chat` or `ago-deploy`, and none was made. Two things
noticed while reading, offered as observations rather than requests:

- `RequireKeycloakIdentity` does not check `email_verified`. Harmless today, because Keycloak will
  not issue a token at all while the `VERIFY_EMAIL` required action is outstanding — the gate is the
  IdP's, not the API's. Worth knowing that the API would accept an unverified identity if that realm
  setting ever changed, which is precisely `adr/0034`'s CAPTCHA trigger seen from the other side.
- `10-02`'s own Scope already flags the missing `GET /api/v1/sites/{id}` behind its `201 Location`.
  This console never follows that header (it navigates to the queue), so nothing here depends on it —
  recorded so the gap is not attributed to this item later.

## Open questions

None — this item depends on `10-01`/`10-02`'s contracts existing first; no new product-shape decision
is left once those are answered.
