# Runbook: public deployment (k3s VPS)

> **Status: fully live and verified end to end** (2026-08-24) — every step below actually ran against
> the real VPS, in order, in the same session. This runbook was originally written by a session with
> no VPS to deploy to ("design only" as of its first version); the managing session then executed it
> live once the author provisioned the real server, finding and fixing seven real bugs along the way
> (all documented in place, below, at the step each was found). Final external check: a real
> `POST .../token` direct-grant call against `https://auth.reserve-me.ru` returned a real Keycloak
> JWT, and that token was accepted by `https://chat.reserve-me.ru/api/v1/operators/me` with `200` —
> the whole chain, DNS through TLS through Keycloak through the API, proven live, not asserted.
> `adr/0026` (including its own "Post-decision update") has the reasoning behind every choice named
> here; this file is the "how".

Every step below is marked **(you)** if it can only be done by the author by hand — buying the VPS,
touching a domain registrar's panel, generating and holding real secret values — or **(session)** if a
Claude Code session with SSH access to the real VPS can run it directly.

## 1. Provision the VPS **(you) — done 2026-08-24**

**Actually purchased**: Fornex, "Cloud NVMe 6" tier (4 vCPU / **6 GB RAM** / 80 GB NVMe, Russia
location, Ubuntu 24.04 LTS) — not the Timeweb Cloud MSK 80 originally recommended below; the author
independently shopped and bought before applying the recommendation verbatim. `adr/0026`'s own
"Post-decision update" has the real memory-headroom tradeoff of 6 GB vs. the recommended 8 GB, accepted
knowingly, not silently. Public IPv4: **`217.177.74.184`**.

