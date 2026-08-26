# Runbook: rotating a secret, and what to do when one leaks

`17-03`, 2026-08-27. The inventory — what exists, where it lives, who reads it — is
`docs/architecture/secrets.md`. This file is the other half: how each one is changed, **what breaks
while it is being changed**, and what to do when one is known to be exposed.

Nothing in this file has been performed against the live deployment. It is written to be followed, not
as a record of having been followed, and every step that has not been exercised says so.

**No value ever goes in a repository, a commit message, an issue, or a chat transcript that will be
pasted into one.** Generate with `openssl rand -base64 32` (key-shaped) or `openssl rand -base64 24`
(password-shaped) and paste the result straight into `.env` on the deploying machine.

---

## The visitor signing key — the one that used to be an incident

**Class: draining.** `AUTH_JWT_SIGNING_KEY` / `Auth:SigningKey` / `Auth:VisitorSigningKeys`.

Before `17-03` this was the most expensive secret in the system to change: one key signed and the
same one key validated, so the instant it changed every visitor on every site lost their session and
their conversation continuity at once. `adr/0067` made it rotatable. What follows is the procedure
that decision exists to make possible.

### What a visitor experiences, step by step

Nothing, at any step, provided the drain window is respected. That is the claim, and here is where it
comes from:

| Moment | A visitor holding an old token | A visitor arriving fresh |
|---|---|---|
| Before the rollout | Works | Works |
| Mid-rollout, pods on two different key sets | Works — the new set still contains the old key | Works, signed by whichever pod answered |
| After the rollout | Works | Works, signed by the new key |
| Within the drain window | Works, and renewal (`adr/0048`) silently re-issues under the new key at the visitor's next use | Works |
| After the drain window | Works **if** they used the site at least once during the window; otherwise their token is refused and the widget mints a new identity, clearing the conversation with a note in the panel | Works |

That last row is the only visitor-visible cost, and it lands on exactly the people who did not visit
the site for a whole week — the same population that loses a session to normal expiry anyway, since
the drain window equals the token lifetime.

### What the operator watches

- The API pods **come up**. Three of the four ways to get this edit wrong are startup failures by
  design (`adr/0067`): two active keys, no active key, or both configuration forms set. A rollout that
  stalls is the mechanism working.
- `401` rate on `/hubs/visitor` negotiate and on the attachment routes. It should not move. If it
  jumps at the moment of the rollout, the old key is not in the validation set — roll back the
  Deployment, which is the whole of the recovery, because nothing was destroyed.
- On the day the window closes, a *small* rise in visitor-session mints is expected and correct: those
  are the visitors who were away for the whole window.

### The rotation

The first rotation also moves this deployment off the single-key setting. That is one edit, not two,
and it is why the two forms may not both be set.

1. Generate the new key on the deploying machine:

   ```bash
   openssl rand -base64 32
   ```

2. In `k8s/overlays/demo/.env`, keep the current `AUTH_JWT_SIGNING_KEY` value and add the new one
   beside it:

   ```
   AUTH_JWT_SIGNING_KEY_PREVIOUS=<the value AUTH_JWT_SIGNING_KEY has right now>
   AUTH_JWT_SIGNING_KEY=<the freshly generated value>
   ```

3. In `k8s/base/api.yaml`, replace the single `Auth__SigningKey` variable with the key set. `RetiredAt`
   is the instant of the rotation, in UTC, ISO-8601 with an explicit offset (`date -u +%Y-%m-%dT%H:%M:%SZ`):

   ```yaml
   - name: Auth__VisitorSigningKeys__Keys__0__Id
     value: "2026-08"                     # any stable non-secret label; a rotation date reads best
   - name: Auth__VisitorSigningKeys__Keys__0__Value
     value: "$(AUTH_JWT_SIGNING_KEY_PREVIOUS)"
   - name: Auth__VisitorSigningKeys__Keys__0__RetiredAt
     value: "2026-08-27T09:00:00Z"
   - name: Auth__VisitorSigningKeys__Keys__1__Id
     value: "2026-09"
   - name: Auth__VisitorSigningKeys__Keys__1__Value
     value: "$(AUTH_JWT_SIGNING_KEY)"
   ```

   **Remove `Auth__SigningKey` in the same edit.** Leaving it produces a host that refuses to start,
   which is deliberate: a half-finished edit must not look applied while the pod signs with the other
   key.

   `Auth__VisitorSigningKeys__RetirementDelay` is optional and defaults to the visitor token's own
   lifetime (seven days, `adr/0048`). Set it only to make the window *longer*; shorter than the token
   lifetime is refused at startup.

