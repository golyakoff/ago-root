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
./apply-android-client.sh        # 26-11's ago-android client and its audience mapper - no secret needed
```

`apply-demo-provisioner.sh` reads the secret from the environment; on the node it is already in
`.env`, so sourcing that file is enough. `apply-android-client.sh` needs nothing from the environment
beyond the admin credential every script here already reads - the client it creates is public and
holds no secret of its own.

A note from fixing it: **kcadm's `-s key=value` could not carry the client's `description`** from the
import file. It answers a bare `unknown_error` on the whole create, and the identical create without
that one flag succeeds. If a `create` fails with nothing but `unknown_error`, drop the longest text
field first.

## Proving the `ago-android` client works - Authorization Code + PKCE, no app (`26-11`)

The whole point of `26-11`'s client is that a native app can get a token `Ago.Chat.Api` already
accepts, with zero changes to `ago-chat`. That is provable by hand, with nothing but a browser and
`curl`, before any Kotlin exists.

```bash
# 1. A PKCE verifier and its S256 challenge.
CODE_VERIFIER=$(openssl rand -base64 96 | tr -d '=+/\n' | cut -c1-64)
CODE_CHALLENGE=$(printf '%s' "$CODE_VERIFIER" | openssl dgst -sha256 -binary | openssl base64 | tr -d '=' | tr '/+' '_-')

# 2. Open in a browser, log in as any real user:
https://<node-ip>/realms/ago-chat/protocol/openid-connect/auth?client_id=ago-android&response_type=code&scope=openid&redirect_uri=ago-android%3A%2F%2Fcallback&code_challenge=$CODE_CHALLENGE&code_challenge_method=S256

# 3. The browser cannot open `ago-android://callback` and will fail to navigate there - that failure
#    is expected, not a bug. Capture the `code=` query parameter from the address it tried to load
#    (or drive the whole exchange from curl instead - fetch the login page's own form `action` URL,
#    POST `username`/`password`/`credentialId=` to it with a cookie jar, and read the `code=` value
#    straight off the `Location:` header of the 302 response, which never needs a browser at all).

# 4. Exchange the code for a token:
curl -s https://<node-ip>/realms/ago-chat/protocol/openid-connect/token \
  -d grant_type=authorization_code -d client_id=ago-android \
  -d code="$AUTH_CODE" -d redirect_uri=ago-android://callback \
  -d code_verifier="$CODE_VERIFIER"

# 5. Decode the access token's `aud` claim (any JWT-aware tool; `node -e` works with no dependency) -
#    it must contain exactly "ago-console", the value CompositionRoot.cs validates.

# 6. Confirm Ago.Chat.Api accepts it - 200 or 403 both mean the token was validated, 401 means
#    something is wrong:
curl -si https://<the chat-api hostname>/api/v1/operators/me -H "Authorization: Bearer $ACCESS_TOKEN"
```

**A note from doing this the first time.** The obvious hostname for the API is not always the real
one - this deployment's own Gateway names it distinctly from the tenant-facing domains (`chat-api.`
rather than `api.` or the console's own host); read the live `HTTPRoute` objects
(`kubectl get httproute -n ago-chat -o json`, grep for `hostnames`) rather than guess from a pattern
that happens to work for a sibling service.

**If testing from a machine other than the node itself, and it also runs a Claude Code sandbox with
its own outbound proxy**: a proxy can silently intercept an HTTPS `CONNECT` to a real domain and
return a misleading `200 Connection established` response body instead of the actual TLS handshake -
running the same `curl` commands over SSH, on the node itself, avoids the ambiguity entirely.

## What this file does not cover

- **Rotating the admin credential**, or any credential — `17-03` owns the inventory and the procedure,
  and neither exists yet.
- **Bulk user operations.** Everything here is one identity at a time, deliberately: there is no
  operation in this system that should touch many realm users at once except `8-07`'s expiry sweep,
  which does it through the service account rather than through this file.
- **A fresh realm.** That is `public-deploy.md`, where the import file does apply and none of the
  skip-if-exists reasoning above is needed.
