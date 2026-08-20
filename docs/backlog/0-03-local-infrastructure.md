# Local infrastructure: compose and Kubernetes

- **Stage**: 0
- **Status**: done — compose and Kubernetes loops both verified end to end against a real cluster,
  three real bugs found and fixed along the way (see "Done when"). Also resolved a question this
  item surfaced: `ingress-nginx` (originally assumed) was archived in March 2026; replaced with
  NGINX Gateway Fabric (`adr/0014`), installed and its route verified end to end.
- **Depends on**: `0-01-repositories-and-skeleton.md`

## Goal

Both local loops work from a clean machine: docker-compose for infrastructure-only development, and
the Docker Desktop Kubernetes cluster for everything about scale-out.

## Context to read first

`docs/architecture/edge.md`, `docs/runbooks/local-dev.md`, `docs/runbooks/k8s-local.md`,
`.claude/skills/local-cluster/SKILL.md`.

## Scope

- `deploy/docker/docker-compose.yml`: Postgres, RabbitMQ (management UI), Redis, MinIO, with
  healthchecks, pinned image versions, and named volumes.
- `deploy/k8s/base/`: the same four dependencies plus placeholders for the three hosts, with resource
  requests/limits, probes, and `terminationGracePeriodSeconds`.
- `deploy/k8s/overlays/local/`: replica counts, `Gateway`/`HTTPRoute` host, and local-only settings.
- NGINX Gateway Fabric install instructions in the runbook (not vendored into the repo; `adr/0014`).
- Seed script creating the demo tenant, an operator, and the MinIO bucket.
- Both runbooks updated with the **actual** commands, verified by running them.

## Out of scope

- Helm charts — Kustomize is enough at this size, and the choice is recorded if that changes.
- Any production or cloud overlay; Stage 8 owns that.

## Done when

- [x] `docker compose up -d` gives a working local infrastructure set. Verified: all four containers
      report `healthy`, and are independently reachable (Postgres query, Redis `PING`, RabbitMQ and
      MinIO management UIs, MinIO's own health endpoint).
- [x] `kubectl apply -k deploy/k8s/overlays/local` brings the cluster up, all pods ready. Verified
      against a real single-node cluster (Docker Desktop, kubeadm mode): all seven pods
      (four infrastructure + three `Ago.Chat.*` hosts) reached `1/1 Running`, all four PVCs `Bound`,
      all seven Services created. Getting there surfaced three real bugs, all fixed in
      `k8s/base/`:
      - Postgres's probes used `$(POSTGRES_USER)` — that syntax only expands in a container's own
        `command`/`args`, never inside a probe's `exec.command` (no shell runs it). `pg_isready` was
        receiving the literal string as a username on every check. Fixed with an explicit `sh -c`.
      - RabbitMQ's memory limit (256Mi, then 512Mi) OOM-killed the container during startup twice.
      - The real cause of that OOM churn: `rabbitmq-diagnostics ping` spins up its own Erlang VM per
        invocation: too short a probe period let successive checks pile up (five concurrent
        `rabbitmq-diagnostics` processes were observed at once), and the pile-up's own memory cost
        compounded the OOM risk independently of the broker's own footprint. Fixed by widening the
        readiness period so one check always finishes before the next starts, and moving liveness to
        a cheap `tcpSocket` check instead of the expensive one - restarting a broker that was merely
        slow to answer is exactly the failure a liveness probe should not cause.
- [x] Both runbooks contain commands that were actually executed, with real output shapes — true for
      both now. `k8s-local.md` additionally documents the NGINX Gateway Fabric install (three
      commands, all run for real) and the Gateway/HTTPRoute verification
      (`curl -H "Host: ago-chat.localhost" ...` → `200`, same request without the header → `404`,
      proving hostname routing and not just "something answers on :80").
- [x] Tearing everything down and bringing it back up works without manual fixes — verified for
      `docker compose down` + `up -d`. `down -v` (full volume wipe) was not exercised: the sandbox
      withheld permission for that specific destructive command this session.

## Open questions

None.