4. Apply and roll:

   ```bash
   cd ~/ago/ago-deploy
   kubectl apply -k k8s/overlays/demo
   kubectl rollout status deployment/ago-chat-api -n ago-chat
   ```

   Only `Ago.Chat.Api` mints or validates visitor tokens, so only it needs the key — but the Secret is
   shared, and `kubectl apply -k` rolls whatever the new Secret hash touches. Let it.

5. Confirm the new key is the one signing, without reading any key material: mint a token against the
   public endpoint and decode its header. `kid` should be the new id.

6. **After the drain window has closed** (seven days by default), delete the retired entry from
   `api.yaml` and `AUTH_JWT_SIGNING_KEY_PREVIOUS` from `.env`, and apply again. This step is
   housekeeping and not a deadline: the key stopped being accepted on its own, on the date, with no
   deploy. That is the property that makes this procedure finishable rather than one that ends with an
   old key quietly still valid.

### Rolling back

Roll the Deployment back. There is nothing to undo — no data was re-written, and the previous key is
still in the previous manifest.

---

## Postgres — `POSTGRES_PASSWORD`

**Class: coordinated.** It is not only a Secret value; the role's password inside Postgres must change
too, and the two must agree.

**What breaks during it:** between changing the role's password and rolling the three hosts, every one
of them fails its readiness probe and the API's endpoints leave the Service — the site is down for the
length of the rollout. There is no version of this that is invisible on a single-node deployment with
one database.

1. `ALTER ROLE ago WITH PASSWORD '<new>';` inside the Postgres pod.
2. Set `POSTGRES_PASSWORD` in `.env` to the same value.
3. `kubectl apply -k k8s/overlays/demo` and wait for the three host rollouts.
4. Re-run `k8s/smoke.sh`.

`POSTGRES_PASSWORD` is *also* what `postgres.yaml` seeds the role from at first boot, so on a
from-scratch node steps 1 and 2 collapse into one. On a live node they do not, and doing only step 2
gives a database that still wants the old password and four pods that only know the new one.

`KEYCLOAK_DB_PASSWORD` is the same procedure against the `keycloak` role, rolling Keycloak instead —
and the same caveat with more teeth, because `adr/0050` notes that `pg_dumpall --globals-only` carries
role password hashes: a backup taken before the rotation restores the *old* password, so a restore
after a rotation needs the `.env` of that moment. That is why `adr/0050` backs the `.env` up.

## RabbitMQ — `RABBITMQ_PASSWORD`

**Class: restart.** RabbitMQ's Deployment reads user and password from the Secret at start, so
changing the value and applying re-seeds the user and rolls the consumers.

**What breaks during it:** publication and consumption pause for the rollout. Nothing is lost — the
outbox is the durable record (`adr/0005`) and consumers are idempotent (`adr/0017`) — but a live
visitor's message may take the length of the rollout to reach an operator's screen. Fan-out
deliveries in flight are dropped and not replayed (`adr/0020`); the client re-reads history on
reconnect, so a visitor sees a pause, not a gap.

## MinIO — `MINIO_ROOT_PASSWORD`

**Class: restart.** Same shape as RabbitMQ.

**What breaks during it:** presigned URLs already handed to a browser are signed with the old
credential and stop working, so an upload or download in flight fails and must be retried. The bytes
already stored are untouched. `backup.sh` reads this value from the Secret at run time, so it needs
nothing; a backup started during the rollout may fail and will succeed on the next run.

## Grafana — `GRAFANA_ADMIN_PASSWORD`

**Class: restart.** Change it, apply, roll `grafana`.

**What breaks during it:** a logged-in session survives; the next login needs the new value. Note the
same trap Keycloak has — Grafana persists its admin user, so once the deployment has booted once, this
variable sets the password only if Grafana's own database does not already have one. Changing it live
is a `grafana-cli admin reset-admin-password` inside the pod, and the `.env` value should then be
updated to match so a rebuilt node agrees with the running one.

## Keycloak's `master`-realm admin — `KEYCLOAK_ADMIN_PASSWORD`

**Not a deployment setting since `15-01`/`adr/0036`.** Keycloak has a database that remembers the
account, so editing this value and re-applying changes the Secret and not the admin. Rotate the actual
password through `runbooks/realm-operations.md`, then update `.env` to match so that a rebuilt node
seeds the same value.

**What breaks during it:** nothing running. The three `apply-*.sh` scripts read this value, so they
fail until `.env` agrees with the realm.

