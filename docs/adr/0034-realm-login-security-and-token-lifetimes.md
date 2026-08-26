# ADR-0034: the realm's login-security policy, and every token lifetime, chosen rather than inherited

- **Status**: Accepted
- **Date**: 2026-08-25
- **Stage**: 17

## Context

`17-06`'s audit found that `keycloak-realm-import.json` set none of Keycloak's login-security
settings, so upstream defaults applied to a realm that `adr/0028` opened to public self-registration
in Stage 10. Upstream defaults are written for a realm an administrator will go on to configure; this
one had no such second step. The same is true one layer up, of every token lifetime in the system:
Keycloak's four session/token lifespans were absent from the same file, and `Ago.Chat.Api`'s own
visitor token carried a thirty-day expiry that no note, ADR or commit message ever gave a reason for.

None of this was a bug anyone could point at. That is exactly why it needed an item: nothing fails,
no test goes red, and the cost only arrives at the moment the demo stops being a demo — a realm-import
edit today, an operation on live accounts once there are real customers.

Two constraints shape every number below.

**Public self-registration is already on.** Anyone can create an account in this realm. So a setting's
worst case is not "an administrator mis-typed a password three times", it is "an attacker who can
enumerate usernames chooses how this realm behaves".

**The visitor token is not a session credential in the usual sense.** Its minting endpoint,
`POST /api/v1/visitor-sessions`, is public and unauthenticated by design (`api-design.md`) — a site's
public key is not a secret. Anyone who can read a visitor token off a page can also mint a fresh one
for the same site. What the token uniquely grants is the binding to *one existing conversation's*
history, and nothing else.

## Decision

### Brute-force protection: on, temporary, and deliberately not permanent

`bruteForceProtected: true`, `permanentLockout: false`, `failureFactor: 10`,
`waitIncrementSeconds: 60`, `maxFailureWaitSeconds: 900`, `maxDeltaTimeSeconds: 43200`,
`quickLoginCheckMilliSeconds: 1000`, `minimumQuickLoginWaitSeconds: 60`.

**Ten failures, not Keycloak's thirty.** Thirty is generous enough to be worth a guessing attempt
against a weak password; ten is more than any human mistypes in a twelve-hour window and small enough
that an online guessing attack is not worth mounting. `maxDeltaTimeSeconds` (12 hours) is the window
those ten accumulate in, so a genuinely forgetful operator across two shifts is not treated as an
attack.

**Never permanent.** This is the setting the open registration form actually changes. On a realm
anyone can enumerate, `permanentLockout: true` hands an attacker a denial-of-service: ten wrong
passwords against a known username and that person cannot work until an administrator intervenes.
Exponential backoff capped at 15 minutes (`waitIncrementSeconds`/`maxFailureWaitSeconds`) makes
guessing hopeless while leaving the account self-healing.

**The quick-login guard is the one that actually fires against a script.** Two failures inside one
second are not a person, and the 60-second penalty that follows is what a scripted attempt hits first
— observed live, not assumed: after ten scripted attempts Keycloak's own attack-detection view
reported `numFailures: 2, disabled: true`, because the quick-login guard tripped long before
`failureFactor` did. Both thresholds are wanted; they catch different attackers.

### Password policy: length, not composition

`length(12) and notUsername(undefined) and notEmail(undefined) and passwordHistory(3)`.

Twelve characters, and no upper/lower/digit/symbol requirement. Composition rules push people toward
`Password1!` and are the part of a policy that gets worked around rather than followed; length is the
part that actually costs an attacker. `notUsername`/`notEmail` block the two guesses any attacker
tries first on a realm where both are visible. `passwordHistory(3)` exists so a forced reset is not
undone by re-entering the same password.

Deliberately **not** set: `hashAlgorithm`. Keycloak 24+ already defaults to Argon2; pinning it here
would also apply to the Keycloak 21 the integration-test realm runs, where Argon2 is not available.

### Second factor: parameters chosen, enrolment not forced

