# Secrets: what exists, who holds it, and what rotating it actually costs

- **Stage**: 17
- **Status**: ready
- **Depends on**: nothing

## Goal

Every secret this system uses is written down — what it is, where it lives, who can read it, and what
happens when it has to change. Today the *handling* is sound and the *rotation* story does not exist,
and one of the secrets turns out to be far more expensive to rotate than anyone has noticed.

## What the audit found

Checked while scoping this (2026-08-25), so a session picking it up does not start from suspicion.

**Handling is genuinely fine.** `ago-deploy` carries only `.env.example` files that document shape and
never values, with a header saying so explicitly. `git check-ignore` confirms
`k8s/overlays/demo/.env` is ignored by the bare `.env` pattern, and `git ls-files` finds no tracked
`.env` or secret-shaped file anywhere. Secrets reach the cluster through a `secretGenerator` reading a
file that only exists on the machine doing the deploy. This is the part that usually goes wrong in a
public repository, and here it did not.

**Rotation is undefined, and one key is much worse than the others.**
`Ago.Chat.Api.Auth.JwtTokenService` issues visitor tokens with `expires: now.AddDays(30)`, signed with
a single symmetric key (`AUTH_JWT_SIGNING_KEY`) shared by every site, and there is no revocation
mechanism of any kind. Three consequences follow, none of them recorded anywhere:

- A leaked visitor token stays valid for up to thirty days and cannot be individually revoked.
- The only way to invalidate it is to rotate the signing key — which invalidates **every** visitor
  token, for **every** site, at once. Every visitor in the system loses their session and their
  conversation continuity simultaneously.
- So key rotation is not routine maintenance here. It is a customer-visible incident, which means in
  practice it will not be done, which means the key's effective lifetime is "forever".

**Other secrets, for completeness**: Postgres, RabbitMQ, MinIO and Keycloak admin credentials, all
from the same Secret; `GRAFANA_ADMIN_PASSWORD`, which now guards a **publicly reachable** admin UI
(`grafana.reserve-me.ru`, a deliberate call recorded in `gateway.yaml`); and
`AGO_PLATFORM_PACKAGES_TOKEN`, a classic GitHub PAT scoped to `read:packages`.

**Recorded 2026-08-25, since this item asked for it and the answer now exists.** One value, held as a
repository secret in **two** repositories — `ago-chat` and `ago-calendar`, the latter added when the
second product's CI needed the same feed. **Scope: `read:packages` only. Expires 2027-08-25.** Rotating
it means creating one PAT, setting it in both repositories, and revoking the old one *in that order* —
revoking first breaks the CI of whichever repository is pushed to next.

Two facts worth keeping beside it. Deliberately one value in two places rather than two independent
tokens: a personal account has no shared Actions secret, so two copies are unavoidable, and the choice
is only whether there is one expiry to track or two. And **`ago-platform` holds no secret at all** — it
*publishes* packages with `permissions: packages: write` and the built-in `GITHUB_TOKEN`. That is
direct evidence the consuming side could plausibly do the same: `adr/0018` justified the PAT by noting
GitHub forbids *anonymous* reads, which is true and does not describe `GITHUB_TOKEN`. Granting each
package Actions-read access to the consuming repository would remove this credential from the
inventory entirely rather than rotating it forever. Untested, and the cheapest experiment on this
list.

## Context to read first

`docs/architecture/repositories.md`'s "No secrets, ever" section — the rule this system already keeps.
`ago-deploy/k8s/overlays/demo/.env.example` and its header comment. `ago-chat/src/Ago.Chat.Api/Auth/
JwtTokenService.cs` — the thirty-day visitor token and the single symmetric key. `adr/0022` — operator
authentication moved to Keycloak, so operator tokens are not this file's problem; visitor tokens are
the only ones AGO signs itself. `adr/0018` — why the packages PAT exists at all.

## Scope

- **An inventory**, checked in: every secret, what it protects, where its value lives, who or what can
  read it, and how it is changed. Short and factual; the point is that it exists and is complete.
- **A rotation procedure per secret**, including what breaks while it happens. For database and broker
  credentials this is ordinary. For the visitor signing key it is not, and the procedure must say so
  rather than pretending otherwise.
- **Make the signing key rotatable without a mass logout.** The mechanism is well-trodden: accept more
  than one key for validation while issuing with only the newest, so an old key can be retired after
  the longest token lifetime has passed. ~~Decide whether the thirty-day lifetime is itself right
  while looking at this~~ — **answered 2026-08-25 by `17-06`/`adr/0034`: it stays thirty**, and now
  for a stated reason. It is a product promise (how long a returning visitor still sees their own
  conversation) more than a security parameter, because the minting endpoint is public and
  unauthenticated — anyone who can read a token off a page can mint their own. So this item's drain
  window is thirty days, and it becomes seven when `17-07` gives the widget a renewal path; build the
  multi-key acceptance so the retirement delay is configuration rather than a constant.
- **A leak procedure**: what to do when a secret is known to be exposed, per secret, given the above.
  One page in the runbook, not a policy document.
- Note the packages PAT's expiry somewhere a human will see it before CI breaks. **The date is now
  known (2027-08-25) and written above — but a backlog file is a record, not a reminder.** It will not
  fire. Whatever does fire, a calendar entry being the obvious one, is the actual deliverable here;
  writing the date down and calling it done is the failure this bullet was trying to prevent.

## Out of scope

- Bringing in a secret manager (Vault, SOPS, sealed-secrets, a cloud KMS). A real option, and a real
  cost for a one-node deployment whose current handling is already correct; if the inventory turns up
  something the present approach genuinely cannot hold, that becomes its own item with that finding as
  its argument.
- Encrypting Kubernetes Secrets at rest — `17-05`, since it is a cluster-configuration matter rather
  than a handling one.
- Token lifetimes, revocation semantics, and the visitor session model — `17-06`.
- Auditing git history for previously committed secrets. Worth doing, but it is a different technique
  (history scanning) and it would be its own item if the inventory suggests a reason to.

## Done when

- [ ] The inventory exists and lists every secret named above, plus any the sweep adds.
- [ ] Each has a written rotation procedure stating what breaks during it.
- [ ] The visitor signing key can be rotated with overlapping validation, proven by rotating it in a
      local environment without invalidating a live token.
- [ ] A leak procedure exists in the runbook.
- [ ] The packages PAT's expiry is recorded **in something that fires**, not only written down. The
      date itself (2027-08-25) is already in this file.

## Open questions

None for the work itself. ~~The thirty-day visitor-token lifetime is a real question and it belongs to
`17-06`~~ — **settled 2026-08-25**: `adr/0034` kept it at thirty and named `17-07` as what lets it
drop to seven. This item still makes rotation possible at whatever lifetime that number is, which is
now a value with reasoning attached rather than an open question.
