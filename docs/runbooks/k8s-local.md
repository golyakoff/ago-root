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
carries `AUTH_JWT_SIGNING_KEY`, needed so every replica validates the same tokens (`authorization.md`),
and, since `15-01`, `KEYCLOAK_DB_PASSWORD` (below). An `.env` copied before `15-01` is missing that key
and Keycloak's pod will sit in `Init:0/1` with `KEYCLOAK_DB_PASSWORD: not set` in the init container's
log - re-copy from `.env.example` rather than guessing what changed.

## Keycloak's user store (`15-01`, `adr/0036`)

Keycloak keeps its realm and its users in **its own `keycloak` database inside the same Postgres
Deployment** that holds `ago_chat`, under its own `keycloak` role. Before `15-01` it ran on an embedded
H2 file in the pod's ephemeral writable layer, and every restart destroyed every account created at
runtime — reproduced live on this cluster before the fix, and gone after it.

Startup ordering is enforced by the pod itself, not by a runbook step: an init container
(`create-keycloak-database`) waits for `pg_isready` against the `postgres` Service, then creates the
role and the database if they are not there. It is idempotent, so it runs on every boot and is a no-op
after the first. Two consequences worth knowing before debugging:

- **Keycloak's pod stays in `Init:0/1` while Postgres is down.** That is the intended reading of a
  dependency, not a stuck pod. `kubectl logs -n ago-chat deploy/keycloak -c create-keycloak-database`
  says which of the two it is.
- **`kubectl exec ... deploy/keycloak` now needs `-c keycloak`**, because the pod has more than one
  container and the default guess is no longer unambiguous.

Verified live on this cluster (2026-08-25), which is the only evidence that counts for this one:

```
# before the fix: create a user, restart, it is gone
# after the fix:
kubectl rollout restart deployment/keycloak -n ago-chat
kubectl exec -n ago-chat deploy/keycloak -c keycloak -- sh -c '
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master \
    --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null
  /opt/keycloak/bin/kcadm.sh get users -r ago-chat --fields username --format csv --noquotes'
```

The runtime-created account was still listed after the restart, and a direct-grant token request for it
still returned `200` with a real access token. Keycloak's own log on that boot reads
`Realm 'ago-chat' already exists. Import skipped` — which is the second half of this change: a changed
`keycloak-realm-import.json` no longer reaches a running realm, and
`deploy/k8s/apply-realm-settings.sh` is how realm-level settings are applied instead
(`local-dev.md`'s "Changing the realm after it exists" has the full rules, including what the script
does *not* cover).

Boot timings were re-measured rather than assumed to carry over from the H2 path, since Liquibase now
runs over the network: first boot into an empty `keycloak` database logged `started in 29.253s` and was
listening ~40s after container start; a restart against the populated database logged `started in
10.852s` and reached Ready at 61s — i.e. the existing `initialDelaySeconds: 60` is now the binding
constraint, not Keycloak, so the probe delays were left unchanged.

**Wiping the local realm is still the cheap way out** when it holds nothing worth keeping: delete the
`postgres-data` PVC (which drops `ago_chat` too, so re-run migrations and the seed afterwards) and the
next boot is a first boot, realm import and all.

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

## Observability (`7-03`)

`kubectl apply -k` above also brings up `prometheus`, `grafana`, and `jaeger` in the `ago-chat`
namespace - verified live: all three reach `1/1 Running`, Grafana's provisioned datasources (Prometheus,
Jaeger) and five dashboards load without error (`/api/datasources`, `/api/search?type=dash-db`), and
Jaeger receives real OTLP traces from all three `Ago.Chat.*` hosts (`Otel__Exporter__Endpoint` wired to
`http://jaeger:4317` in `api.yaml`/`worker.yaml`/`webhooks.yaml` - confirmed via
`http://localhost:16686/api/services` after port-forwarding, listing all three hosts).

```
kubectl port-forward -n ago-chat svc/prometheus 9090:9090   # http://localhost:9090/targets
kubectl port-forward -n ago-chat svc/grafana 3000:3000      # http://localhost:3000
kubectl port-forward -n ago-chat svc/jaeger 16686:16686     # http://localhost:16686
```

**Metrics gotcha found while verifying this item, fixed in `7-02` before merge** (same root cause
`local-dev.md`'s own compose-loop note documents): Prometheus's targets page initially showed every
`Ago.Chat.*` host `DOWN` with a real `404 Not Found` on `/metrics` - DNS and Service routing were
correct, nothing was listening on that path. `7-02` had wired metrics as an OTLP push to Jaeger (which
doesn't implement the OTLP metrics service) instead of a Prometheus scrape endpoint; fixed with
`AddPrometheusExporter()` plus `app.MapPrometheusScrapingEndpoint()` per host. Re-verified after the fix
landed.

**Also found and fixed while verifying this item**: `api.yaml`, `worker.yaml`, and `webhooks.yaml` were
all missing `Storage:S3:*` env vars (`S3StorageOptions` is validated at startup for every host, not only
`Ago.Chat.Api`), and `webhooks.yaml` had no `env`/`envFrom` block at all - a pre-existing gap since
`5-02`/`6-05`, invisible only because the previously-running pods predated these requirements. All three
manifests now carry `Storage__S3__{ServiceUrl,AccessKey,SecretKey,Bucket}` (pointed at `minio.yaml`'s
own Service) and `Webhooks__SecretEncryptionKey` (the same throwaway dev value already committed in
`Ago.Chat.Webhooks/appsettings.Development.json`).

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
