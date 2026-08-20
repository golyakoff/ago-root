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
dotnet run --project ../ago-chat/src/Ago.Chat.Api
dotnet run --project ../ago-chat/src/Ago.Chat.Worker
dotnet run --project ../ago-chat/src/Ago.Chat.Webhooks
```

Local endpoints (all verified reachable):

| Endpoint | Address |
|---|---|
| Postgres | `localhost:5432` |
| RabbitMQ (AMQP) | `localhost:5672` |
| RabbitMQ management UI | http://localhost:15672 |
| Redis | `localhost:6379` |
| MinIO S3 API | `localhost:9000` |
| MinIO console | http://localhost:9001 |
| `Ago.Chat.Api` health | http://localhost:5299/healthz/live (port from `launchSettings.json`) |

Each host also exposes `/healthz/live` and `/healthz/ready` - trivially healthy for now, since none
of them have a real dependency wired up yet to report on (`architecture/edge.md`).

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
