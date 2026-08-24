# Runbook: public deployment (k3s VPS)

> **Status: design only, not live-verified.** This runbook was written by a session with no VPS to
> deploy to (`8-01`'s own worker scope) — every command below is believed correct against the real
> manifests it references (`k8s/overlays/demo/`) and against `k8s-local.md`'s own already-verified
> install steps where this deployment reuses them unchanged, but nothing here has been run against a
> real Timeweb Cloud node. The next session with real VPS access should run this end to end, fix
> whatever it finds wrong, and update this status line the same way `k8s-local.md`'s own header was
> updated once `0-03` actually ran it. `adr/0026` has the reasoning behind every choice named here;
> this file is the "how", not the "why".

Every step below is marked **(you)** if it can only be done by the author by hand — buying the VPS,
touching a domain registrar's panel, generating and holding real secret values — or **(session)** if a
future Claude Code session with SSH access to the real VPS can run it directly. Nothing in this
runbook can be executed by the worker that wrote it: there is no real VPS in this worktree's reach.

## 1. Provision the VPS **(you)**

- Buy a Timeweb Cloud **MSK 80** instance (4 vCPU / 8 GB RAM / 80 GB NVMe, Moscow region,
  annual billing ≈1 800 ₽/month — `adr/0026`'s sizing math). Russian-issued cards work directly with
  this provider; a Western provider would need a third-party intermediary (`adr/0026`'s context).
- OS image: **Ubuntu 24.04 LTS** ("Noble") — the mainstream Debian-family LTS, and the same distro
  family `8-00`'s Ubuntu Chiseled base image already targets, keeping the base OS and the container
  base image from the same upstream.
- Note the VPS's public IPv4 address — every step below needs it.
- Add an SSH key during provisioning (Timeweb Cloud's own panel) rather than a password login.

## 2. DNS records **(you)**

In `golyakov.net`'s own registrar/DNS panel, add four `A` records pointed at the VPS's IPv4 address:

| Host | Type | Value |
|---|---|---|
| `chat.ago.golyakov.net` | A | `<vps-ip>` |
| `auth.ago.golyakov.net` | A | `<vps-ip>` |
| `console.ago.golyakov.net` | A | `<vps-ip>` |
| `demo-shop1.ago.golyakov.net`, `demo-shop2.ago.golyakov.net` | A | `<vps-ip>` (reserved now, unrouted until `8-02`) |

Give DNS time to propagate before step 6 (cert-manager's HTTP-01 challenge needs the hostname to
already resolve to this node) — a few minutes is typical, occasionally longer.

## 3. Install k3s, disabling the bundled Traefik **(session, once SSH access exists)**

```bash
ssh <user>@<vps-ip>
curl -sfL https://get.k3s.io | sh -s - --disable traefik
sudo k3s kubectl get nodes   # confirms the node is Ready before anything else
```

`k3s-local.md` never had to cover this — Docker Desktop manages the local cluster's own bring-up.
**`--disable traefik` is the one genuinely k3s-specific step this deployment needs**: k3s ships
Traefik as its default ingress controller, which would otherwise bind the same `:80`/`:443` NodePorts
NGINX Gateway Fabric's own data-plane `LoadBalancer` Service needs. Everything downstream of this
(Gateway API CRDs, NGF itself) is standard, conformant Kubernetes API surface — k3s's own control
plane is a real (if lightweight) Kubernetes distribution, so nothing about those install steps needs
adjusting for it.

Copy the kubeconfig somewhere a session can reach it, or export `KUBECONFIG` to
`/etc/rancher/k3s/k3s.yaml` for the rest of this runbook's `kubectl` commands (k3s bundles its own
`kubectl` as `k3s kubectl`; a plain `kubectl` binary works identically once `KUBECONFIG` points here).

## 4. Gateway API CRDs + NGINX Gateway Fabric **(session)**

Identical to `k8s-local.md`'s own already-verified three steps — copied here unchanged, since nothing
about them is Docker-Desktop-specific:

```bash
kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v2.6.7" | kubectl apply -f -
kubectl create namespace nginx-gateway
kubectl apply --server-side -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v2.6.7/deploy/crds.yaml
kubectl apply -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v2.6.7/deploy/default/deploy.yaml
kubectl get pods -n nginx-gateway   # one Completed (cert generator), one 1/1 Running (controller)
```

On a real cloud VPS (unlike Docker Desktop) the NGF data-plane `LoadBalancer` Service will not get an
external IP from a cloud load-balancer controller, since none is installed — that is expected on a
single k3s node with no cloud provider integration. It still binds the node's own `:80`/`:443` via
k3s's built-in `ServiceLB` (klipper-lb), which is what DNS in step 2 is actually pointing at.

## 5. cert-manager **(session)**

Not covered by `k8s-local.md` at all — the local overlay needs no real certificate (NGF's own default
install self-signs for its control-plane webhook, `k8s-local.md`'s own note on that). Install
cert-manager the same static-manifest way NGF itself was installed:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl get pods -n cert-manager -w   # three pods (controller, webhook, cainjector), all 1/1 Running
```

## 6. Get source and build images on the VPS **(session)**

`adr/0026`'s "Image delivery" decision: no registry, build directly on the node, import straight into
k3s's own containerd. Needs the .NET SDK and Docker installed on the VPS in addition to k3s itself
(`sudo apt-get install -y dotnet-sdk-10.0 docker.io` on Ubuntu, or follow each project's own upstream
install docs if the Ubuntu package is behind):

```bash
git clone https://github.com/<author>/ago-platform.git
git clone https://github.com/<author>/ago-chat.git
git clone https://github.com/<author>/ago-deploy.git

cd ago-platform && dotnet pack Ago.Platform.slnx -c Release -o ../ago-deploy/.nuget-feed && cd ..

cd ago-chat
CHAT_REPO=. NUGET_FEED=../ago-deploy/.nuget-feed ../ago-deploy/k8s/build-images.sh
cd ..

for img in ago-chat-api ago-chat-worker ago-chat-webhooks; do
  docker save "${img}:local" | sudo k3s ctr -n k8s.io images import -
done
sudo k3s ctr -n k8s.io images ls | grep ago-chat   # confirms all three landed in the namespace kubelet reads from
```

`build-images.sh` is reused **completely unmodified** — same script, same `:local` tags, same
`CHAT_REPO`/`NUGET_FEED` environment variables it already supports, just run from a different working
directory. The `-n k8s.io` namespace flag on `k3s ctr images import` matters: k3s's embedded
containerd keeps kubelet-visible images in the `k8s.io` namespace specifically, not `ctr`'s own
default namespace — importing without `-n k8s.io` would leave the image invisible to the kubelet, and
`imagePullPolicy: Never` would then fail with `ErrImageNeverPull` even though the image genuinely
exists on the node, just in the wrong namespace. **Not live-verified against a real k3s node in this
session** — flagged plainly per this file's own status line, since it is the one command in this
runbook this session is least confident about without a real node to try it against.

## 7. Generate real secrets **(you)**

```bash
cd ago-deploy/k8s/overlays/demo
cp .env.example .env
openssl rand -base64 32   # run four times: Postgres, RabbitMQ, MinIO, Keycloak admin passwords
openssl rand -base64 24   # Grafana admin password
openssl rand -base64 32   # AUTH_JWT_SIGNING_KEY
```

Paste each result into `.env` in place of its `<generate-a-real-password-do-not-commit>` placeholder.
**This step cannot be delegated to a session** — `.env` never leaves the machine it was created on
(gitignored, per every other overlay's own convention), and a session generating "real" secrets on
your behalf inside a transcript that might be read back later defeats the entire point of the
distinction `.env.example`'s own header comment draws. Also edit `k8s/overlays/demo/tls.yaml`'s
`ClusterIssuer.spec.acme.email` to a real, reachable address before applying — the committed
placeholder (`letsencrypt-admin@golyakov.net`) is intentionally not one you should actually use as-is.

## 8. Apply the demo overlay **(session)**

```bash
kubectl apply -k k8s/overlays/demo
kubectl get pods -n ago-chat -w
```

Same rendering-without-a-cluster trick as `k8s-local.md` names for the local overlay, for reviewing
before applying: `kubectl kustomize k8s/overlays/demo`.

Watch for cert-manager's own `Certificate` resource going `Ready`:

```bash
kubectl get certificate ago-public-tls -n ago-chat -w
kubectl describe certificate ago-public-tls -n ago-chat   # if it stalls - shows the ACME order/challenge state
```

## 9. Migrations **(session)**

Same shape as `k8s-local.md`'s own already-verified sequence, unchanged (`AGO_CHAT_CONNECTION_STRING`
pointed at a port-forwarded Postgres, not a public one — Postgres itself is never routed through the
Gateway in this overlay, `gateway.yaml`'s own hostnames are chat/auth/console only):

```bash
kubectl port-forward svc/postgres 15432:5432 -n ago-chat
AGO_CHAT_CONNECTION_STRING="Host=localhost;Port=15432;Database=ago_chat;Username=ago;Password=<the-real-POSTGRES_PASSWORD-from-.env>" \
  dotnet ef database update -p ago-chat/src/Ago.Chat.Infrastructure.Postgres -s ago-chat/src/Ago.Chat.Infrastructure.Postgres
```

## 10. Seed the demo tenant **(session)**

`1-05`'s script targets `docker-compose`'s network by name and will not reach this cluster's Postgres
as written — same limitation `k8s-local.md` already documents for the local cluster, same fix:

```bash
kubectl exec -n ago-chat deploy/postgres -- psql -U ago -d ago_chat -c "<create-demo-tenant.sh's own SQL block>"
```

Keycloak's demo realm (`ago-chat`, seeded operator `demo-operator`/`demo-admin`) imports automatically
on Keycloak's own pod startup via `--import-realm` (`keycloak.yaml`) — no separate seeding step for
Keycloak itself, same as local.

## 11. Verify — from outside this network **(you, or a session with a way to reach the public internet from somewhere that isn't this VPS)**

This is the step `8-01`'s own Done-when insists on actually running, not asserting from the manifests:

```bash
curl -v https://chat.ago.golyakov.net/healthz/live      # expect: 200, a certificate chain with no warning
curl -v https://auth.ago.golyakov.net/realms/ago-chat    # expect: 200, Keycloak's realm discovery JSON
```

Then the same direct-grant pattern `local-dev.md`'s "Getting a working operator session locally"
section already documents, pointed at the public issuer instead of `127.0.0.1:8081`:

```bash
curl -s -X POST https://auth.ago.golyakov.net/realms/ago-chat/protocol/openid-connect/token \
  -d "grant_type=password&client_id=ago-console&username=demo-operator&password=demo-operator-password" \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
```

A token from this call should be accepted by `wss://chat.ago.golyakov.net/hubs/operator` (`dev-
harness.html`'s Operator pane, pointed at `?api=https://chat.ago.golyakov.net` — `5-01`'s own
`?api=` query-param support already handles a non-same-origin backend).

## Redeploying after a change

1. On the VPS: `git pull` in whichever of `ago-platform`/`ago-chat` changed, re-run the relevant part
   of step 6 (re-pack the platform feed only if `ago-platform` changed; always rebuild the `ago-chat`
   images whose source changed), re-import into containerd.
2. `kubectl rollout restart deployment/ago-chat-api deployment/ago-chat-worker deployment/ago-chat-webhooks -n ago-chat`
   as needed — `edge.md`'s own rolling-deploy sequence (`preStop`, drain, reconnect) applies unchanged;
   this is the same mechanism `3-06` already proved locally, now running on a real node.
3. If `k8s/overlays/demo/` itself changed (a new route, a new resource limit): `kubectl apply -k
   k8s/overlays/demo` again — kustomize + `kubectl apply` is declarative, so this is safe to re-run.

No CI/CD auto-redeploy exists for this environment, deliberately (`8-01`'s own "Out of scope") — this
manual sequence is the whole story until a later item decides differently.

## Known gaps, named plainly

- **HTTP is never redirected to HTTPS** — `gateway.yaml`'s own comment names this: a permanent
  redirect is a small addition (Gateway API's `RequestRedirect` HTTPRoute filter) this item did not
  add without a live server to verify it against. A visitor hitting `http://chat.ago.golyakov.net`
  today gets a 404 from the Gateway (no HTTPRoute matches the `http` listener), not a redirect.
- **Keycloak's realm still has `sslRequired: "none"`** (`k8s/base/keycloak-realm-import.json`) —
  inherited unchanged from the local realm import, per this item's own instruction to reuse `5-05`'s
  mechanism rather than invent a new one. Tightening this to `external` (require TLS for
  non-private-network requests) is a real, deferred hardening step, not evaluated live against this
  deployment's own `--proxy-headers=xforwarded` config in this session.
- **Keycloak runs in `start-dev` mode publicly**, not its own hardened `start` production mode —
  `adr/0026`'s own "Consequences" section names this a deliberate, stated gap: a demo IdP for one
  seeded operator, not a production identity provider.
- **`console.ago.golyakov.net`'s `HTTPRoute` has no real backend yet** — `ago-console`'s Service is
  `8-02`'s own job. Requests to this hostname will fail until that item lands and creates it.
- **`demo-shop1`/`demo-shop2.ago.golyakov.net` have DNS records reserved but no Gateway resources at
  all** — same reason, `8-02`'s own scope.
- **The `k3s ctr -n k8s.io images import` step (§6) is unverified** — the one command in this runbook
  this session is least confident about, named explicitly rather than presented as proven.
- **One node, still** — `k8s-local.md`'s own "Known limits" (no pod anti-affinity, no real node-drain
  or network-partition testing) carry over unchanged to this real deployment. `nfr.md`'s "not an
  uptime SLA — this is a demo cluster" framing is the bar this deployment is held to, not a new one
  invented here.

## Troubleshooting

- **NGF's data-plane pod never gets traffic on `:80`/`:443`**: confirm `--disable traefik` actually
  took (`sudo k3s kubectl get pods -n kube-system | grep traefik` should show nothing) — a Traefik
  left running from a default install would already be bound to those ports.
- **cert-manager's `Certificate` stays `False`**: `kubectl describe certificate ago-public-tls -n
  ago-chat` shows the ACME order; a stuck HTTP-01 challenge almost always means DNS (step 2) has not
  propagated yet, or the `:80` listener (`gateway.yaml`) is not actually reachable from the public
  internet (a cloud firewall/security-group rule blocking port 80 would look exactly like this).
- **`k8s-local.md`'s own WSL2/cgroup-v1 troubleshooting notes do not apply here** — those are specific
  to Docker Desktop's own WSL2-backed VM, not a real Ubuntu VPS. If the k3s service itself fails to
  start, check `sudo journalctl -u k3s -f` instead.
