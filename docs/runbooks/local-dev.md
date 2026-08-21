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
HTML+SignalR page, not the real widget/console - `1-06`) and maps `POST /dev/operator-session`;
neither exists outside Development. Verified against a real running instance: a visitor session
(`POST /api/v1/visitor-sessions`), both hubs' JWT auth, `JoinAsync`/`JoinConversationAsync` against
the seeded demo tenant, a message's own sender receiving it back over the SignalR group, and live
cross-tab delivery (the *other* party's tab receiving a reply, in both directions, two separate
tabs) confirmed twice by hand. That second round of manual testing found a real bug, not a tooling
artifact: SignalR scopes `Clients.Group(...)` per hub *type*, so `VisitorHub` and `OperatorHub` never
shared a group even under the same name - fixed by having each hub also broadcast through the other's
`IHubContext<THub>` (`docs/backlog/1-06-api-realtime-and-wiring.md` has the detail).

Local endpoints (all verified reachable):

| Endpoint | Address |
|---|---|
| Postgres | `localhost:5432` |
| RabbitMQ (AMQP) | `localhost:5672` |
| RabbitMQ management UI | http://localhost:15672 |
| Redis | `localhost:6379` |
| MinIO S3 API | `localhost:9000` |
| MinIO console | http://localhost:9001 |
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
- Seed the demo site and operator: `deploy/seed/create-demo-tenant.sh` (verified, idempotent - `1-05`;
  source `deploy/docker/.env` first). Prints the demo site's public key and the demo operator's id,
  which `1-06`'s manual verification and its dev-only operator-auth stub both need.
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
