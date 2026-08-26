# Secrets: what exists, who holds it, and what rotating it actually costs

- **Stage**: 17
- **Status**: implemented 2026-08-27 — the mechanism, the inventory, both procedures and the reminder
  are in. **Nothing has been rotated**: the Done-when that asks for a rotation performed in a live
  environment is proven by tests and not by an act, and says so below. The sweep also turned up one
  finding this item deliberately did not fix, recorded in the inventory's "Open finding" section.
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

**Rotation is undefined, and one key is much worse than the others.** *(As found. The third bullet is
what `adr/0067` closed — see "What shipped" at the foot of this file. The lifetime read `AddDays(30)`
when this was written and is `JwtTokenService.VisitorTokenLifetime`, seven days, since `17-08`.)*
`Ago.Chat.Api.Auth.JwtTokenService` issues visitor tokens signed with
a single symmetric key (`AUTH_JWT_SIGNING_KEY`) shared by every site, and there is no revocation
mechanism of any kind. Three consequences follow, none of them recorded anywhere:

- A leaked visitor token stays valid for up to seven days (thirty until `17-08`) and cannot be
  individually revoked.
- The only way to invalidate it is to rotate the signing key — which invalidates **every** visitor
  token, for **every** site, at once. Every visitor in the system loses their session and their
  conversation continuity simultaneously.
- So key rotation is not routine maintenance here. It is a customer-visible incident, which means in
  practice it will not be done, which means the key's effective lifetime is "forever".

**Other secrets, for completeness**: Postgres, RabbitMQ, MinIO and Keycloak admin credentials, all
from the same Secret; `GRAFANA_ADMIN_PASSWORD`, which now guards a **publicly reachable** admin UI
(`grafana.reserve-me.ru`, a deliberate call recorded in `gateway.yaml`); and
`AGO_PLATFORM_PACKAGES_TOKEN`, a classic GitHub PAT scoped to `read:packages`.

**Added by `8-07` (2026-08-26): `KEYCLOAK_DEMO_PROVISIONER_SECRET`.** The client secret of the
`ago-demo-provisioner` confidential client, held by `Ago.Chat.Api` and `Ago.Chat.Worker` — the first
credential in this system that lets a web-facing process *write* to the identity provider, which is the
class `13-01` named and had until now avoided. `adr/0058` argues why it is worth holding and how it is
narrowed: its service account carries exactly one role, `realm-management:manage-users` on the
`ago-chat` realm, so it can neither read the realm's configuration nor reach another realm, and it is
deliberately not the `master`-realm admin `apply-realm-settings.sh` uses from the node.

