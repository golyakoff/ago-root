# Runbook: local development

> **Status: the compose loop below is verified** (backlog item `0-03-local-infrastructure.md` - every
> command in this section was actually run, not just written). Migrations and seeding are verified
> too, as of `1-04`/`1-05` - the schema exists and the demo tenant seeds cleanly.

## Prerequisites

- .NET 10 SDK
- Docker Desktop (with Kubernetes enabled — see `k8s-local.md`)
- Node 24+ (frontend, from Stage 5)

## The fast loop: infrastructure in Docker, app from the IDE

Paths below assume you are in `ago-root`; the junctions (`deploy/`, `chat/`) make the siblings
reachable from here (`workspace.md`).

```
cp deploy/docker/.env.example deploy/docker/.env   # once; edit if you want different local creds
docker compose -f deploy/docker/docker-compose.yml up -d
export $(grep -v '^#' deploy/docker/.env | xargs) && AGO_CHAT_CONNECTION_STRING="Host=localhost;Port=5432;Database=$POSTGRES_DB;Username=$POSTGRES_USER;Password=$POSTGRES_PASSWORD" \
  dotnet ef database update -p ../ago-chat/src/Ago.Chat.Infrastructure.Postgres
bash deploy/seed/create-demo-tenant.sh   # after .env is sourced, per 1-05
ASPNETCORE_ENVIRONMENT=Development dotnet run --project ../ago-chat/src/Ago.Chat.Api
dotnet run --project ../ago-chat/src/Ago.Chat.Worker
dotnet run --project ../ago-chat/src/Ago.Chat.Webhooks
```

**`15-01`: an existing `deploy/docker/.env` needs one new key**, `KEYCLOAK_DB_PASSWORD` — copy it from
the updated `.env.example`. Keycloak no longer keeps its users in an embedded H2 file inside the
container; it now has its own `keycloak` database and its own role in the same Postgres container as
`ago_chat` (`adr/0036`), created before Keycloak starts by a one-shot `keycloak-db-init` service.
Without the key, `docker compose up` refuses to start with a missing-variable error rather than
starting something half-configured. What this buys locally: an account created at runtime (through
Keycloak's registration form, or the admin API) now survives `docker compose restart` **and** a full
container recreate — verified live on both. What it costs: editing
`deploy/k8s/base/keycloak-realm-import.json` no longer reaches a realm that already exists, because the
realm now survives too. See "Changing the realm after it exists" below.

`AGO_CHAT_CONNECTION_STRING` (already exported above) must stay set for `Ago.Chat.Api` too -
`ChatModule.ConfigureServices` (`1-06`) reads it the same way the migration step did. With
`ASPNETCORE_ENVIRONMENT=Development`, the API additionally serves `/dev-harness.html` (a plain
HTML+SignalR page, not the real widget/console - `1-06`); it never exists outside Development.
**Shipped in `5-01`**: every call in the harness now goes through `?api=http://host:port` (default
empty - same-origin, unchanged from before) instead of a root-relative path, so the page can be
served from a *second* static server to prove per-site CORS for real - `http://host:8095/dev-harness?api=http://localhost:5009`
against a seeded origin completes the handshake; an unseeded origin gets a real browser-enforced
`blocked by CORS policy` rejection. Same-origin usage below is unaffected.
**`POST /dev/operator-session` no longer exists (`5-05`)** - see "Getting a working operator session
locally" below for its replacement. Verified against a real running instance: a visitor session
(`POST /api/v1/visitor-sessions`), both hubs' JWT auth, `JoinAsync`/`JoinConversationAsync` against
the seeded demo tenant, a message's own sender receiving it back over the SignalR group, and live
cross-tab delivery (the *other* party's tab receiving a reply, in both directions, two separate
tabs) confirmed twice by hand. That second round of manual testing found a real bug, not a tooling
artifact: SignalR scopes `Clients.Group(...)` per hub *type*, so `VisitorHub` and `OperatorHub` never
shared a group even under the same name - fixed by having each hub also broadcast through the other's
`IHubContext<THub>` (`docs/backlog/1-06-api-realtime-and-wiring.md` has the detail).

### Changing the realm after it exists

**Since `15-01`/`adr/0036`.** Keycloak's realm lives in Postgres now, so it survives a restart, and
`--import-realm` picks its strategy from what it finds. Read straight off Keycloak's own startup log:

```
empty database:       KC-SERVICES0030: Full model import requested. Strategy: OVERWRITE_EXISTING
                      Realm 'ago-chat' imported
realm already there:  KC-SERVICES0030: Full model import requested. Strategy: IGNORE_EXISTING
                      Realm 'ago-chat' already exists. Import skipped
```

`Import skipped` skips the whole file — realm settings, clients, roles, users, all of it. Editing
`deploy/k8s/base/keycloak-realm-import.json` and restarting does nothing at all on a realm that
already exists. It used to appear to work only because the store was being destroyed on every boot.

- **Realm-level settings** (`adr/0034`'s brute-force thresholds, password policy, OTP parameters, the
  four token/session lifetimes; `registrationAllowed`, `verifyEmail`, `sslRequired`) — edit the JSON,
  then:

  ```bash
  cd deploy && k8s/apply-realm-settings.sh compose   # or: k8s/apply-realm-settings.sh   (kubectl context)
  ```

  It PUTs the realm-level fields of the mounted file onto the live realm and leaves users and clients
  alone. Verified live on both targets with a runtime-created user present throughout: the settings
  changed, the user stayed, and the user could still get a token afterwards.
- **A client, realm role, group or user** — not covered by that script, and not covered by a restart
  either. Do it with a `kcadm.sh`/Admin API call, in the same change that edits the JSON, so a fresh
  install and a running one end up the same.
- **Never `kc.sh import --override true`.** It applies the whole file by *replacing the realm*, which
  deletes every self-registered account with it.
- **Starting over locally is still cheap**, and is the honest shortcut when the local realm has
  nothing worth keeping: `docker compose -f deploy/docker/docker-compose.yml down -v` (or deleting the
  `postgres-data` PVC in the cluster) drops both databases, and the next boot is a first boot again.
  Never on the demo deployment.

### Getting a working operator session locally

**Shipped in `5-05`** (`adr/0022`): the API now validates a real Keycloak-issued token for
`/hubs/operator`, so `dev-harness.html`'s Operator pane takes a pasted token instead of minting one
itself. `deploy/seed/create-demo-tenant.sh` links the seeded demo operator to the demo-operator user
`deploy/keycloak/ago-chat-realm.json` seeds into Keycloak by a fixed id - get a token for it with the
direct (password) grant against Keycloak's own token endpoint, matching whichever hostname the
running `Ago.Chat.Api`'s own `Auth:Keycloak:Authority` uses (issuer validation is an exact string
match - `127.0.0.1` and `localhost` are different issuers to it even though they reach the same
container):

