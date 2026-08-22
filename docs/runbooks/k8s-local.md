# Runbook: local Kubernetes

> **Status: verified against a real cluster.** `kubectl apply -k deploy/k8s/overlays/local` was run
> for real (0-03-local-infrastructure.md): all seven pods reached `1/1 Running`, all four PVCs
> `Bound`. Getting there found and fixed three real bugs in the manifests - see the backlog item for
> the detail, and "Known issues found this way" below for the one prerequisite worth knowing before
> you hit it yourself. NGINX Gateway Fabric (`adr/0014`) was installed and its route to
> `Ago.Chat.Api`'s health endpoint verified end to end, hostname matching included.
>
> **`3-06` re-verified with 3 `ago-chat-api` replicas**: `/api` and `/hubs` now actually route
> through the Gateway too (the `HTTPRoute` only carried `/healthz` until this point - a stale
> comment claimed `/api`/`/hubs` "arrive with Stage 1," but the route itself was never updated). A
> real `kubectl rollout restart deployment/ago-chat-api` under synthetic load produced zero
> acknowledged-but-lost messages; `least_conn` confirmed live in the Gateway's own generated NGINX
> config (`concurrency.md`, `edge.md` have the full detail and the two bugs this surfaced).

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

`ago-chat-api` runs 3 replicas here since `3-06` (`least_conn` across them, `edge.md`) - copy
`deploy/k8s/overlays/local/.env.example` to `.env` first if this is a fresh checkout; it now also
carries `AUTH_JWT_SIGNING_KEY`, needed so every replica validates the same tokens (`authorization.md`).

## Migrations and seeding

**Verified against this cluster's own Postgres, `3-06`** - the commands below were run for real, not
assumed to match the `docker-compose` path `1-04`/`1-05` verified:

```
kubectl port-forward svc/postgres 15432:5432 -n ago-chat
# from ago-chat, on a machine with the .NET SDK and the dotnet-ef tool installed -
# Microsoft.EntityFrameworkCore.Design is PrivateAssets=all (Ago.Chat.Infrastructure.Postgres.csproj),
# specifically so it never flows into ago-chat-api's own image, so migrating from inside the
# cluster is not an option:
AGO_CHAT_CONNECTION_STRING="Host=localhost;Port=15432;Database=ago_chat;Username=ago;Password=ago-local-dev" \
  dotnet ef database update -p src/Ago.Chat.Infrastructure.Postgres -s src/Ago.Chat.Infrastructure.Postgres
```

`ago-deploy/seed/create-demo-tenant.sh` targets the `docker-compose` network by name and will not
reach this cluster's Postgres as written - seed the same fixed-id rows with `kubectl exec -n ago-chat
deploy/postgres -- psql -U ago -d ago_chat -c "..."` instead, using the script's own SQL block.

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

`3-06` added `/api` and `/hubs` to the same `HTTPRoute` (only `/healthz` routed before that -
`Ago.Chat.Api`'s actual endpoints had existed since Stage 1/2, the route just never caught up):

```
curl -H "Host: ago-chat.localhost" -H "Content-Type: application/json" \
  -d '{"publicKey":"demo_site"}' http://localhost/api/v1/visitor-sessions   # 201, a visitor JWT
```

## What to check after a change

- `kubectl get pods -n ago-chat` — everything `Running` **and** ready.
- Readiness must be false while a pod drains, and true only when it will accept traffic.
- `kubectl rollout restart deployment/ago-chat-api -n ago-chat` under load is the cheapest way to
  test the drain path.
- `least_conn` is genuinely wired, not just declared: exec into the Gateway's data-plane pod
  (`kubectl exec -n ago-chat deploy/ago-chat-gateway-nginx -- grep -A6 'upstream ago-chat_ago-chat-api'
  /etc/nginx/conf.d/http.conf`) and look for `least_conn;` and one `server` line per replica.

## Scale-out testing

Only the cluster can answer these, so use it for them:

- More than one Api replica and cross-node delivery (`adr/0007`) - **done, `3-06`**: 3 replicas,
  live-verified (see the Status note above).
- Rolling deploy without losing acknowledged messages - **done, `3-06`**.
- Pod kill mid-load.
- Ingress behaviour with WebSocket upgrades and idle timeouts.

## Known limits of this setup

- One node: pod anti-affinity, node drain and real network partitions cannot be tested here. Say so
  rather than claiming coverage that does not exist.
- Docker Desktop's resource limits are the effective ceiling for every load number produced locally,
  and every report must state them (`load-testing.md`).
