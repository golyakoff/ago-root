# Runbook: local development

> **Status: skeleton.** The commands below are the intended shape. They are filled in and verified by
> backlog item `0-03-local-infrastructure.md`. Until then, do not quote them as working — a runbook
> nobody has executed is fiction.

## Prerequisites

- .NET 10 SDK
- Docker Desktop (with Kubernetes enabled — see `k8s-local.md`)
- Node 24+ (frontend, from Stage 5)

## The fast loop: infrastructure in Docker, app from the IDE

Paths below assume you are in `ago-root`; the junctions (`deploy/`, `chat/`) make the siblings
reachable from here (`workspace.md`).

```
docker compose -f deploy/docker/docker-compose.yml up -d
dotnet run --project ../ago-chat/src/Ago.Chat.Api
dotnet run --project ../ago-chat/src/Ago.Chat.Worker
```

Local endpoints (to confirm at Stage 0): API, RabbitMQ management UI, MinIO console, Postgres.

## Configuration

`appsettings.Development.json` for defaults, `appsettings.Local.json` for anything machine-specific.
The latter is gitignored, and secrets never enter the repository. Every options class is validated at
startup, so a wrong key fails fast instead of silently disabling a feature.

## Common tasks

- Run the fast tests: `dotnet test` (domain, application, architecture).
- Run integration tests: they start their own containers; Docker must be running.
- Apply migrations: `dotnet ef database update -p <infra project> -s ../ago-chat/src/Ago.Chat.Api`.
- Reset local data: stop compose with volumes removed, then re-seed.

## When something is wrong

1. Are the containers healthy? `docker compose ps`.
2. Did migrations run? Check the migrations history table.
3. Is the broker reachable and are the queues declared? Management UI.
4. Read the logs before changing code — structured logs carry the trace id that ties a request to its
   consumer side.