*(Original recommendation, kept for the reasoning trail: Timeweb Cloud MSK 80, 4 vCPU / 8 GB RAM /
80 GB NVMe, Moscow region, ≈1 800 ₽/month, annual billing — Russian-issued cards work directly with
Timeweb; Fornex, a Spain-registered provider with a Russia-region line, also worked for the author's
own card without a third-party intermediary, per `adr/0026`'s updated payment-constraint note.)*

**SSH hardening — done and verified 2026-08-24**: a non-root sudo user `ago` was created with
`NOPASSWD:ALL` (a personal single-admin demo box, not multi-tenant — password-gated sudo was skipped
deliberately) and the session's own SSH public key installed to its `authorized_keys`; root SSH login
and password authentication were then disabled in `/etc/ssh/sshd_config`
(`PermitRootLogin no`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`), **verified live
before reporting done**: `ago` login confirmed working from the new key location, *then* `root` login
confirmed refused (`Permission denied (publickey,password)`) — in that order, specifically to avoid a
lockout. The private key lives at `~/.ssh/ago-vps-ed25519` on the machine running the managing
session — not committed to any repository (`repositories.md`: "no secrets, ever").

## 2. DNS records **(you) — done 2026-08-24**

Domain: **`reserve-me.ru`**, bought via reg.ru specifically for this deployment (not a subdomain of a
personal domain — see `adr/0026`'s "Post-decision update" for the full account of the change from the
original `*.ago.golyakov.net` plan). Configured at reg.ru as: apex (`@`) as an `A` record to the VPS
IP (so the domain itself is reachable, not only its subdomains), the five subdomains below as `CNAME`
records pointing at the apex rather than five separate `A` records (the author's own established
pattern — one record to update if the IP ever changes, instead of five; `CNAME` is not valid at the
apex itself, which is exactly why `@` stays `A`), and the registrar's own default `www` record left
untouched (unused today, may be repurposed later, doesn't conflict with anything here):

| Host | Type | Value |
|---|---|---|
| `reserve-me.ru` (apex) | A | `217.177.74.184` |
| `chat.reserve-me.ru` | CNAME | `reserve-me.ru` |
| `auth.reserve-me.ru` | CNAME | `reserve-me.ru` |
| `console.reserve-me.ru` | CNAME | `reserve-me.ru` |
| `demo-shop1.reserve-me.ru` | CNAME | `reserve-me.ru` (reserved now, unrouted until `8-02`) |
| `demo-shop2.reserve-me.ru` | CNAME | `reserve-me.ru` (reserved now, unrouted until `8-02`) |

**Propagation, checked live** (2026-08-24, against `8.8.8.8` to bypass any local cache):
`chat.`/`auth.`/`console.reserve-me.ru` resolved to `217.177.74.184` within minutes of being added —
the three hostnames `tls.yaml`'s `Certificate` actually needs for step 6's HTTP-01 challenge.
`demo-shop1`/`demo-shop2`/the bare apex had not resolved yet at last check — not a blocker (neither is
routed by any `HTTPRoute` yet; both are `8-02`'s own future work), left to finish propagating in the
background.

## 3. Install k3s, disabling the bundled Traefik **(session) — done 2026-08-24**

```bash
ssh -i ~/.ssh/ago-vps-ed25519 ago@217.177.74.184
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

**Real gotcha found live**: `kubectl kustomize <remote-github-URL>` (a `git fetch --depth=1` under the
hood) hit kustomize's own hardcoded 27s timeout on this VPS's network path to GitHub — not blocked
(`git ls-remote` against the same repo returned in under a second), just genuinely slower than that
timeout for an actual data-transfer `git fetch`/`clone` (a real `git clone --depth=1` of the same repo
took ~39s end to end). No VPN or proxy needed — worked around by `git clone`-ing once to `/tmp` and
running `kubectl kustomize <local-path>` instead of the remote URL, which has no timeout at all since
it's local disk. This same workaround is folded into step 4 below.

## 4. Gateway API CRDs + NGINX Gateway Fabric **(session) — done 2026-08-24**

Identical to `k8s-local.md`'s own already-verified three steps, with one addition (the local-clone
workaround from step 3's own gotcha, above) for the CRD step specifically:

```bash
git clone --depth=1 --branch v2.6.7 https://github.com/nginx/nginx-gateway-fabric.git /tmp/ngf
kubectl kustomize /tmp/ngf/config/crd/gateway-api/standard | kubectl apply -f -
kubectl create namespace nginx-gateway
kubectl apply --server-side -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v2.6.7/deploy/crds.yaml
kubectl apply -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v2.6.7/deploy/default/deploy.yaml
kubectl get pods -n nginx-gateway   # one Completed (cert generator), one 1/1 Running (controller)
```

`raw.githubusercontent.com` fetches (the two `kubectl apply -f <url>` calls) were never slow — only
the git-protocol remote-kustomize-base fetch was, so only that one call needed the workaround.

On a real cloud VPS (unlike Docker Desktop) the NGF data-plane `LoadBalancer` Service will not get an
external IP from a cloud load-balancer controller, since none is installed — that is expected on a
single k3s node with no cloud provider integration. It still binds the node's own `:80`/`:443` via
k3s's built-in `ServiceLB` (klipper-lb), which is what DNS in step 2 is actually pointing at.

## 5. cert-manager **(session) — done 2026-08-24**

Not covered by `k8s-local.md` at all — the local overlay needs no real certificate (NGF's own default
install self-signs for its control-plane webhook, `k8s-local.md`'s own note on that). Install
cert-manager the same static-manifest way NGF itself was installed:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl get pods -n cert-manager -w   # three pods (controller, webhook, cainjector), all 1/1 Running
```

**Real bug found live, one more step needed here**: cert-manager's plain static-manifest install does
**not** enable Gateway API support by default — the `gatewayHTTPRoute` ACME solver `tls.yaml` uses
(step 8) failed every challenge with `couldn't Present challenge ... gateway api is not enabled` until
the controller was told explicitly to support it:

```bash
kubectl patch deployment cert-manager -n cert-manager --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--enable-gateway-api=true"}]'
kubectl get pods -n cert-manager -l app.kubernetes.io/component=controller   # confirm it restarted 1/1
```

This is a one-time cluster-level flag (persists across every future `Certificate`, not just this
overlay's own) — do it once, right after installing cert-manager, before ever applying an overlay that
uses the `gatewayHTTPRoute` solver.

## 6. Get source and build images on the VPS **(session) — done 2026-08-24**

`adr/0026`'s "Image delivery" decision: no registry, build directly on the node, import straight into
k3s's own containerd. Needs the .NET SDK and Docker installed on the VPS in addition to k3s itself
(`sudo apt-get install -y dotnet-sdk-10.0 docker.io` on Ubuntu, or follow each project's own upstream
install docs if the Ubuntu package is behind):

```bash
git clone --depth=1 https://github.com/<author>/ago-platform.git
git clone --depth=1 https://github.com/<author>/ago-chat.git
git clone --depth=1 https://github.com/<author>/ago-deploy.git

# CHANGELOG.md is the real source of truth for the published version (adr the ago-platform CI
# workflow itself uses) - Directory.Build.props's own <Version> is a stale placeholder packing
# ignores in CI. Real bug hit live: packing without -p:Version pulled 0.2.2 from that stale
# placeholder, while ago-chat's Directory.Packages.props pins >= 0.14.0 - NU1102, every restore
# failed, until packed with the CHANGELOG-derived version explicitly, matching CI exactly:
cd ago-platform
VERSION=$(grep -m1 '^## \[' CHANGELOG.md | sed -E 's/^## \[([^]]+)\].*/\1/')
dotnet pack Ago.Platform.slnx -c Release -o ../ago-deploy/.nuget-feed -p:Version=$VERSION
cd ..

# Real gotcha: docker.io's own Ubuntu package ships without BuildKit's buildx component, and
# build-images.sh's --build-context flag needs it - `unknown flag: --build-context` until installed:
sudo apt-get install -y docker-buildx   # NOT docker-buildx-plugin - that package name doesn't exist

chmod +x ago-deploy/k8s/build-images.sh   # git clone does not reliably preserve the +x bit
cd ago-chat
CHAT_REPO=. NUGET_FEED=../ago-deploy/.nuget-feed DOCKER_BUILDKIT=1 ../ago-deploy/k8s/build-images.sh
cd ..

for img in ago-chat-api ago-chat-worker ago-chat-webhooks; do
  docker save "${img}:local" | sudo k3s ctr -n k8s.io images import -
done
sudo k3s ctr -n k8s.io images ls | grep ago-chat   # confirms all three landed in the namespace kubelet reads from
```

`build-images.sh` itself needed no changes — same script, same `:local` tags, same
`CHAT_REPO`/`NUGET_FEED` environment variables it already supports, just run from a different working
directory (plus `DOCKER_BUILDKIT=1` and the one-time `chmod +x`, both environment/host-level, not
script changes). The `-n k8s.io` namespace flag on `k3s ctr images import` matters and **is now
live-verified**: k3s's embedded containerd keeps kubelet-visible images in the `k8s.io` namespace
specifically, not `ctr`'s own default namespace — importing without `-n k8s.io` would leave the image
invisible to the kubelet.

## 7. Generate real secrets **(you, or a session per the author's own explicit instruction) — done 2026-08-24**

```bash
cd ago-deploy/k8s/overlays/demo
cp .env.example .env
```

Then, for each `<generate-a-real-...-do-not-commit>` placeholder, generate and substitute a real value
**without ever printing it to a terminal/transcript that persists** - `openssl rand -base64 24`/`32`
piped straight into `sed -i` on the file, never `echo`'d:

```bash
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -base64 24)|" .env
# ...repeat for RABBITMQ_PASSWORD, MINIO_ROOT_PASSWORD, KEYCLOAK_ADMIN_PASSWORD, GRAFANA_ADMIN_PASSWORD (base64 -24),
# and AUTH_JWT_SIGNING_KEY (base64 -32)
chmod 600 .env
```

Done live by the managing session in this pass, on the author's own explicit request mid-conversation
- the original text here said this step "cannot be delegated to a session," reasoning that a session
printing real secrets into its own transcript defeats the point of treating them as real. That
reasoning still holds; the actual risk it warns about is the values appearing in the session's own
visible output, not which hands type the command - piping `openssl` straight into `sed` avoids that
specifically, so a session generating them this way, without ever echoing a value, satisfies the same
intent this note originally protected. `tls.yaml`'s `ClusterIssuer.spec.acme.email` (a non-secret,
role-style address under the domain itself, never a personal inbox per `repositories.md`) was left as
committed - correct as shipped, no edit needed.

## 8. Apply the demo overlay **(session) — done 2026-08-24, with two real bugs found and fixed live**

```bash
kubectl apply -k k8s/overlays/demo
kubectl get pods -n ago-chat -w
```

Same rendering-without-a-cluster trick as `k8s-local.md` names for the local overlay, for reviewing
before applying: `kubectl kustomize k8s/overlays/demo`.

**Real bug #1 — `keycloak` got `ErrImageNeverPull`**: the demo overlay's `imagePullPolicy: Never`
patch had been copied onto `keycloak`'s own Deployment by pattern-matching the three `ago-chat-*`
entries, but `keycloak` runs the real upstream `quay.io/keycloak/keycloak` image, never built locally
- there was never a `keycloak:local` tag to import. Fixed by removing that one patch op (kept for the
three `ago-chat-*` Deployments, which genuinely are built-and-imported locally).

**Real bug #2 — `keycloak` deadlocked on its own embedded H2 database during any rollout**: applying
bug #1's fix triggered a rollout, which (with the default `RollingUpdate` strategy) briefly ran the
old and new pod together - Keycloak's `start-dev` mode uses its embedded H2 database by default, which
only allows one process to hold the file open at a time, so both pods deadlocked fighting over the
same exclusive lock and neither ever became `Ready`. Fixed in `k8s/base/keycloak.yaml`: `strategy: {
type: Recreate }` (old pod terminated before the new one starts - the correct strategy for any
single-replica, exclusive-lock-backed workload).

**Real bug #3 (found right after #2's own fix rolled out) — liveness probe too aggressive for a real
first boot**: Quarkus's own build-time augmentation alone took ~23s on this VPS (measured live), and
the pod still had a Liquibase schema migration and `--import-realm` left to do after that - well past
the original `livenessProbe.initialDelaySeconds: 20`, so Kubernetes killed the pod mid-startup
(`exit 143`/SIGTERM, not an internal crash) on every single attempt. A long-running local-dev Keycloak
pod never re-exercises this path (it boots once, stays up for weeks), so the gap was never hit before
a real cold cluster start. Fixed in `k8s/base/keycloak.yaml`: `initialDelaySeconds` raised to 60s
(readiness) / 90s (liveness), liveness `failureThreshold` widened to 6.

After all three fixes: `keycloak` reached `1/1 Running`, `0` restarts, in well under two minutes from
a cold `Recreate`.

Watch for cert-manager's own `Certificate` resource going `Ready` (needs step 5's own
`--enable-gateway-api=true` patch applied first, or every challenge fails with `gateway api is not
enabled` - see step 5 above):

```bash
kubectl get certificate ago-public-tls -n ago-chat -w
kubectl describe certificate ago-public-tls -n ago-chat   # if it stalls - shows the ACME order/challenge state
kubectl get challenges -n ago-chat                        # per-hostname HTTP-01 challenge state
```

**Live result**: all four hostnames' HTTP-01 challenges resolved within about a minute of the
cert-manager Gateway API flag being applied; `ago-public-tls` went `READY: True`.

## 9. Migrations **(session) — done 2026-08-24**

Same shape as `k8s-local.md`'s own already-verified sequence (`AGO_CHAT_CONNECTION_STRING` pointed at
a port-forwarded Postgres, not a public one — Postgres itself is never routed through the Gateway in
this overlay, `gateway.yaml`'s own hostnames are chat/auth/console/grafana only), run from the VPS
itself (simpler than tunnelling the port-forward out to a separate machine) with the real
`POSTGRES_PASSWORD` read directly from the live cluster's own Secret and never printed:

```bash
kubectl port-forward svc/postgres 15432:5432 -n ago-chat &

dotnet tool install --global dotnet-ef   # not present by default - real gap, install once
export PATH="$PATH:$HOME/.dotnet/tools"

# ago-chat's own committed nuget.config points "ago-local" at a Windows host path (C:\git\ago\
# .nuget-feed) that does not exist on this Linux VPS - a real gap for any restore run outside the
# Dockerfile (which uses its own nuget.docker.config, pointed at a Buildx mount path that doesn't
# exist outside a build either). Neither existing config file works unmodified here; write a third,
# minimal one for this one-off host-side restore:
cat > /tmp/nuget.migrations.config << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="ago-local" value="/home/ago/ago/ago-deploy/.nuget-feed" />
  </packageSources>
  <packageSourceMapping>
    <packageSource key="ago-local"><package pattern="Ago.Platform.*" /></packageSource>
    <packageSource key="nuget.org"><package pattern="*" /></packageSource>
  </packageSourceMapping>
</configuration>
EOF
cd ago-chat
dotnet restore src/Ago.Chat.Infrastructure.Postgres/Ago.Chat.Infrastructure.Postgres.csproj \
  --configfile /tmp/nuget.migrations.config

# kustomize's secretGenerator hash-suffixes the Secret name (e.g. infra-credentials-2b77c6k587) so it
# changes on every content edit - look it up by its own stable label instead of hardcoding the hash:
SECRET_NAME=$(kubectl get secret -n ago-chat -o name | grep infra-credentials | cut -d/ -f2)
PGPW=$(kubectl get secret "$SECRET_NAME" -n ago-chat -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
AGO_CHAT_CONNECTION_STRING="Host=localhost;Port=15432;Database=ago_chat;Username=ago;Password=${PGPW}" \
  dotnet ef database update -p src/Ago.Chat.Infrastructure.Postgres -s src/Ago.Chat.Infrastructure.Postgres
```

All fourteen migrations (`Stage1CreateChatSchema` through `Stage7AddOutboxTraceContext`) applied
cleanly in one run.

## 10. Seed the demo tenant **(session) — done 2026-08-24**

`1-05`'s script targets `docker-compose`'s network by name and will not reach this cluster's Postgres
as written — same limitation `k8s-local.md` already documents for the local cluster, same fix: the
script's own SQL block (fixed, well-known UUIDs and site/operator/role names — none of it is a
secret, per the script's own header comment), run via `kubectl exec` piping a heredoc file rather than
a single `-c "..."` string (simpler quoting for a multi-statement block with embedded single quotes):

```bash
# Build /tmp/seed-demo.sql from deploy/seed/create-demo-tenant.sh's own SQL heredoc (same statements,
# same fixed ids), then:
kubectl exec -i -n ago-chat deploy/postgres -- psql -U ago -d ago_chat -v ON_ERROR_STOP=1 < /tmp/seed-demo.sql
```

Keycloak's demo realm (`ago-chat`, seeded operator `demo-operator`/`demo-admin`) imports automatically
on Keycloak's own pod startup via `--import-realm` (`keycloak.yaml`) — no separate seeding step for
Keycloak itself, same as local.

## 11. Verify — from outside this network **(you, or a session with a way to reach the public internet from somewhere that isn't this VPS) — done and passed, 2026-08-24**

This is the step `8-01`'s own Done-when insists on actually running, not asserting from the manifests
— **run for real, from a machine other than the VPS itself, every result below is a real live
response, not an expectation**:

```bash
curl -v https://chat.reserve-me.ru/healthz/live      # -> 200, "Healthy", valid cert chain, no warning
curl -v https://auth.reserve-me.ru/realms/ago-chat    # -> 200, Keycloak's real realm discovery JSON,
                                                       #    token-service correctly reads
                                                       #    https://auth.reserve-me.ru/... (not the
                                                       #    internal Service address - confirms the
                                                       #    keycloak.yaml --hostname patch is correct)
```

Then the same direct-grant pattern `local-dev.md`'s "Getting a working operator session locally"
section already documents, pointed at the public issuer instead of `127.0.0.1:8081`:

```bash
TOKEN=$(curl -s -X POST https://auth.reserve-me.ru/realms/ago-chat/protocol/openid-connect/token \
  -d "grant_type=password&client_id=ago-console&username=demo-operator&password=demo-operator-password" \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
curl -s -o /dev/null -w "%{http_code}\n" https://chat.reserve-me.ru/api/v1/operators/me \
  -H "Authorization: Bearer $TOKEN"   # -> 200
```

**All four checks returned exactly what they should, live**: the full chain — public DNS, a real
Let's Encrypt certificate, Keycloak issuing a real signed JWT under the public issuer, and
`Ago.Chat.Api` accepting that JWT and resolving it to the seeded demo operator — works end to end. A
token from this call should also be accepted by `wss://chat.reserve-me.ru/hubs/operator` (`dev-
harness.html`'s Operator pane, pointed at `?api=https://chat.reserve-me.ru` — `5-01`'s own
`?api=` query-param support already handles a non-same-origin backend) — not separately re-verified in
this pass beyond the REST call above, since the REST call already proves the identical JWT-validation
path the hub's own connection negotiation uses.

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
  add without a live server to verify it against. A visitor hitting `http://chat.reserve-me.ru`
  today gets a 404 from the Gateway (no HTTPRoute matches the `http` listener), not a redirect.
- **Keycloak's realm still has `sslRequired: "none"`** (`k8s/base/keycloak-realm-import.json`) —
  inherited unchanged from the local realm import, per this item's own instruction to reuse `5-05`'s
  mechanism rather than invent a new one. Tightening this to `external` (require TLS for
  non-private-network requests) is a real, deferred hardening step, not evaluated live against this
  deployment's own `--proxy-headers=xforwarded` config in this session.
- **Keycloak runs in `start-dev` mode publicly**, not its own hardened `start` production mode —
  `adr/0026`'s own "Consequences" section names this a deliberate, stated gap: a demo IdP for one
  seeded operator, not a production identity provider.
- **`console.reserve-me.ru`'s `HTTPRoute` has no real backend yet** — `ago-console`'s Service is
  `8-02`'s own job. Requests to this hostname will fail until that item lands and creates it.
- **`demo-shop1`/`demo-shop2.reserve-me.ru` have DNS records reserved but no Gateway resources at
  all** — same reason, `8-02`'s own scope.
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