Two properties make it easier to rotate than the signing key above, and this item should say so when it
lands: it is a Keycloak client secret, so rotating it is a change in one place plus a redeploy, and
**nothing holds a token signed by it** — the access tokens it exchanges for last minutes and are cached
in-process, so a rotation costs at most one failed mint. It is the opposite of `AUTH_JWT_SIGNING_KEY` in
exactly the way that matters here. `Ago.Chat.Webhooks` deliberately does not receive it.

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
JwtTokenService.cs` — the seven-day visitor token and the single symmetric key. `adr/0022` — operator
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
  while looking at this~~ — **answered twice, and the second answer is the live one. `17-06`/`adr/0034`
  (2026-08-25) kept it at thirty**, because it was a product promise (how long a returning visitor
  still sees their own conversation) more than a security parameter — the minting endpoint is public
  and unauthenticated, so anyone who can read a token off a page can mint their own — and lowering it
  without a renewal path would only have broken returning visitors sooner. **`17-07`+`17-08`/`adr/0048`
  (2026-08-26) built that renewal path and set it to seven.** So **this item's drain window is seven
  days, not thirty**; build the multi-key acceptance so the retirement delay is configuration rather
  than a constant, which is what makes that number safe to change again.
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

- [x] The inventory exists and lists every secret named above, plus any the sweep adds.
      `docs/architecture/secrets.md`. Its own first section states the six sweeps it was built from, so
      completeness is checkable rather than asserted. **The sweeps added five entries this file did not
      name**: `KEYCLOAK_DB_PASSWORD`, the cluster-managed TLS and ACME keys, the node's OpenDKIM key,
      the backup GPG keypair (which `adr/0050` had already assigned here), and
      `Webhooks:SecretEncryptionKey` — the last of which is the open finding below.
- [x] Each has a written rotation procedure stating what breaks during it.
      `docs/runbooks/secret-rotation.md`, one section per secret, each with an explicit "what breaks
      during it". The signing key's says what a *visitor* experiences at each step, in a table, because
      that is the one where the answer is not obvious.
- [ ] ~~The visitor signing key can be rotated with overlapping validation~~ — **the mechanism is
      built and proven, the live rotation is not performed.** `adr/0067`; `VisitorSigningKeyRingTests`
      and `VisitorKeyRotationTests` in `ago-chat`. A token minted under the previous key still
      validates after the key has changed, and one signed by a key whose drain window has closed does
      not — both through a real `JwtBearer` handler, both shown failing against the code without the
      mechanism. What is *not* done is running the procedure against the demo deployment. That is
      deliberate: this item builds the mechanism, and rotating a live credential is the author's act on
      the author's schedule. Tick this when it has been done once.
- [x] A leak procedure exists in the runbook.
      The second half of `docs/runbooks/secret-rotation.md`. Three common steps, then the part that is
      specific per secret — including the one case where the mass logout is the *correct* answer, which
      `adr/0067` deliberately kept reachable.
- [x] The packages PAT's expiry is recorded **in something that fires**.
      `ago-chat/.github/workflows/credential-expiry.yml` — a scheduled workflow that fails 30 days
      before the date and after it. It fails rather than warns, because a green job with a warning in
      its log is a notification nobody receives. Its own limitation is in its header and repeated in
      the runbook: GitHub disables scheduled workflows in a repository idle for 60 days, so a dormant
      repository is a dormant reminder. Best available with no deployment and no third party; not a
      guarantee.

## What shipped, 2026-08-27

**`ago-chat`** — `adr/0067`'s mechanism. `Auth:VisitorSigningKeys` is a key *set*:
`IVisitorSigningKeyRing` / `VisitorSigningKeyRing` / `VisitorSigningKeyOptions` beside
`JwtTokenService`, which now takes the ring and can reach only the one key that signs.
`TokenValidationParameters.IssuerSigningKey` became `IssuerSigningKeyResolver`, which is the line that
makes the difference: the former is one key captured while the host starts, the latter is asked on
every token, so a retired key leaves the accepted set the moment its window closes with no restart.
The old `Auth:SigningKey` still works and means "a set of exactly one active key", so **applying this
change rotates nothing and logs nobody out**; setting both forms is a refusal to start.

**`ago-deploy`** — `KEYCLOAK_DEMO_PROVISIONER_SECRET` added to both `.env.example` files (consumed by
`base/api.yaml` and `base/worker.yaml` since `8-07`, documented in neither: the one thing sweep 2 found
that sweep 1 did not); the signing-key comment in `base/api.yaml` now names the rotation procedure; the
open finding is recorded in all three manifests that carry it.

**`ago-root`** — the inventory, the runbook, `adr/0067`, and a correction to `17-02`'s lifetime table,
which still said thirty days.

## The open finding this item did not fix

`Webhooks:SecretEncryptionKey` — the AES-256 key encrypting every tenant's webhook signing secret at
rest — has its **value committed** in `ago-deploy/k8s/base/{api,worker,webhooks}.yaml`, and `base/` is
inherited by the demo overlay. `7-03` put it there describing it as "the same throwaway local dev
value", which was true of the local loop and stopped being true once `base/` served the public
deployment.

Not fixed here, and the reason is not effort: `adr/0024` chose reversible encryption so a secret can be
shown to a tenant again, so the stored ciphertext is load-bearing, and changing the key makes every
already-registered webhook secret permanently undecryptable — silently. The fix needs a second key
setting and a re-encryption path, which is structurally what `adr/0067` just built for tokens in
flight, applied to data at rest. That is an item with a migration in it, not a manifest edit, and this
item's own Out-of-scope section is what says so ("something the present approach genuinely cannot hold
becomes its own item with that finding as its argument"). `docs/architecture/secrets.md` carries the
full write-up including what the fix looks like; `runbooks/secret-rotation.md` carries the honest
interim procedure, which is "revoke and re-register".

## Open questions

None for the work itself. ~~The thirty-day visitor-token lifetime is a real question and it belongs to
`17-06`~~ — **settled 2026-08-25 and then moved 2026-08-26**: `adr/0034` kept it at thirty and named
`17-07` as what would let it drop to seven; `17-07`+`17-08`/`adr/0048` did exactly that, so **it is
seven days now**. This item still makes rotation possible at whatever that lifetime is — and the fact
that the number moved once already is the argument for building the retirement delay as configuration
rather than reading a constant.
