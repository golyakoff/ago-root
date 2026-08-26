# Runbook: changing the Keycloak realm on the live deployment

Things you do to the running realm a few times a year, forget entirely in between, and then get
wrong in the same three ways. Everything here has been executed against the demo deployment; where
something has not, it says so.

`adr/0022` (Keycloak issues operator tokens), `adr/0032` (the platform-owner role), `adr/0034` (realm
login security and token lifetimes), `adr/0036` (persistent user store, and the import behaviour this
whole file is shaped by).

## The rule that shapes everything below

**`--import-realm` is skip-if-exists.** Once the realm exists, `keycloak-realm-import.json` is never
read again — not on restart, not on redeploy, not when the file changes. So **anything added to that
file after the realm was first created does not exist on the live deployment**, and never will until
somebody applies it by hand.

This is not a corner case; it is the normal case, and it has bitten twice:

- `11-07` found that a changed `loginTheme` in the import file does nothing to a realm that already
  exists — `apply-realm-settings.sh` is what moves it.
- `8-07` declared the `ago-demo-provisioner` client in the import file, and `apply-demo-provisioner.sh`
  was written to *configure* a client the import would create. On the live realm the import had run
  long before, so the client did not exist and the script's own failure message advised the one thing
  that cannot work. Fixed 2026-08-26 so the script creates the client when it is missing.

**When you add anything to the import file, ask immediately: what applies this to a realm that already
exists?** If the answer is nothing, the feature works on a fresh cluster and silently does not work on
the deployed one — the worst of the two ways to be broken.

## Getting a `kcadm` shell against the live realm

No admin credential leaves the cluster and nothing is port-forwarded — `kcadm` runs inside the
Keycloak pod, the same shape `apply-realm-settings.sh` uses.

```bash
ssh -i ~/.ssh/ago-vps-ed25519 ago@reserve-me.ru
```

Then on the node:

```bash
set -a; . ~/ago/ago-deploy/k8s/overlays/demo/.env; set +a
POD=$(sudo k3s kubectl get pod -n ago-chat -l app=keycloak -o jsonpath='{.items[0].metadata.name}')
K() { sudo k3s kubectl exec -i -n ago-chat -c keycloak "$POD" -- /opt/keycloak/bin/kcadm.sh "$@"; }
K config credentials --server http://localhost:8080 --realm master \
  --user "$KEYCLOAK_ADMIN_USER" --password "$KEYCLOAK_ADMIN_PASSWORD"
```

The variable is `KEYCLOAK_ADMIN_USER`, not `KEYCLOAK_ADMIN` — `apply-realm-settings.sh` reads the
second name, this file and `apply-demo-provisioner.sh` read the first, and the `.env` carries the
first. Sourcing `.env` prints one `line 47: Chat: command not found`; it is an unquoted value with a
space in it, it does not affect the variables above, and it is worth fixing the next time that file
is touched.

## Making somebody a platform owner

`adr/0032`: the platform owner is a normal realm identity distinguished by one **realm role**,
`platform-owner`, in the token's `realm_access.roles`. There is no `operators` row and no
`external_subject_id` link.

**Choose the password yourself and do not let it reach a transcript, a log, or shell history.**

```bash
read -p "username: " OWNER_USER
read -s -p "password: " OWNER_PASS; echo

K create users -r ago-chat \
  -s "username=$OWNER_USER" \
  -s enabled=true \
  -s emailVerified=true \
  -s "email=$OWNER_USER@reserve-me.ru" \
  -s "firstName=<given name>" \
  -s "lastName=<family name>"

K set-password -r ago-chat --username "$OWNER_USER" --new-password "$OWNER_PASS" --temporary=false
K add-roles  -r ago-chat --uusername "$OWNER_USER" --rolename platform-owner

unset OWNER_PASS
K get users -r ago-chat -q "username=$OWNER_USER" --fields username,enabled --format csv --noquotes
```

Then sign in at `console.reserve-me.ru` and open **`/owner`**.

### The three ways this goes wrong

**`firstName` and `lastName` are required, and the error does not say so.** Without them the login is
refused with `invalid_grant: "Account is not fully set up"` — Keycloak's User Profile rejecting an
incomplete profile, in a message that names nothing missing.

**`set-password` is temporary by default.** Without `--temporary=false` Keycloak sets a
required action to change it at first login, and `ago-console` has no screen for that flow — you land
on a wall rather than on a page.

**The operator screens will be empty, and that is correct.** Granting the role alone gives the
identity no tenant: no `OperatorId`, no `site_id`, `OperatorIdentityClaimsTransformation` resolves
nothing for it and is not consulted. `adr/0032` grants exactly one thing, `/owner` and the read-only
API behind it. If the operator views look broken for this account, they are not — you are logged in
as somebody who is not an operator.

**If you want this account to have a tenant too, register one the ordinary way** (`12-05`). Sign in,
go to `/onboarding`, fill in a site display name and an embed origin. Nothing does this for you and
nothing refuses it any more; afterwards the same login shows both the operator queue and "Platform
sites", because the two are separate axes (`adr/0063`). Note that it cannot be undone — this product
has no un-register path — so do it because you want to run a tenant on your own deployment, not to
make an empty screen look less empty.

### If the `/owner` link is missing from the navigation

`12-03`: the console **asks the server** whether to draw that link and never inspects the token
itself, so an absent link means the server said no. Check the role rather than the browser:

```bash
K get-roles -r ago-chat --uusername "$OWNER_USER" --effective --fields name --format csv --noquotes
```

Hiding the link is not the gate — `RequirePlatformOwner` decides on every call — so opening `/owner`
directly is a fair test of whether the role took.

### Taking it away

```bash
K remove-roles -r ago-chat --uusername "$OWNER_USER" --rolename platform-owner
```

Effective on the identity's next token, not immediately: `adr/0034` sets the access-token lifetime,
and a token already issued keeps its claims until it expires. If it has to be immediate, disable the
user (`-s enabled=false`) instead and re-enable afterwards.

## Applying a realm setting the import file already declares

Two scripts exist and neither is optional on a running realm:

```bash
cd ~/ago/ago-deploy/k8s
set -a; . ./overlays/demo/.env; set +a
./apply-realm-settings.sh        # login security, token lifetimes, SMTP, loginTheme (11-07, 17-06)
KEYCLOAK_DEMO_PROVISIONER_SECRET=... ./apply-demo-provisioner.sh   # 8-07's client, its secret, its one role
```

`apply-demo-provisioner.sh` reads the secret from the environment; on the node it is already in
`.env`, so sourcing that file is enough.

A note from fixing it: **kcadm's `-s key=value` could not carry the client's `description`** from the
import file. It answers a bare `unknown_error` on the whole create, and the identical create without
that one flag succeeds. If a `create` fails with nothing but `unknown_error`, drop the longest text
field first.

## What this file does not cover

- **Rotating the admin credential**, or any credential — `17-03` owns the inventory and the procedure,
  and neither exists yet.
- **Bulk user operations.** Everything here is one identity at a time, deliberately: there is no
  operation in this system that should touch many realm users at once except `8-07`'s expiry sweep,
  which does it through the service account rather than through this file.
- **A fresh realm.** That is `public-deploy.md`, where the import file does apply and none of the
  skip-if-exists reasoning above is needed.
