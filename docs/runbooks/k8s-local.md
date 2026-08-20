# Runbook: local Kubernetes

> **Status: skeleton.** Filled in and verified by `0-03-local-infrastructure.md`.

The cluster is **Docker Desktop's built-in Kubernetes** (Settings → Kubernetes → Enable). One node,
which is enough for everything except real node-failure testing — and honest about that limit.

## Bring-up

```
kubectl config use-context docker-desktop
kubectl apply -k deploy/k8s/overlays/local
kubectl get pods -w
```

ingress-nginx is installed once per machine (command goes here once verified) and reaches the cluster
on `localhost`.

## What to check after a change

- `kubectl get pods` — everything `Running` **and** ready.
- Readiness must be false while a pod drains, and true only when it will accept traffic.
- `kubectl rollout restart deployment/ago-api` under load is the cheapest way to test the drain path.

## Scale-out testing

Only the cluster can answer these, so use it for them:

- More than one Api replica and cross-node delivery (`adr/0007`).
- Rolling deploy without losing acknowledged messages.
- Pod kill mid-load.
- Ingress behaviour with WebSocket upgrades and idle timeouts.

## Known limits of this setup

- One node: pod anti-affinity, node drain and real network partitions cannot be tested here. Say so
  rather than claiming coverage that does not exist.
- Docker Desktop's resource limits are the effective ceiling for every load number produced locally,
  and every report must state them (`load-testing.md`).
