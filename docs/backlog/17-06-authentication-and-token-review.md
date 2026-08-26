# Authentication and tokens: the review, and the two settings nobody chose

- **Stage**: 17
- **Status**: done (2026-08-25) - `adr/0034` records every decision; the realm settings landed in both
  realm-import files, and the token-scheme separation is tested rather than inferred. One sub-check is
  deliberately left open below (the hosted registration form's own browser flow), and one finding is
  named as follow-up rather than closed (`sslRequired`).
- **Depends on**: nothing. Pairs with `17-03`, which makes the visitor signing key rotatable at
  whatever lifetime this item settles on — neither blocks the other.

## Goal

Every way into this system is reviewed once, deliberately, rather than trusted because each piece
looked reasonable when it was written. Two settings in particular were never chosen at all: they are
Keycloak's defaults, on a realm that has been open to public self-registration since Stage 10.

## What the audit found

Checked 2026-08-25.

**The realm's security policy is inherited, not chosen.** `keycloak-realm-import.json` leaves
Keycloak's login-security settings unset, so upstream defaults apply — and upstream defaults are
written for a realm an administrator will configure, not for one that has been open to public
self-registration since Stage 10. Nobody looked at them; that is the finding. The specific settings and
their current values are visible to anyone reading that file in this public repository, so this item
does not restate them — writing them out more vaguely would protect nothing and writing them out
precisely would be a notice. The remedy is to set them, not to describe them better.

Worth being clear about the size of it: as a demo with no real tenants this costs little today, and it
becomes expensive at exactly the moment it stops being a demo. Doing it before the first real customer
is a realm-import change; doing it after is an operation on live accounts.

**The visitor token is long-lived, globally signed, and irrevocable.** A single symmetric key shared
by every site, a lifetime nothing recorded a reason for, and no revocation, no logout and no per-site
key — so the only lever is the key itself, and `17-03` covers what pulling it currently costs. Stated
here as design rather than as a hole: the token grants its own visitor's own conversation and nothing
else, which is why this sits below the realm settings above in urgency despite sounding worse.

**Two things are already right and should be confirmed rather than changed.** The hub token in the
query string is accepted only on the two hub paths (`HubTokenFromQueryString` in `Program.cs`), which
is the correct narrowing of a mechanism a browser forces on us. And the `Kind` claim that lets one
attachment route serve both schemes (`5-03`) sits alongside distinct audiences per scheme — which
should mean a visitor token cannot be presented as an operator one, and this review is where that
stops being an inference.

## Context to read first

`adr/0022` — operator authentication through Keycloak, and the claims model. `adr/0028` — why
Keycloak's own hosted registration was chosen, which is what makes the realm's missing password policy
a live concern rather than a theoretical one. `ago-chat/src/Ago.Chat.Api/Program.cs` — both JWT
schemes, their audiences, and `HubTokenFromQueryString`. `ago-chat/src/Ago.Chat.Api/Auth/` in full —
the token service, the claims transformation, and `ClaimsPrincipalExtensions`.
`docs/architecture/authorization.md` — what a token is trusted to assert once validated.
`docs/backlog/10-01-self-registration-identity-flow.md` — its deliberate deferral of a registration
CAPTCHA, which belongs to this item's abuse half.

## Scope

- **Set the realm's security policy deliberately**: brute-force protection on, with chosen thresholds;
  a password policy that states its own minimum rather than inheriting none; and a decision, recorded
  either way, on whether operators can enable a second factor. Each value written into the realm
  import so it survives a re-import, not clicked in an admin console.
- **Decide the visitor token's lifetime on purpose.** Thirty days is a real product choice — it is how
  long a returning visitor still sees their history without re-identifying — and it is also the
  window a stolen token stays useful and the time a key rotation takes to complete. State the number
  and the reasoning, whether or not it stays thirty.
- **Decide whether visitor sessions need revocation at all.** A deny-list keyed by token id in Redis is
  cheap; a shorter lifetime with silent renewal is cheaper still and removes the question. Both are
  defensible and neither exists; pick one and say why.
- **Review the operator side against Keycloak's actual configured lifetimes** — access token, refresh
  token, SSO idle and max — none of which the realm import sets either, so all are defaults nobody
  reviewed. Confirm they suit an operator console someone sits in all day.
- **Confirm, with a test, that the two schemes cannot be substituted for one another**: a visitor token
  rejected everywhere an operator token is required, and the reverse, including on the shared
  attachment route where the `Kind` claim does the distinguishing.
- **Registration abuse**: `10-01` deferred a CAPTCHA deliberately and named it as such. Revisit it here
  with the realm's new brute-force settings in hand, and decide — a registration rate limit per IP
  already exists, so this is about whether that is enough, not about starting from nothing.

## Out of scope

- Tenant isolation and permission enforcement — `17-01`. This item is about who a caller *is*; that one
  is about what they may reach.
- The token appearing in logs and spans — `5-14` and `17-02`.
- Secret rotation mechanics — `17-03`.
- Replacing Keycloak, or changing `adr/0022`'s model.
- Owner-facing abuse signals across tenants — `12-02` already scopes that as a reporting surface.

## Done when

- [x] The realm import sets brute-force protection, a password policy, and a recorded decision on a
      second factor — verified by a re-import and a real failed-login sequence that locks out.
      Both realm-import files carry the settings; the decision on a second factor is "no mandatory
      TOTP, parameters chosen anyway, and here is the trigger" (`adr/0034`). Verified two ways. A
      throwaway Keycloak 26.0 container was started against `ago-deploy`'s own file, the realm read
      back over the admin API (every value present, none inherited), then `demo-operator`'s correct
      password proven to work, ten scripted wrong passwords sent, and the *correct* password then
      rejected — the only unambiguous proof, since Keycloak deliberately returns the same
      `invalid_grant` for a locked account and a wrong one. `demo-admin` was unaffected (per-user, not
      global) and the lockout cleared itself inside a minute (`permanentLockout: false`, behaviourally
      and not just declared). The password policy was probed live too: 7 characters refused, the
      username refused, the email refused, a 24-character passphrase accepted. The same sequence now
      runs on every build as `RealmLoginSecurityTests` against the Testcontainers realm.
- [x] The visitor token's lifetime is a stated decision with reasoning, whatever the number. **Thirty
      days, unchanged in value and changed in status** — `adr/0034` and
      `JwtTokenService.VisitorTokenLifetime`, which is now a named constant so the number and its
      reasoning sit together. The item's framing that this is a free knob turned out to be wrong; see
      "What this item got wrong" below.
- [x] The revocation question is answered, and implemented if the answer is yes. **Answered: no.** No
      deny-list, so nothing to implement. `adr/0034` has the argument — no caller exists that could
      decide to revoke, and a deny-list would make an authentication decision depend on Redis, which
      `adr/0009` forbids as truth. The trigger that reopens it is named.
- [x] Keycloak's operator-side lifetimes are reviewed and set explicitly rather than inherited. Access
      token 5 minutes, SSO idle 4 hours, SSO max 12 hours, offline idle 7 days, user action tokens 15
      minutes. One correction to this item's own scope: **there is no separate refresh-token lifetime
      to set** — for standard sessions a refresh token lives exactly as long as its SSO session, so
      the two SSO settings *are* it.
- [x] Tests prove the two token schemes cannot be substituted for each other, including on the shared
      attachment route. `TokenSchemeSeparationTests`, five tests, both directions, against a real
      Keycloak-issued operator token and a real `JwtTokenService`-issued visitor token. The shared
      route's policy is exercised through the same method `AttachmentEndpoints` passes to
      `RequireAuthorization`, not a transcription of it. The item was right that substitution does not
      work — and the review found a third state that route had no answer for; see below.
- [x] The registration-CAPTCHA question has a recorded answer, and `10-01`'s deferral points at it.
      **Still no**, for reasons that are not the brute-force settings (`adr/0034` says so explicitly,
      because "we added brute-force protection" is exactly the adjacent-sounding change that gets
      mistaken for closing this). `10-01`'s Out-of-scope entry now points at `adr/0034`.

## What this item found that its own description did not anticipate

**A third principal on the shared attachment route.** `5-03`'s routes branch on
`ClaimsPrincipalExtensions.IsOperator()` and read `false` as "therefore a visitor". Since `10-01`
opened the realm to public self-registration there is a caller who is neither: a
signature/audience/lifetime-valid Keycloak token whose `sub` matches no `operators` row. It was
classified as a visitor whose id was Keycloak's own `sub` GUID. **Nothing was reachable through it** —
each handler then compares that id against the conversation's real visitor, and a Keycloak subject id
never matches one — so this is a mis-classification, not an access-control failure, and it is reported
as such rather than dressed up. Closed at the policy layer: the route now requires the `kind` claim to
hold one of two known values. The test that proves it was checked against the pre-fix code and does
fail there, so it is a regression test and not a tautology.

**The visitor token's lifetime is not a free knob.** `ago-widget`'s `getOrCreateVisitorSession` reuses
a stored token forever: it never inspects `exp` and never re-mints. So the lifetime is not only "how
long a stolen token is useful", it is also "the day the widget silently stops working for a returning
visitor" — and shortening it without renewal moves that day closer while buying nothing, because the
minting endpoint is public and unauthenticated. `17-07` is the piece that has to exist first.

**`quickLoginCheckMilliSeconds`, not `failureFactor`, is what actually fires against a script.**
Observed live: after ten scripted attempts Keycloak's attack-detection view reported
`numFailures: 2, disabled: true` — two failures inside one second tripped the quick-login guard long
before the tenth failure. Both thresholds are wanted; they catch different attackers. It is also why
`RealmLoginSecurityTests` asserts "the account is disabled" rather than an exact failure count.

## Left open, deliberately

- **The hosted registration form's own browser flow was not driven end to end.** Typing a password
  into Keycloak's own signup page is an interactive step this dispatch could not perform, and it is
  currently blocked anyway for a known reason that is not this item's: `verifyEmail: true` with no
  `smtpServer` means registration ends at `SEND_VERIFY_EMAIL_ERROR` (`10-05`, and `local-dev.md`'s
  admin-API shortcut). What *was* verified is the part this item changed — that the realm enforces the
  new password policy at password-set time, proven against the admin API rather than the form.
- **`sslRequired` is still `"none"`.** Explicitly chosen rather than inherited, and the public demo is
  only reachable over HTTPS (the Gateway redirects `:80`), so nothing is served in the clear in
  practice. Tightening it to `"external"` requires Keycloak to trust `X-Forwarded-Proto`
  (`--proxy-headers=xforwarded`), which cannot be verified against the plain-HTTP local cluster and
  would lock out the login page if wrong. Named in `adr/0034`'s Consequences as follow-up rather than
  changed blind.

  > **Closed 2026-08-26 by `17-05`/`adr/0054` §4** — raised to `"external"` and verified against the
  > real `--proxy-headers=xforwarded` configuration on the public deployment (NGF does set
  > `X-Forwarded-Proto`; login page, direct-grant token and the API's acceptance of the JWT all still
  > 200). The instinct above was right about not changing it blind, and one thing it did not predict:
  > with `--hostname=https://auth...` set, `"external"` refuses nothing on this deployment either. It
  > is a guard against a future misconfiguration, not the closing of a live hole.
- **The live cluster was not restarted to apply the new realm.** The verification ran against an
  isolated throwaway container on the identical Keycloak version with the identical file, which proves
  the same thing without destroying the running demo's runtime state (`15-01`: this Keycloak has no
  persistent store, so a restart takes every runtime-created user and the hand-granted `platform-owner`
  role with it). The settings reach the demo on its next ordinary redeploy.
- **Nothing mechanically keeps the two realm-import files in step.** They live in different
  repositories, so no test can compare them. `adr/0034` is the only thing holding them together, and
  that is stated there as a real weakness rather than hidden.

## Open questions

None that block starting. The lifetime and revocation choices are this item's own to make and record,
which is exactly what it exists to do. **Resolved 2026-08-25** — both are recorded in `adr/0034`, each
with the trigger that would reopen it.