`otpPolicyType: "totp"`, `otpPolicyAlgorithm: "HmacSHA1"`, `otpPolicyDigits: 6`,
`otpPolicyPeriod: 30`, `otpPolicyLookAheadWindow: 1`. **No realm-wide required action forces
enrolment.**

The decision the item asked for, recorded either way: **no mandatory second factor today.** Three
reasons, in order of weight. There is no tenant to protect yet — every account in this realm is a demo
account whose password is published in a public repository, so mandatory TOTP would be ceremony over
credentials that are not secret. Forcing it would break every scripted login this project relies on
(the integration suite's direct-access grants, and `local-dev.md`'s curl recipe), replacing a real
verification path with a manual one. And a support console's realistic threat is a shared or
unattended workstation, which `ssoSessionIdleTimeout` below addresses more directly than a second
factor does.

What is decided is that the *parameters* are no longer defaults nobody chose, so turning it on for one
operator, or for a whole realm, is a switch rather than another set of unreviewed values. **The
trigger that changes this answer**: the first account that is not a demo account — i.e. the first
tenant whose data a stolen operator password would actually expose.

### Keycloak's operator-side lifetimes

`accessTokenLifespan: 300`, `ssoSessionIdleTimeout: 14400`, `ssoSessionMaxLifespan: 43200`,
`offlineSessionIdleTimeout: 604800`, `actionTokenGeneratedByUserLifespan: 900`.

The console is something an operator sits in for a whole shift, so the shape wanted is a *short*
access token with a *long* session behind it — the standard OIDC arrangement, and the one that keeps
the credential actually presented on every request cheap to steal and useless quickly.

