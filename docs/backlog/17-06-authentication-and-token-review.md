# Authentication and tokens: the review, and the two settings nobody chose

- **Stage**: 17
- **Status**: ready
- **Depends on**: nothing. Pairs with `17-03`, which makes the visitor signing key rotatable at
  whatever lifetime this item settles on — neither blocks the other.

## Goal

Every way into this system is reviewed once, deliberately, rather than trusted because each piece
looked reasonable when it was written. Two settings in particular were never chosen at all: they are
Keycloak's defaults, on a realm that has been open to public self-registration since Stage 10.

## What the audit found

Checked 2026-08-25.

**The realm sets no security policy whatsoever.** `keycloak-realm-import.json` specifies none of
`bruteForceProtected`, `failureFactor`, `passwordPolicy`, or any OTP policy, so Keycloak's own
defaults apply — and its default for brute-force protection is *off*. With `registrationAllowed: true`
(Stage 10) this means anyone can register an account with a password of any length or triviality, and
nothing slows down repeated failed login attempts against an existing one.

**The visitor token is long-lived, globally signed, and irrevocable.**
`JwtTokenService.IssueVisitorToken` sets `expires: now.AddDays(30)` with a single symmetric key shared
by every site. Nothing recorded why thirty days. There is no revocation, no logout, and no per-site
key, so the only lever is the key itself — see `17-03` for what pulling it currently costs.

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

- [ ] The realm import sets brute-force protection, a password policy, and a recorded decision on a
      second factor — verified by a re-import and a real failed-login sequence that locks out.
- [ ] The visitor token's lifetime is a stated decision with reasoning, whatever the number.
- [ ] The revocation question is answered, and implemented if the answer is yes.
- [ ] Keycloak's operator-side lifetimes are reviewed and set explicitly rather than inherited.
- [ ] Tests prove the two token schemes cannot be substituted for each other, including on the shared
      attachment route.
- [ ] The registration-CAPTCHA question has a recorded answer, and `10-01`'s deferral points at it.

## Open questions

None that block starting. The lifetime and revocation choices are this item's own to make and record,
which is exactly what it exists to do.
