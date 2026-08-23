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

## When something is wrong

1. Are the containers healthy? `docker compose ps`.
2. Did migrations run? Check the migrations history table.
3. Is the broker reachable and are the queues declared? Management UI.
4. Read the logs before changing code — structured logs carry the trace id that ties a request to its
   consumer side.
