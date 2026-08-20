# Local infrastructure: compose and Kubernetes

- **Stage**: 0
- **Status**: ready
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
- `deploy/k8s/base/`: the same four dependencies plus placeholders for the two hosts, with resource
  requests/limits, probes, and `terminationGracePeriodSeconds`.
- `deploy/k8s/overlays/local/`: replica counts, ingress host, and local-only settings.
- ingress-nginx install instructions in the runbook (not vendored into the repo).
- Seed script creating the demo tenant, an operator, and the MinIO bucket.
- Both runbooks updated with the **actual** commands, verified by running them.

## Out of scope

- Helm charts — Kustomize is enough at this size, and the choice is recorded if that changes.
- Any production or cloud overlay; Stage 8 owns that.

## Done when

- [ ] `docker compose up -d` gives a working local infrastructure set.
- [ ] `kubectl apply -k deploy/k8s/overlays/local` brings the cluster up, all pods ready.
- [ ] Both runbooks contain commands that were actually executed, with real output shapes.
- [ ] Tearing everything down and bringing it back up works without manual fixes.

## Open questions

None.
