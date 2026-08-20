# Runbook: local Kubernetes

> **Status: verified against a real cluster.** `kubectl apply -k deploy/k8s/overlays/local` was run
> for real (0-03-local-infrastructure.md): all seven pods reached `1/1 Running`, all four PVCs
> `Bound`. Getting there found and fixed three real bugs in the manifests - see the backlog item for
> the detail, and "Known issues found this way" below for the one prerequisite worth knowing before
> you hit it yourself. NGINX Gateway Fabric (`adr/0014`) was installed and its route to
> `Ago.Chat.Api`'s health endpoint verified end to end, hostname matching included.

The cluster is **Docker Desktop's built-in Kubernetes** (Settings → Kubernetes → Enable, cluster
type **Kubeadm** - not **kind**, which needs a separate image-loading step our
`imagePullPolicy: Never` manifests do not do). One node, which is enough for everything except real
node-failure testing — and honest about that limit.

## Bring-up

```
kubectl config use-context docker-desktop
bash deploy/k8s/build-images.sh              # builds ago-chat-{api,worker,webhooks}:local
kubectl apply -k deploy/k8s/overlays/local
kubectl get pods -n ago-chat -w
```

`kubectl kustomize deploy/k8s/overlays/local` renders the same manifests without needing a cluster
connection at all - useful for reviewing a change before applying it.

## Migrations and seeding

Not yet re-verified against this cluster's own Postgres specifically - `1-04`/`1-05` verified the
migration and the seed script against the `docker-compose` Postgres only (`local-dev.md`), which is
what those items' own scope committed to. The same commands should work here too, against
`svc/postgres` in the `ago-chat` namespace via `kubectl port-forward svc/postgres 15432:5432 -n
ago-chat` from a machine with the .NET SDK and `dotnet-ef` installed - `Microsoft.EntityFrameworkCore.Design`
is `PrivateAssets=all` (`Ago.Chat.Infrastructure.Postgres.csproj`), specifically so it never flows
into `ago-chat-api`'s own image, so migrating from inside the cluster is not an option as-is. Saying
so here rather than claiming coverage this session did not actually exercise.

## Known issues found this way

- **Kubernetes hanging forever at "Starting Kubernetes cluster..."**: check `wsl --version` and, if
  the kernel looks old, run `wsl --update` then `wsl --shutdown` and restart Docker Desktop. The
  concrete symptom that confirms this diagnosis: Docker Desktop's own VM log
  (`%LOCALAPPDATA%\Docker\log\vm\init.log` on Windows) shows kubelet exiting with *"kubelet is
  configured to not run on a host using cgroup v1"* - Kubernetes requires cgroup v2, and an outdated
  WSL2 kernel can still default to v1. A newer kernel (6.x) logs `detected cgroup2` instead and the
  cluster comes up normally. If Docker Desktop was ever run in **kind** mode first, `wsl --unregister
  docker-desktop` (safe - Docker Desktop recreates this VM from scratch on next launch; built images
  and volumes live on a separate disk and survive it) clears any leftover state before retrying.
- **A `localhost`-bound proxy on Windows** (a corporate security tool, a local VPN client such as
  v2rayN, etc.) needs WSL2's **mirrored networking mode** to be reachable from inside containers -
  add `networkingMode=mirrored` under `[wsl2]` in `%UserProfile%\.wslconfig`, then `wsl --shutdown`
  and restart Docker Desktop. WSL itself will warn about this exact situation (`wsl -d docker-desktop
  -- true`) if it applies.

**NGINX Gateway Fabric** (`adr/0014` - the direct successor to `ingress-nginx`, archived March 2026)
is installed once per machine, in three steps verified against a real cluster:

```
# 1. Gateway API CRDs (version pinned to match the NGF release below)
kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v2.6.7" | kubectl apply -f -

# 2. NGINX Gateway Fabric's own CRDs
kubectl create namespace nginx-gateway
kubectl apply --server-side -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v2.6.7/deploy/crds.yaml

# 3. NGINX Gateway Fabric itself (control plane + default config)
kubectl apply -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v2.6.7/deploy/default/deploy.yaml
```

No cert-manager needed for this default install - the manifest includes its own one-shot
`nginx-gateway-cert-generator` Job. `kubectl get pods -n nginx-gateway` should show one `Completed`
(the cert generator) and one `1/1 Running` (the controller).

`deploy/k8s/overlays/local/gateway.yaml` then defines the `Gateway` (`gatewayClassName: nginx`) and
`HTTPRoute` for this repository; applying it (the normal `kubectl apply -k` above) makes NGF create
its own per-Gateway data-plane `Deployment` and a `LoadBalancer` Service that Docker Desktop maps to
`localhost:80` automatically. Verified end to end:

```
curl -H "Host: ago-chat.localhost" http://localhost/healthz/live   # 200 Healthy
curl http://localhost/healthz/live                                  # 404 - proves hostname routing, not just "anything on :80"
```

## What to check after a change

- `kubectl get pods -n ago-chat` — everything `Running` **and** ready.
- Readiness must be false while a pod drains, and true only when it will accept traffic.
- `kubectl rollout restart deployment/ago-chat-api -n ago-chat` under load is the cheapest way to
  test the drain path.

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
