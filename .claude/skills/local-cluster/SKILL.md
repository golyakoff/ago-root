---
name: local-cluster
description: Run AGO Platform locally - docker-compose inner loop and the Docker Desktop Kubernetes cluster, manifests, probes, ingress and troubleshooting. Use when starting the stack, changing deployment manifests, or debugging why something will not come up.
---

# Running it locally

Authoritative sources: `docs/runbooks/local-dev.md`, `docs/runbooks/k8s-local.md`,
`docs/architecture/edge.md`.

## Two loops, used for different things

- **docker-compose** (`deploy/docker/`): infrastructure only - Postgres, RabbitMQ, Redis, MinIO -
  with the app running from the IDE. This is the fast loop; use it for feature work.
- **Kubernetes on Docker Desktop** (`deploy/k8s/overlays/local`): the whole system, multiple
  replicas. Use it for anything about scale-out, rolling deploys, probes, or ingress - i.e. anything
  the single-process loop cannot honestly test.

Never test a scale-out behaviour in compose and claim it works in the cluster.

## Manifest rules

- Kustomize: `base` holds the real definitions, `overlays/local` holds only what differs. If a value
  appears identically in both, it belongs in base.
- Resource requests and limits on every workload - `nfr.md` states the budgets, and a pod without
  limits invalidates any memory measurement.
- Probes are three distinct things and must stay distinct: startup (migrations done), readiness
  (willing to take traffic - false while draining), liveness (process healthy). Conflating readiness
  and liveness means Kubernetes kills pods that are deliberately shedding load.
- `terminationGracePeriodSeconds` > `preStop` sleep + drain deadline, or the durability guarantee is
  a lie (`concurrency.md`).
- Config through ConfigMaps, secrets through Secrets, both bound to validated options classes so a
  typo fails startup instead of silently disabling a feature.
- Ingress carries TLS, coarse rate limits and `least_conn`. It never carries business behaviour -
  CORS per site is a database lookup and lives in the app (`edge.md`).

## Troubleshooting order

1. `kubectl get pods` - is it `CrashLoopBackOff`, `Pending`, or `Running` but not ready?
2. `Pending` is almost always resources on Docker Desktop, or a PVC that cannot bind.
3. `kubectl logs --previous` for a crash loop; startup failures are usually configuration binding or
   a migration that did not run.
4. Ready but unreachable: check the Service selector, then the ingress path, then whether the ingress
   controller is actually installed in the cluster.
5. WebSocket connects then drops: read timeouts on the ingress, then the client's reconnect logic.
6. Only after all that, suspect the application.

## Rules for sessions

- Do not invent `kubectl` output. Run the command or say you did not.
- Do not add a new infrastructure component to the cluster without an ADR - each one is a thing the
  author has to operate, explain, and pay for at demo time.