## The demo-provisioner client secret — `KEYCLOAK_DEMO_PROVISIONER_SECRET`

**Class: coordinated**, and it is the easiest secret in this system to rotate — deliberately the
opposite of the signing key, in exactly the way that matters here. It is a Keycloak client secret,
so it changes in one place plus a redeploy, and **nothing holds a token signed by it**: the access
tokens it exchanges for last minutes and are cached in-process, so a rotation costs at most one failed
mint.

1. Generate a value, set `KEYCLOAK_DEMO_PROVISIONER_SECRET` in `.env`.
2. `kubectl apply -k k8s/overlays/demo` — this updates the Secret.
3. `KEYCLOAK_DEMO_PROVISIONER_SECRET=<the same value> k8s/apply-demo-provisioner.sh` — this updates
   the client's own record inside Keycloak, and grants the service account its single role.
4. `kubectl rollout restart deployment/ago-chat-api deployment/ago-chat-worker -n ago-chat`.

**Order matters, and steps 2 and 3 may be done in either order provided step 4 follows both.** Between
step 3 and step 4 the running pods hold the old secret: a demo-tenant mint fails with an authentication
error against Keycloak, and `DemoTenantExpiryJob` cannot delete an expired tenant until the restart.
Both are retried, so the cost is a window of failures rather than damage.

## The packages PAT — `AGO_PLATFORM_PACKAGES_TOKEN`

**Class: coordinated.** One value, two repositories.

**What breaks during it:** nothing, if the order is right. Revoking first breaks the CI of whichever
repository is pushed to next.

1. Create a new classic PAT, **`read:packages` only**, and note the new expiry.
2. Set it as a repository secret in **`ago-chat`** and in **`ago-calendar`**.
3. Re-run one workflow in each and confirm the restore step passes.
4. **Only then** revoke the old PAT.
5. Update the expiry date in `ago-chat/.github/workflows/credential-expiry.yml` and in
   `docs/architecture/secrets.md`.

Step 5 is the one that gets skipped, which is why the reminder that fires lives in the workflow rather
than in a document. That reminder's own limitation: GitHub disables scheduled workflows in a repository
that has had no activity for 60 days, so a dormant `ago-chat` is a dormant reminder. It is the best
available mechanism that needs no deployment and no third party; it is not a guarantee.

Before doing any of this, read the note in `secrets.md` about whether this credential needs to exist at
all. Granting each `Ago.Platform.*` package Actions-read access to the consuming repositories would let
their built-in `GITHUB_TOKEN` do the restore and remove this entry from the inventory rather than
rotating it forever. That experiment is cheaper than this procedure.

## The node's SSH key

**Class: coordinated, and the one where a mistake locks everyone out.**

Password authentication and root login are disabled (`17-05`), so this key is the only way in. Add the
new public key to `~/.ssh/authorized_keys` **first**, open a *second* session with the new key while
the first is still connected, confirm it works, and only then remove the old entry. Never edit
`authorized_keys` from a session you would lose.

`k8s/backup/backup-pull.sh` reads the key path from `AGO_SSH_KEY`, defaulting to
`~/.ssh/ago-vps-ed25519`; keep the new key at the same path or set that variable.

## The backup GPG keypair

**Class: draining, with no automatic expiry — the archive splits at a date.**

Rotating does **not** re-encrypt existing artifacts. Everything taken before the rotation is readable
only by the old private key, everything after only by the new one. So both must be kept for as long as
the older half is wanted, which is the 30-day retention `adr/0050` sets.

1. Generate the new keypair on the machine that holds the backups, in its own `GNUPGHOME`. **Never on
   the node.**
2. Copy the new *public* key to the node, replacing the recipient file `backup.sh` reads.
3. Run `backup.sh` once and confirm the artifact decrypts with the new private key.
4. Keep the old private key until the last artifact encrypted under it has aged out of retention. Only
   then destroy it, and understand that doing so makes those artifacts permanently unreadable.

**Lose the private key and every artifact ever taken is unreadable. There is no escrow and no
recovery.** An offline copy of the identity file is the mitigation.

## The OpenDKIM signing key

**Class: coordinated.** The private key on the node and the public key in DNS must change together.

**What breaks during it:** mail signed with a key whose public half is not yet published fails DKIM,
which for a domain with a DMARC policy means the verification mail a self-registering visitor is
waiting for goes to spam or nowhere. Publish the new DNS record first, wait for propagation, then
switch the selector.