- **Access token, 5 minutes.** This equals Keycloak's own default, and is set explicitly anyway: an
  inherited value that happens to be right is still a value nobody chose, and it would move silently
  under a Keycloak upgrade. Five minutes bounds what a token captured from a log or a span
  (`17-02`'s subject) is worth.
- **SSO idle, 4 hours.** This is the operator-facing number: it is how long a console can sit
  untouched before the operator has to log in again. Thirty minutes (Keycloak's default) would log
  someone out over lunch; four hours covers a break without covering an overnight absence at an
  unattended workstation.
- **SSO max, 12 hours.** One shift plus margin, then a real re-authentication regardless of activity.
  Keycloak's default is 10 hours, which would cut a long shift in half.
- **There is no separate "refresh token lifetime" to set** — `17-06`'s scope named one, and the
  honest answer is that Keycloak does not have that knob for standard sessions: a refresh token lives
  exactly as long as the SSO session it belongs to. The two settings above *are* the refresh token's
  lifetime, which is worth stating so nobody looks for a third setting that does not exist.
- **Offline sessions, 7 days idle** (Keycloak's default is 30). An offline token is the one credential
  here that can outlive every setting above, and `ago-console` is a public client. Nothing in this
  project requests `offline_access`; capping it is defence against a scope that arrives later by
  accident rather than by decision.
- **User action tokens, 15 minutes** (default 5). These are the email-verification and password-reset
  links. Five minutes is a usability trap the moment mail takes a minute to arrive — and mail will,
  once `10-05` gives this realm an SMTP server at all.

### The visitor token: 30 days, and why it was not 7 yet — superseded, it is 7 now

> **Superseded in part by `adr/0048` (2026-08-25).** `17-07` built the renewal path this section says
> does not exist, so the premise underneath the number is gone and the decision is now **7 days,
> sliding, with no absolute cap**. What survives is everything below about *why* the number could not
> be lowered on its own — that reasoning is why `0048` exists and it is still the honest account of
> the state this project was in.
>
> **Both halves have shipped (2026-08-26), so nothing below describes what is running.** `ago-widget`
> renews (`VisitorSessionManager`, `tokenExpiry.ts`, `17-07`) and is lifetime-agnostic: it derives its
> renewal window from the token itself, so it was correct against both numbers and needed no change
> when the second half landed. The `Ago.Chat.Api` half is `17-08`:
> `POST /api/v1/visitor-sessions/renew` exists on the Visitor scheme, and
> `JwtTokenService.VisitorTokenLifetime` is `TimeSpan.FromDays(7)`. `authorization.md` states the
> shipped shape; this section is history.

**The lifetime stayed 30 days** at this decision, and gained a stated reason. (Tense deliberate: the
number moved to 7 in `adr/0048`/`17-08`. Everything from here to the end of this section is the
reasoning as it stood, kept because it is why the number could not simply be lowered — not because it
describes what runs.)

The number is a product promise before it is a security parameter: the widget's
`getOrCreateVisitorSession` reuses a stored token rather than minting a new identity per page view, so
this value *is* "how long a returning visitor still sees their own conversation" — there is no other
setting that expresses it.

Shortening it would not currently buy security so much as break returning visitors sooner, because
that same function has **no renewal path**: it neither inspects `exp` nor re-mints. A shorter lifetime
therefore moves the day the widget silently stops working from day 31 to day 8; it does not narrow
what an attacker can do, because of the second constraint in Context — the minting endpoint is public,
so an attacker positioned to read the token can mint their own. What the lifetime genuinely bounds is
one visitor's own transcript remaining reachable from a shared or lost device.

**7 days was the target, and it was blocked on renewal existing, not on this decision** — which is
exactly how it played out. `17-07` shipped silent renewal in `ago-widget` and `17-08` shipped
`POST /api/v1/visitor-sessions/renew` plus the constant in `Ago.Chat.Api`; `adr/0048` is where that
decision is recorded. It took two changes rather than the one this paragraph predicted, deliberately:
the widget half was built to be correct against the endpoint's absence (a `404` is a transient
failure, so a visitor keeps the valid token they already hold), which let each half be reviewed on
its own. `17-03` inherits this number as its key-rotation drain window, and that window is therefore
**7 days**.

### Visitor session revocation: no deny-list

**No Redis deny-list, and no per-token revocation of any kind.**

The reason is not cost — a deny-list keyed by `jti` would be a small amount of code against the Redis
surface this project already has. It is that **there is no caller**. Nothing in this system can
currently decide that a specific visitor token should stop working: there is no visitor logout, no
"sign out other devices", no operator action that reports a compromised session, and no signal that
would detect one. A deny-list with no writer is not an unused abstraction, it is a mechanism whose
entire failure surface exists for a code path that never runs — worse than
`clean-architecture.md`'s "an abstraction with one caller is a guess about the second one".

Two further reasons make it the wrong shape even if a caller appeared tomorrow. A deny-list checked on
every request makes an authentication decision depend on Redis being up, and `adr/0009` is explicit
that Redis is never a source of truth — the honest failure mode of a Redis outage would be
"revocations silently stop applying", which is a security control that quietly disables itself. And
global revocation already exists: rotating the visitor signing key invalidates every visitor token at
once, which is `17-03`'s subject and is the correct blunt instrument for the only scenario currently
imaginable (the key itself leaked).

**The trigger that changes this answer**: the first surface that lets anyone say "end this session" —
a visitor-facing "forget me" control (`16-02`'s erasure work is the likely home) or an operator-facing
report of abuse. That is the caller a deny-list needs, and it should be built with that caller, not
before it.

### Registration CAPTCHA: still no, with a named trigger

`10-01` deferred a registration CAPTCHA explicitly. Revisited here with the brute-force settings in
hand: **still no, and the brute-force settings are not the reason** — they protect existing accounts
from password guessing and do nothing whatsoever about account *creation*. Saying so plainly matters,
because "we added brute-force protection" is exactly the kind of adjacent-sounding change that gets
mistaken for closing this.

The reasons it stays deferred:

- **What a spam account currently gets is nothing.** `verifyEmail: true` with no `smtpServer`
  (`10-05`) means a registered account cannot complete verification, so it cannot reach `10-02`'s
  bootstrap endpoint and cannot create a `Site` or an `Operator`. The abuse ceiling is rows in
  Keycloak's own user table — noise in a demo, not a foothold in this system.
- **A CAPTCHA is a third-party secret and a third-party dependency.** Keycloak's reCAPTCHA
  authenticator needs a Google secret key, which would be the first secret whose *absence* breaks the
  login page rather than a background job, and it would attach a Google call to the sign-up path just
  as `16-01` is about to write down a data-residency constraint. Acquiring that before it is needed is
  the wrong order.
- **The coarse per-IP limit at the edge covers floods, not this.** The Gateway's 30 r/s
  `RateLimitPolicy` applies to the Keycloak hostname along with everything else, so it stops a
  registration flood; it does nothing about a patient script. It is honest to call it a flood
  backstop rather than a registration limit.

**The trigger that changes this answer** — stated so a later session does not have to re-derive it:
the day a self-registered account can create a tenant with no human in the loop *and* `10-05` makes
email verification actually work. At that moment the cost of a tenant drops to "one deliverable
mailbox", and a CAPTCHA (or an invite/waitlist gate, which is cheaper and needs no third party)
earns its place. Whichever is chosen then, it is realm configuration or a console change, touching
nothing in `Ago.Chat.Api`.

### The shared attachment route now requires a `kind` claim, not merely an authenticated caller

`17-06` set out to *confirm* that a visitor token and an operator token cannot be substituted for one
another. They cannot, and there are now tests saying so in both directions
(`TokenSchemeSeparationTests`). But the same review found a third state the shared attachment route
(`5-03`) had no answer for, and this is where the decision about it is recorded.

`AttachmentEndpoints` branches on `ClaimsPrincipalExtensions.IsOperator()`, which reads the `kind`
claim — and read `false` as "therefore a visitor". Since `adr/0028` opened the realm to public
self-registration there is a principal that is neither: a signature/audience/lifetime-valid Keycloak
token whose `sub` matches no `operators` row. It authenticates on the Operator scheme, gains no `kind`
claim (only `OperatorIdentityClaimsTransformation`'s *successful* path adds one), and so fell into the
visitor branch, where `GetVisitorId()` parsed Keycloak's own `sub` GUID as a `VisitorId`.

**Nothing was reachable through it** — every handler on that route then compares that id against the
conversation's real visitor and never matched, so this was a mis-classification, not an access-control
failure, and it is reported as such. `12-01`'s platform-owner token was in the same position.

The fix is at the policy layer, not in each handler: the route group requires `kind` to be one of two
known values, so a principal carrying neither is a `403` before any handler runs. Chosen over adding a
third branch to each of the three handlers because the question "is this caller one of the two kinds
this route serves" is an authorization question, and `adr/0028` already established the policy layer
as where this codebase expresses "which claims must hold after the scheme validated the token". The
policy is a named method (`AuthorizationPolicies.EitherTokenKind`) rather than the inline lambda it
was, for the plain reason that a lambda inside `MapAttachmentEndpoints` cannot be exercised by a test.

### The two realm-import files: same security policy, deliberately different lifetimes

This project maintains two realm imports — `ago-deploy/k8s/base/keycloak-realm-import.json` (the
local/demo deployment) and `ago-chat/tests/Ago.Chat.Integration.Tests/keycloak-realm-import.json` (the
Testcontainers realm). They now carry **identical** brute-force, password-policy and OTP settings, and
**deliberately different** lifetimes.

Identical security policy, because a test realm that does not carry the settings cannot verify them —
and `RealmLoginSecurityTests` exists specifically to hold them in place, which requires the realm
under test to have them.

Different lifetimes, because those are test instruments rather than policy in that file: the test
realm's `accessTokenLifespan: 5` is what `OperatorOidcAuthenticationTests.ExpiredToken_IsRejected`
depends on, and a 12-hour SSO session in a container that lives for one test class means nothing.
The divergence is stated here because JSON cannot carry a comment, which is the whole reason this
paragraph exists rather than a line in either file.

## Consequences

- **Every seeded demo password must satisfy the policy.** They all do today (the shortest is 19
  characters). A future seed user with a short password will now be rejected at import or at
  password-set time rather than working silently — verified live: `short12` is refused with
  `invalidPasswordMinLengthMessage`.
- **A locked-out demo account is now a real thing a session can hit**, including one's own, by
  fat-fingering a password twice inside a second. It clears itself in 60 seconds; the admin API's
  `attack-detection/brute-force/users` endpoint clears it immediately. Worth knowing before assuming
  a broken deployment.
- **`RealmLoginSecurityTests` couples the test suite to the realm's security policy on purpose.**
  Changing `failureFactor` now breaks a test, which is the point — it is the mechanism that stops
  these settings from drifting back to "whatever the file happened to say".
- **The two realm files can still drift**, and nothing mechanical prevents it: they live in different
  repositories, so no test can compare them. This ADR is the only thing holding them together, which
  is a real weakness of the arrangement and is stated rather than hidden.
- **`sslRequired` stays `"none"` and is not fixed here.** It is at least an explicitly chosen value
  rather than an inherited one, and the public demo is only reachable over HTTPS (the Gateway
  redirects `:80`), so nothing is served over plain HTTP in practice. Tightening it to `"external"`
  requires Keycloak to trust `X-Forwarded-Proto` (`--proxy-headers=xforwarded`), which cannot be
  verified against the plain-HTTP local cluster and would silently lock out the login page if wrong.
  Named as open follow-up work rather than changed blind.
- **The visitor token's lifetime is now load-bearing in two places** — this ADR and
  `JwtTokenService.VisitorTokenLifetime`, which is a named constant precisely so the number and its
  reasoning sit next to each other rather than as a `30` inside a method call.
- **Neither revocation nor a CAPTCHA exists after this item**, by decision. Both answers carry an
  explicit trigger, so the next session to ask has something to check rather than a judgment to
  repeat.

## Alternatives considered

- **Permanent lockout after N failures** — rejected above: on a realm with open self-registration it
  is a denial-of-service primitive handed to anyone who can guess a username.
- **A composition-based password policy** (upper + lower + digit + symbol) — rejected. It produces
  predictable passwords and trains people to work around the rule; length is the requirement that
  actually costs an attacker. This is the mainstream modern position (NIST SP 800-63B), not a local
  preference.
- **Mandatory TOTP for every operator** — rejected for now, with the trigger named above. The
  decisive practical objection is that it would break every scripted login this project verifies
  itself with, trading a real verification path for a manual one, at a moment when no account in the
  realm guards anything real.
- **Shortening the visitor token to 7 days now** — rejected as sequencing, not as direction. Without
  renewal it breaks returning visitors four times sooner while buying nothing, because the minting
  endpoint is public. `17-07` makes it correct; the number moves with it. **It did**: `adr/0048`,
  2026-08-25.
- **A Redis deny-list for visitor tokens** — rejected: no caller, and it would make an authentication
  decision depend on Redis, which `adr/0009` forbids as a source of truth.
- **Reducing the visitor token to a session cookie or an opaque server-side session** — considered,
  and it would answer revocation properly. Rejected as a much larger change than `17-06`: it replaces
  the widget's whole identity model (`storage.ts`, `localStorage`, no cookies on third-party sites by
  design — the `embeddable-widget` skill's own constraint), and third-party cookie blocking is
  precisely why the token lives in `localStorage` in the first place.
- **Enabling Keycloak's reCAPTCHA authenticator now** — rejected above; a third-party secret and a
  third-party dependency acquired before the abuse it prevents can actually pay off.
- **Leaving the test realm without the security settings**, so no test could be affected by them —
  rejected: it is the realm the automated proof runs against, and a proof against a realm configured
  differently from the deployed one proves the wrong thing.