```
curl -s -X POST http://127.0.0.1:8081/realms/ago-chat/protocol/openid-connect/token \
  -d "grant_type=password&client_id=ago-console&username=demo-operator&password=demo-operator-password" \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
```

Paste the result into `dev-harness.html`'s Operator token field and Connect. This is not the flow the
real console uses (`5-06`'s Authorization Code + PKCE, a browser redirect) - it is the pragmatic
equivalent for a page that pastes a token in rather than driving a redirect itself, the same
"password grant for a throwaway local test client" shape this runbook's own integration tests use
against a real, disposable Keycloak.

**`5-08`**: a second seeded operator, `demo-admin`, holds the `"Admin"` role (`site:configure`,
`site:manage_operators`, `attachment:delete`) alongside `"Operator"` - `demo-operator` still holds
only `"Operator"`. Signing into the real console (below) as each in turn is how the admin views and
the attachment-delete action get manually verified: `demo-admin` sees every conversation for the site
and can delete an attachment, `demo-operator` sees only its own assigned conversations and gets a 403
attempting the same delete. Same direct-grant shape as above, different credentials:

```
curl -s -X POST http://127.0.0.1:8081/realms/ago-chat/protocol/openid-connect/token \
  -d "grant_type=password&client_id=ago-console&username=demo-admin&password=demo-admin-password" \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
```

### Completing self-registration locally (`10-01`/`10-02`)

**Shipped in `10-01`** (`adr/0028`): the realm now allows registration
(`registrationAllowed: true`) and requires email verification before an account is usable
(`verifyEmail: true`) - the same fields `5-05`'s own `VERIFY_PROFILE` gotcha above already forces
onto every seeded user (`email`/`firstName`/`lastName`) are what Keycloak's own hosted registration
form collects by default, so no extra realm config was needed to avoid that gotcha a second time at
registration.

The real flow a browser drives: open Keycloak's hosted registration page directly (the same
`client_id`/`redirect_uri` shape `5-06`'s console login already redirects through) -

```
http://127.0.0.1:8081/realms/ago-chat/protocol/openid-connect/registrations?client_id=ago-console&response_type=code&redirect_uri=http://localhost:5173/callback&scope=openid
```

- fill in the form, and Keycloak sends a verification email through whatever SMTP config the realm
has. **There is none, anywhere in this project** - local Keycloak has no SMTP configured at all, and
attempting this flow fails silently server-side (`SEND_VERIFY_EMAIL_ERROR ... error="email_send_failed"`
in Keycloak's own log, found live, `8-05`/`5-13`'s own investigation while checking the public
deployment's mail-related exposure) rather than the "logs the email to its own console instead" this
runbook previously claimed - that claim was never actually true, corrected here. The verification link
is what actually lifts the "Verify Email" required action; without it, this exact browser flow cannot
complete, and there is currently no local workaround other than the admin-API shortcut below. Adding a
mock-SMTP relay (e.g. MailHog) to the local compose stack is real work — **now owned, as of 2026-08-25,
by `backlog/10-05-transactional-email-delivery.md`**, which covers both the local relay and a real
sending provider for the public deployment, where the same gap means a real visitor cannot finish
registering at all. Until it lands, the admin-API shortcut below stays the only way past this gate.

For testing `10-02`/`10-03` without driving a real browser + email flow every time, mint an
equivalent token directly against Keycloak's admin API instead - the same shape
`OperatorOidcFixture.GetWrongIssuerAccessTokenAsync` already uses in the automated test suite, run
by hand against the local compose Keycloak. Requires `KEYCLOAK_ADMIN`/`KEYCLOAK_ADMIN_PASSWORD` from
`docker/.env`:

```
ADMIN_TOKEN=$(curl -s -X POST http://127.0.0.1:8081/realms/master/protocol/openid-connect/token \
  -d "grant_type=password&client_id=admin-cli&username=$KEYCLOAK_ADMIN&password=$KEYCLOAK_ADMIN_PASSWORD" \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')

curl -s -X POST http://127.0.0.1:8081/admin/realms/ago-chat/users \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d '{"username":"local-self-register","email":"local-self-register@example.test","firstName":"Local","lastName":"SelfRegister","enabled":true,"emailVerified":true,"credentials":[{"type":"password","value":"local-self-register-password","temporary":false}]}'

curl -s -X POST http://127.0.0.1:8081/realms/ago-chat/protocol/openid-connect/token \
  -d "grant_type=password&client_id=ago-console&username=local-self-register&password=local-self-register-password" \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
```

`"emailVerified":true` on the admin-created user sidesteps the "Verify Email" required action the
same way the seeded demo users already do - the point of this shortcut is testing `10-02`'s bootstrap
endpoint against a real, signature-valid Keycloak token whose `sub` matches no `operators` row, not
re-proving Keycloak's own email flow every time. `POST /api/v1/sites` (`10-02`) with this token in the
`Authorization` header, gated by the new `RequireKeycloakIdentity` policy, is what actually creates
the `Site`/`Operator`/`Role` rows - after that call succeeds, the same token (re-fetched, so
`OperatorIdentityClaimsTransformation` resolves it fresh) works against any `RequireOperatorIdentity`
route exactly like `demo-operator`'s does above.

### "Invalid user credentials" for a password you know is right (`17-06`)

**Shipped in `17-06`** (`adr/0034`): the realm has brute-force protection now, so a locked-out account
is a real thing a local session can hit — including by mistyping a password twice inside one second,
which trips `quickLoginCheckMilliSeconds` long before the ten-failure threshold. Keycloak deliberately
returns the same `{"error":"invalid_grant","error_description":"Invalid user credentials"}` for a
locked account as for a wrong password (no user enumeration), so the symptom is a correct password
that suddenly stops working while every other account keeps working.

It clears itself after a minute (`permanentLockout: false`, so an account is never stuck). To clear it
immediately — or to check whether that is really what happened:

```
cd C:/git/ago/ago-deploy

# Is this account actually locked? `disabled: true` is the unambiguous answer.
curl -s http://127.0.0.1:8081/admin/realms/ago-chat/attack-detection/brute-force/users/00000000-0000-0000-0000-000000000004 \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Clear every lockout in the realm.
curl -s -X DELETE http://127.0.0.1:8081/admin/realms/ago-chat/attack-detection/brute-force/users \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

(`$ADMIN_TOKEN` is the one minted in the self-registration section above; the UUID is
`demo-operator`'s fixed realm-import id.)

The same item put a **12-character minimum** on the realm's password policy, plus "not the username"
and "not the email". It applies to accounts created through the admin API too, not just the hosted
form — a `reset-password` call with a short value comes back `400
invalidPasswordMinLengthMessage`, which is worth recognising before assuming the admin token is
wrong. Every seeded and documented password in this project already satisfies it.

### Becoming the platform owner locally (`12-01`/`12-03`)

`12-01` defines the `platform-owner` realm role in `k8s/base/keycloak-realm-import.json` and grants it
to **nobody**, deliberately (that same file provisions the public demo realm). Nothing in the product
can grant it either - it is a realm role, so Keycloak's own admin API is the only way in, which is the
point. Grant it to a seeded user, verify, then take it away:

```
export $(grep -v '^#' deploy/docker/.env | xargs)
KC=http://127.0.0.1:8081
ADMIN_TOKEN=$(curl -s -X POST $KC/realms/master/protocol/openid-connect/token \
  -d "grant_type=password&client_id=admin-cli&username=$KEYCLOAK_ADMIN_USER&password=$KEYCLOAK_ADMIN_PASSWORD" \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
USER_ID=$(curl -s "$KC/admin/realms/ago-chat/users?username=demo-admin&exact=true" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
ROLE=$(curl -s "$KC/admin/realms/ago-chat/roles/platform-owner" -H "Authorization: Bearer $ADMIN_TOKEN")

curl -s -X POST "$KC/admin/realms/ago-chat/users/$USER_ID/role-mappings/realm" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" -d "[$ROLE]"
# ... verify, then revoke - same call, DELETE instead of POST:
curl -s -X DELETE "$KC/admin/realms/ago-chat/users/$USER_ID/role-mappings/realm" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" -d "[$ROLE]"
```

Two things found by actually doing this (`12-03`, 2026-08-25), both of which cost time otherwise:

- **The master admin token expires in about a minute.** Fetch it inside the same script that uses it;
  a token pasted from a previous command reliably returns `401` on the next call.
- **A Keycloak container started before `12-01` merged does not have the role**, because
  `--import-realm` imports a realm only when it does not already exist - the mounted file changing
  afterwards does nothing. `curl .../roles/platform-owner` returning `{"error":"Could not find role"}`
  on an otherwise healthy realm is this, not a typo. Create the role once by hand (`POST
  /admin/realms/ago-chat/roles` with `{"name":"platform-owner"}`), which is what the import would have
  done. Since `15-01` this is the *only* option for a realm role: `apply-realm-settings.sh` covers
  realm-level settings, not roles, and dropping the realm to force a re-import would take every
  self-registered account with it (`adr/0036`).

The role has to be in the token, not just in the database: re-fetch the user's access token after
granting (the direct-grant snippets above), and `realm_access.roles` should contain `platform-owner`.
`GET /api/v1/owner/sites` (`12-02`) answers `200` with it and `403` with `Content-Length: 0` without
it - the console's `/owner` screen (`12-03`) renders whichever of those two the server returns, and
holds no opinion of its own about who the owner is.

### Running the widget demo locally

**Shipped in `5-09`**: `ago-widget/demo/` is a deliberately hostile host page proving the widget's
Shadow DOM isolation for real, not by inspection. It needs `Ago.Chat.Api` and the demo tenant from
the bring-up sequence above, plus the widget's own build:

```
cd ago-widget
npm ci
AGO_API_BASE_URL=http://localhost:5009 npm run build
npx serve -l 8080 .          # whole repo, not just demo/ - the demo page's dist/ reference needs both
```

Serving on port `8080` specifically matters: `create-demo-tenant.sh` only allows the origin
`http://localhost:8080` in the demo site's `AllowedOrigins`, and the whole point of this demo page is
a real cross-origin request through `5-01`'s CORS policy, not one disabled for the test. Open
`http://localhost:8080/demo/`.

**Testing a real reconnect (node death) locally**: the fast loop's single `dotnet run` instance uses a
random per-process signing key by default (`3-06`'s finding, above) - killing and restarting *that*
process invalidates every visitor token, which reads as an auth failure, not a resume. To prove a
genuine "node died, a replacement resumed the session" reconnect the way a real multi-replica overlay
would, restart with an explicit, stable key instead:

```
Auth__SigningKey="<any base64 32-byte value>" ASPNETCORE_ENVIRONMENT=Development \
  dotnet run --project ../ago-chat/src/Ago.Chat.Api
```

Verified this way (`5-09`): killing the process and restarting it with the *same* `Auth__SigningKey`
reconnected in ~10s (jittered backoff) and resumed with the exact prior message present exactly once
- no gap, no duplicate. Restarting *without* the fixed key reproduces the expected 401, which is
`3-06`'s already-documented limitation of the single-dev-instance loop, not a new bug.

### Running the console locally

**Shipped in `5-06`**: `ago-console` is a normal SPA (Vite + React, `adr/0023`), not a script embedded
on a page it doesn't control, so it's built once per environment rather than configured per-embed
the way `ago-widget` is. It needs `Ago.Chat.Api` and Keycloak from the bring-up sequence above, plus
its own env file and dev server:

```
cd ago-console
cp .env.example .env.local        # first time only - defaults already match the fast loop above
npm ci
npm run dev
```

Open `http://localhost:5173`. `RequireAuth` redirects straight to Keycloak's own login page
(Authorization Code + PKCE, `oidc-client-ts`); sign in as `demo-operator` (`5-05`'s seeded user), and
Keycloak redirects back to `/callback`, which exchanges the code for tokens and lands on the queue
page showing "Operator hub: Connected" once the SignalR connection to `/hubs/operator` opens with the
resulting access token.

Two registrations both have to know about port `5173`, or this fails before reaching the app at all:

- **Keycloak's `ago-console` client** needs `http://localhost:5173/*` in both `redirectUris` and
  `webOrigins` (`deploy/k8s/base/keycloak-realm-import.json`). Keycloak only imports a realm that
  doesn't already exist yet, so an existing local install needs this applied by hand once (Admin
  console, or a REST API `PUT` on the client) in addition to the committed file, which only takes
  effect on a fresh realm.
- **The demo site's `AllowedOrigins`** (`5-01`'s CORS policy) needs `http://localhost:5173` alongside
  the widget demo's `:8080`, or the console's very first API call fails CORS before Keycloak is even
  reached. `deploy/seed/create-demo-tenant.sh` seeds both origins and now `DO UPDATE`s
  `allowed_origins` on conflict rather than `DO NOTHING`, specifically so re-running it against an
  already-seeded local install picks up a newly-added origin like this one. Flush Redis after
  re-running it - the CORS-origin cache has no event-driven invalidation wired up yet (`5-01`'s
  documented scope limit).

Verified this way: real login through the local Keycloak, real redirect back through `/callback`,
real token handed to `/hubs/operator`, connection state genuinely reaching `Connected` in the browser
- not inferred from the code. `automaticSilentRenew` is still deliberately not enabled - `5-07`
hit the access-token-expiry gap this note already called out (Keycloak's default token lifetime is a
few minutes, well inside one manual test session), and confirmed the current behaviour is exactly what
was documented here: no crash, no confusing partial state, just a `401` on the next hub negotiate and
the operator has to sign in again. Wiring real silent renewal stays a deliberate, stated gap, not
something `5-07` was scoped to close.

**Shipped in `5-07`**: the console's real conversation experience verified end to end against this
same bring-up sequence - operator login, a visitor conversation started from `dev-harness.html`,
automatic assignment (`4-02`) surfacing it in the console's queue view, both sides exchanging messages
live, a mid-conversation `Ago.Chat.Api` process kill-and-restart (same fixed `Auth__SigningKey`
approach as `5-09`'s note below) resuming with no gap and no duplicate on both the operator and visitor
sides, and `clientMessageId` retry-dedup proven directly over the wire (two `SendMessageAsync`
invocations with the same `clientMessageId` returned the identical `sequence`, exactly one row in
`messages`). Two real, unrelated bugs found live while doing this, both fixed in the same change:

- `dev-harness.html`'s `sendVisitorMessage()`/`sendOperatorMessage()` had been calling
  `SendMessageAsync` with only 2 positional arguments since `1-06`, silently broken the moment `5-03`
  added a third parameter (`attachmentId`) - the same SignalR argument-count gotcha this file already
  documents for `JoinAsync` above, just never hit on this call path because nothing had exercised a
  real visitor send against a post-`5-03` server since. Fixed by passing explicit `null`s, same as the
  existing `JoinConversationAsync` call already does.
- `ago-console`'s `OperatorConnectionProvider` called `connection.stop()` in its effect's cleanup
  function. In development, React StrictMode's synthetic mount -> cleanup -> remount cycle raced that
  `stop()` against the still-negotiating `start()` from the same mount, permanently breaking the
  connection (`HubConnection` never recovered on its own). Fixed by not stopping the connection on this
  cleanup at all - the provider sits at a layout-route level specifically so it survives every in-app
  navigation, so there is no legitimate in-app unmount to clean up after; a real end of session is
  already handled by the browser tearing down the socket itself.

Local endpoints (all verified reachable):

| Endpoint | Address |
|---|---|
| Postgres | `localhost:5432` |
| RabbitMQ (AMQP) | `localhost:5672` |
| RabbitMQ management UI | http://localhost:15672 |
| Redis | `localhost:6379` |
| MinIO S3 API | `localhost:9000` |
| MinIO console | http://localhost:9001 |
| Keycloak (OIDC) | http://localhost:8081 (`5-05`) |
| Keycloak health/management | http://localhost:8082 |
| `Ago.Chat.Api` health | http://localhost:5009/healthz/live (port from `launchSettings.json`) |
| Prometheus | http://localhost:9090/targets (`7-03`) |
| Grafana | http://localhost:3000 (`7-03`, `GRAFANA_ADMIN_USER`/`GRAFANA_ADMIN_PASSWORD` from `deploy/docker/.env` - same env-var-driven, no-committed-secret-value shape as Keycloak's admin credentials above) |
| Jaeger UI | http://localhost:16686 (`7-03`) |

**`7-03`**: `Ago.Chat.Worker`/`Ago.Chat.Webhooks` have no `applicationUrl` in their own
`Properties/launchSettings.json` (neither file has one, unlike `Ago.Chat.Api`'s `http://localhost:5009`),
so both default to Kestrel's bare `http://localhost:5000` and collide with each other if started
together the way this runbook's own bring-up sequence does - verified live: starting `Ago.Chat.Worker`
alone logs `Now listening on: http://localhost:5000`. Prometheus's compose-loop scrape config
(`deploy/docker/prometheus-scrape-config.yml`) assumes fixed, distinct ports instead - start Worker and
Webhooks with an explicit `ASPNETCORE_URLS` so the collision and the scrape targets are resolved
together:

```
ASPNETCORE_URLS=http://localhost:5010 dotnet run --project ../ago-chat/src/Ago.Chat.Worker
ASPNETCORE_URLS=http://localhost:5011 dotnet run --project ../ago-chat/src/Ago.Chat.Webhooks
```

**Metrics gotcha found while verifying `7-03`, fixed in `7-02` before merge**: none of the three hosts
served `/metrics` at first - confirmed live (`curl http://localhost:5009/metrics` against a real running
`Ago.Chat.Api` returned an empty body and `HTTP 404`, Prometheus's own targets page showed every
`Ago.Chat.*` target `DOWN` with a real connection/404 error, not a wiring mistake in the scrape config).
Root cause: `7-02`'s first draft wired metrics through the same `AddOtlpExporter` **push** call tracing
uses, pointed at the same `Otel:Exporter:Endpoint` (Jaeger) - but Jaeger's OTLP receiver only implements
the trace collector service, and Prometheus's own model is pull/scrape in the first place, not push, so
every metric silently went nowhere either way. Fixed by replacing that with `AddPrometheusExporter()`
plus one `app.MapPrometheusScrapingEndpoint()` line per host's own `Program.cs` (mapping the endpoint
needs the built `WebApplication`, not available from `Ago.Platform.Hosting`'s own `IServiceCollection`-
only extension method). Re-verified after the fix: `/metrics` returns real Prometheus-format output, and
Prometheus's targets page shows `ago-chat-api` `up`.

`Ago.Chat.Worker`'s `/healthz/ready` is a real check as of `2-04` (Postgres + RabbitMQ reachable, not
trivially healthy) - verified: started against the compose stack above, `/healthz/live` and
`/healthz/ready` both `200`, and three rows inserted directly into `outbox` one at a time, each after
the previous one was confirmed published, were each published and marked `published_at` within ~2s
(`LISTEN`/`NOTIFY`, not the 5s poll fallback). Deliberately checked more than one insert, not just the
first: a bug found afterward (`OutboxDispatcher`'s poll loop could permanently stall the first time a
`NOTIFY` won its race against the poll timer - see `2-04`'s backlog entry) would have passed a
single-insert check and then silently never dispatched anything again. `Ago.Chat.Api` and
`Ago.Chat.Webhooks` still expose `/healthz/live` and `/healthz/ready` trivially healthy, since neither
has a real dependency wired up yet to report on (`architecture/edge.md`).

**Environment gotcha found while verifying `2-04`**: on this Docker Desktop/Windows setup, a raw AMQP
connection to `localhost:5672` hangs for the full connection timeout instead of failing fast, because
`RabbitMQ.Client` tries the `::1` (IPv6) resolution of `localhost` first and that address never
completes the TCP handshake through Docker Desktop's port mapping, even though the container's IPv6
port is listed as published. Plain HTTP requests to `localhost` (e.g. the management UI on `15672`)
are unaffected - only raw AMQP sockets hit this. Fixed by pointing `Messaging:RabbitMq:HostName` at
`127.0.0.1` explicitly in `Ago.Chat.Worker`'s `appsettings.Development.json`, sidestepping the
resolution order entirely rather than trying to disable IPv6 for one client.

**Environment gotcha found while verifying `3-03`**: `Ago.Chat.Api` failed to start against the
compose stack with `OptionsValidationException: ... 'HostName' ... 'UserName' ... 'Password' ...
required` for `RabbitMqOptions`. `3-02` gave `Ago.Chat.Api` its first real reason to need RabbitMQ
(`NodeDeliveryConsumer`), but `appsettings.Development.json` was never updated to configure it -
only `Redis:ConnectionString` was there, left over from `3-01`. Fixed by adding the same
`Messaging:RabbitMq` block `Ago.Chat.Worker`'s own `appsettings.Development.json` already has
(`127.0.0.1`, not `localhost` - the same IPv6-resolution gotcha noted above for `Ago.Chat.Worker`
applies here too). While debugging this, also enabled `EnableDetailedErrors` on `AddSignalR()` for
Development - without it, a hub method's real exception is replaced with a generic "Failed to invoke
'X' due to an error on the server" client-side, which is not enough to debug a `dev-harness.html`
session by hand.

**SignalR gotcha found the same session**: `dev-harness.html` originally omitted the argument for
`JoinAsync`'s new optional `lastKnownSequence` parameter on its very first call
(`invoke('JoinAsync')`). C#'s optional-parameter default does not help here - SignalR's client
binder matches invocations by **argument count**, not by the target method's defaults, and throws
`InvalidDataException: Invocation provides 0 argument(s) but target expects 1` for a short call.
Fixed by always passing an explicit argument - `null` for "no known sequence" - never omitting it.

**RabbitMQ gotcha found while running `6-06`'s load proof**: a long-lived local compose broker that
predates `5-11`'s queue-naming fix accumulates orphaned queues under the old bare topic names
(`MessageAccepted`, `ConversationAssignedToOperator`, `OperatorPresenceLost`, `AttachmentConfirmed`) -
still bound to the exchange, still silently collecting a full copy of every event, with zero consumers
since no code names them anymore. Not a code bug - RabbitMQ doesn't delete a queue just because nothing
declares it anymore - but it looks alarming in the management UI and skews queue-depth checks. If a
bare-named queue shows message counts growing with no consumers, purge it:
`curl -u ago:ago-local-dev -X DELETE http://127.0.0.1:15672/api/queues/%2f/<queue-name>` (safe on a dev
box - the data is disposable). See `docs/backlog/5-11-fix-competing-consumer-queue-collision.md`'s
"Operational note" for why this happens and why it will matter again on a real deployed cluster.

## Configuration

`appsettings.Development.json` for defaults, `appsettings.Local.json` for anything machine-specific.
The latter is gitignored, and secrets never enter the repository. Every options class is validated at
startup, so a wrong key fails fast instead of silently disabling a feature.

## Common tasks

- Run the fast tests: `dotnet test` (domain, application, architecture).
- Run integration tests: they start their own containers; Docker must be running.
- Apply migrations: see the bring-up sequence above - verified against the real `docker-compose`
  Postgres (`1-04`). `AgoChatDbContextFactory` reads the connection string from
  `AGO_CHAT_CONNECTION_STRING`, never a hardcoded default (repositories.md - "no secrets, ever").
- Create the attachments bucket: `deploy/seed/create-minio-bucket.sh` (verified; source
  `deploy/docker/.env` first).
- Seed the demo site and operator: `deploy/seed/create-demo-tenant.sh` (verified, idempotent - `1-05`,
  updated in `5-05` to link the operator row to Keycloak's own demo-operator user; source
  `deploy/docker/.env` first). Prints the demo site's public key and the demo operator's id - "Getting
  a working operator session locally" above is what actually turns that into a usable token now.
- Stop and restart without losing data: `down` then `up -d` again - verified, comes back healthy
  with no manual fixes. Add `-v` to `down` to also wipe the named volumes for a truly clean slate
  (not run in this session - permission for a volume-destroying command was withheld; the command
  itself is standard compose behaviour, just not exercised here).
- Build a host's container image: `docker build --build-context nugetfeed=../.nuget-feed --build-arg
  PROJECT_NAME=Ago.Chat.Api|Worker|Webhooks -t ago-chat-api:local .` from `ago-chat`'s own root
  (`Dockerfile`'s own header comment has the full reasoning for the shared-file/build-arg shape).
  `8-00`: the final stage is `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled`, not the full
  Debian image - ~43% smaller for Api/Webhooks, ~15% for Worker at the time (`docker image ls`,
  `8-00`'s own report has the exact numbers), verified live against this same compose stack (real
  `/api/v1/visitor-sessions` call, real `/healthz/ready` checks, real webhook-delivery DB writes on
  all three hosts, no ICU/globalization exception). One harmless warning to expect and not chase:
  `Cannot load library libgssapi_krb5.so.2` in Worker's startup log - Npgsql's optional GSSAPI-auth
  probe not finding that library on the minimal image, falling back cleanly since this compose
  Postgres doesn't use GSSAPI auth anyway.
  `8-04`: the build stage's `dotnet restore`/`dotnet publish` are now RID-restricted to `linux-x64`
  (`--self-contained false` kept - still framework-dependent, only the RID is pinned, since the build
  stage's own base image and every deploy target are always Linux). Before this, a RID-agnostic
  publish shipped every RID's native assets for every native-asset NuGet package in the dependency
  closure - almost entirely SkiaSharp (`Ago.Chat.Worker`'s attachment-thumbnail dependency, `5-04`),
  which alone put ~440MB of win-x64/win-arm64/osx/linux-arm64/linux-musl-\*/etc. binaries under
  `/app/runtimes` that this container could never load. Real sizes (`docker image ls`, same three
  images, same day): Api 140MB -> 140MB, Webhooks 139MB -> 139MB (neither carries a multi-RID native
  package, so no change), Worker 599MB -> 151MB (~75% smaller) - the RID-specific publish now places
  `libSkiaSharp.so` directly under `/app` with no `runtimes/` tree at all. Re-verified live the same
  way as `8-00`: all three hosts' `/healthz/live` and `/healthz/ready` return 200 against this compose
  stack, and a real `POST /api/v1/visitor-sessions` against the RID-restricted Api image still returns
  201 with a real token.

## When something is wrong

1. Are the containers healthy? `docker compose ps`.
2. Did migrations run? Check the migrations history table.
3. Is the broker reachable and are the queues declared? Management UI.
4. Read the logs before changing code — structured logs carry the trace id that ties a request to its
   consumer side.