`adr/0040`'s amendment records a real incident here that is worth reading before touching this: a
registrar served the zone from sixteen authoritative IPs of which only four carried the record, which
fails DKIM for roughly three quarters of the internet while every casual check looks fine. Verify with
`opendkim-testkey -d <domain> -s <selector> -vvv`, and if it disagrees with `dig`, believe neither
until you have queried the authoritative nameservers individually.

## The webhook secret-encryption key — `Webhooks:SecretEncryptionKey`

**Class: breaking, and there is no non-breaking version of it today.** See the open finding in
`secrets.md` for why the value is where it is and what the real fix looks like.

Changing this key makes every already-stored webhook secret permanently undecryptable. Nothing warns;
the next dispatch simply signs with garbage, or the read fails. The honest interim procedure is
therefore:

1. Tell every tenant with a registered webhook endpoint that they must re-register it.
2. Change the value and roll all three hosts.
3. Have each tenant re-register, taking the newly shown secret.

Check how many endpoints this would affect before deciding
(`select count(*) from webhook_endpoints`) — this procedure is tolerable only while the answer is
small and every row belongs to a demo tenant. Once one belongs to a real tenant, do not follow it; cut
the item described in `secrets.md` instead.

---

# When a secret is known to be exposed

One page, per secret, given everything above. The first three steps are the same every time:

1. **Write down when and how it was exposed**, before doing anything. A rotation destroys the evidence
   of which value was live.
2. **Decide whether the exposure is bounded.** A value in a log this project controls, a value in a
   terminal transcript, and a value pushed to a public repository are three different situations. Only
   the third is unbounded, and only the third makes speed matter more than order.
3. **Rotate using the procedure above.** A leak does not license skipping a procedure; it licenses
   accepting its cost immediately instead of scheduling it.

Then, per secret, the part that is specific:

**The visitor signing key.** This is the one case where the *blunt* instrument is correct, and
`adr/0067` deliberately left it available. Anyone holding a leaked key can mint a valid token for any
visitor of any site, and the ordinary rotation keeps accepting the leaked key for the whole drain
window. So for a leak, do **not** use today's date as `RetiredAt` — set it far enough in the past that
`RetiredAt + RetirementDelay` is already behind you. The old key is then refused immediately.

That is the mass logout: every visitor on every site loses their conversation continuity at that
instant, and the widget mints a new identity with a note in the panel (`adr/0048`). Take it knowingly;
it is the correct trade for a leaked signing key and the wrong trade for anything else. Note what a
leak of this key does *not* let anyone do: it grants no operator access, no cross-tenant read, and no
ability to mint a session anyone could not already mint through the public endpoint. What it grants is
impersonation of a *specific* visitor, i.e. their transcript.

**Postgres, RabbitMQ, MinIO, the Keycloak DB role.** These are only reachable from inside the cluster
(`17-05`'s NetworkPolicies) and no Service is published. So a leak of one of these matters if and only
if something else is already wrong — treat it as evidence of a broader compromise and check that
first. Rotate in the order the procedures give, and take the outage.

**The demo-provisioner client secret.** Rotate immediately; it is the cheapest rotation here. Then
check the realm for users the provisioner created that no `demo_tenants` row accounts for — that is
the only thing this credential can do, and it is a bounded, checkable list.

**The packages PAT.** Revoke it at GitHub *first*, in this one case, before creating the replacement.
Its scope is `read:packages` on public packages, so revoking costs a red CI run and nothing else; the
ordering rule above exists to avoid an inconvenience, and an inconvenience is not worth a live
credential.

**The node SSH key.** Assume the node is compromised, not just the key. Rotate the key, then rotate
every credential the node holds — because it holds them all: the Secret's contents are readable to
anyone with `kubectl` there. This is the one entry on this page whose real answer is "rebuild the
node", and `runbooks/public-deploy.md` plus `backup-and-restore.md` are what make that possible.

**The backup private key.** Every artifact ever taken is now readable by whoever has it, and no
rotation changes that — the ciphertext is already wherever it is. Rotate so that *future* artifacts are
safe, and treat the contents of the exposed archives as disclosed: `personal-data.md` is the inventory
of what that means, and `runbooks/personal-data-incident.md` is the procedure for the disclosure
itself, which is a separate obligation from this one.

**The webhook secret-encryption key.** It is already in a public repository, by accident, and has been
since `7-03`. That is the open finding in `secrets.md` rather than an incident to run this page
against — the exposure is known, recorded and bounded by the fact that it is useless without the
database. Treat *that* boundary as the thing to protect until the fix lands.
