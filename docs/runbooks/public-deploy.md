# Runbook: public deployment (k3s VPS)

> **This is the record of the first bring-up, not the procedure for updating.** Every step below is
> marked with the date it was done, because each was done once. To redeploy, use
> [`redeploy.md`](redeploy.md) and the script it points at.
>
> The distinction is not pedantry: on 2026-08-25 a redeploy followed this file, skipped step 9
> (migrations) because a step marked "done" does not read like a step, and left the API running
> against a schema three migrations behind. Every page still returned 200 while every query loading a
> `Site` failed. This file stays as it is — it is a good record, and rewriting it into a procedure
> would lose what it records — and `redeploy.md` carries the repeatable sequence instead.

> **Status: fully live and verified end to end** (2026-08-24) — every step below, including step 12
> and step 13, has actually run against the real VPS. This runbook was originally written by a
> session with no VPS to deploy to ("design only" as of its first version); the managing session then
> executed it live once the author provisioned the real server, finding and fixing real bugs along the
> way (documented in place, below, at the step each was found — nine in total across steps 1-13, one
> of them a real product bug in `ago-widget` fixed as its own backlog item, `5-12`, not folded in
> silently). Final external check, repeated after each of steps 12 and 13: a real visitor sends a
> message through the public widget, it lands in Postgres, and the operator console (a real Keycloak
> login, a different browser context per operator) sees and answers it — the whole chain, DNS through
> TLS through Keycloak through the API through the realtime hub, proven live, not asserted. `adr/0026`
> (including its own "Post-decision update") has the reasoning behind every choice named here; this
> file is the "how".

Every step below is marked **(you)** if it can only be done by the author by hand — buying the VPS,
touching a domain registrar's panel, generating and holding real secret values — or **(session)** if a
Claude Code session with SSH access to the real VPS can run it directly.

## 1. Provision the VPS **(you) — done 2026-08-24**

**Actually purchased**: Fornex, "Cloud NVMe 6" tier (4 vCPU / **6 GB RAM** / 80 GB NVMe, Russia
location, Ubuntu 24.04 LTS) — not the Timeweb Cloud MSK 80 originally recommended below; the author
independently shopped and bought before applying the recommendation verbatim. `adr/0026`'s own
"Post-decision update" has the real memory-headroom tradeoff of 6 GB vs. the recommended 8 GB, accepted
knowingly, not silently. Public IPv4: **`<node-ip>`** — see the note below.
> **The node's public IPv4 is deliberately not written here** (2026-08-25). `CLAUDE.md`'s standing rule
> is "never write a secret, a token, a real endpoint or anyone's data into any of these repositories",
> and a node address is an endpoint. It is derivable from DNS, so removing it recovers no secrecy —
> what it does is stop this repository from handing over the last step, and stop the rule from being
> one this project keeps everywhere except where it was inconvenient. It is also still in this
> repository's git history, which this change does not and cannot undo.
>
> The real value lives in the private `ago-business` repository. Everywhere below, `<node-ip>` means it.


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
lockout.

> **Correction, 2026-08-25.** One of those three did not take. `PasswordAuthentication no` sits at line
> 66 of `/etc/ssh/sshd_config`, but line 12 is `Include /etc/ssh/sshd_config.d/*.conf`, and Ubuntu's
> `50-cloud-init.conf` sets `PasswordAuthentication yes`. OpenSSH keeps the **first** value it obtains,
> and the include is read first, so the edit below it never applied. `sshd -T` — the authoritative
> view — reports `passwordauthentication yes` today.
>
> The evidence was in this paragraph the whole time: `Permission denied (publickey,password)` names
> the methods still on offer. Had the setting taken, that message would have read `(publickey)`.
>
> **Not exploitable as it stands**: `ago`'s password is locked (`passwd -S` → `L`) and `root` is barred
> by `PermitRootLogin no`, so no account can be logged into by password. It is a missing layer rather
> than an open door — and the box logged 2018 failed password attempts in 24 hours, so it is a layer
> under active probing. `17-05` owns the fix, which must edit the drop-in rather than the main file and
> verify with `sshd -T` rather than by reading the file that lost.
>
> The lesson worth keeping: verifying a hardening change by observing a *refusal* proves the refusal,
> not the reason for it. `sshd -T` was always the check that would have caught this. The private key lives at `~/.ssh/ago-vps-ed25519` on the machine running the managing
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
| `reserve-me.ru` (apex) | A | `<node-ip>` |
| `chat.reserve-me.ru` | CNAME | `reserve-me.ru` |
| `auth.reserve-me.ru` | CNAME | `reserve-me.ru` |
| `console.reserve-me.ru` | CNAME | `reserve-me.ru` |
| `demo-shop1.reserve-me.ru` | CNAME | `reserve-me.ru` (reserved now, unrouted until `8-02`) |
| `demo-shop2.reserve-me.ru` | CNAME | `reserve-me.ru` (reserved now, unrouted until `8-02`) |

**Propagation, checked live** (2026-08-24, against `8.8.8.8` to bypass any local cache):
`chat.`/`auth.`/`console.reserve-me.ru` resolved to `<node-ip>` within minutes of being added —
the three hostnames `tls.yaml`'s `Certificate` actually needs for step 6's HTTP-01 challenge.
`demo-shop1`/`demo-shop2`/the bare apex had not resolved yet at last check — not a blocker (neither is
routed by any `HTTPRoute` yet; both are `8-02`'s own future work), left to finish propagating in the
background.

## 3. Install k3s, disabling the bundled Traefik **(session) — done 2026-08-24**

```bash
ssh -i ~/.ssh/ago-vps-ed25519 ago@<node-ip>
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
# ...repeat for RABBITMQ_PASSWORD, MINIO_ROOT_PASSWORD, KEYCLOAK_ADMIN_PASSWORD, GRAFANA_ADMIN_PASSWORD,
# KEYCLOAK_DB_PASSWORD (15-01 - Keycloak's own Postgres role) (all base64 -24),
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

## 12. Publish the console and the public demo page **(session) — done 2026-08-24, one real product bug found and fixed live**

`8-02`'s own scope: `console.reserve-me.ru`'s `HTTPRoute` (step 8, `gateway.yaml`) has had no real
backend behind it since it was created — this closes that gap, and routes a new
`demo-shop1.reserve-me.ru` for the widget's own public demo page. Same shape as step 6's image
delivery (`adr/0026`: no registry, build straight on the VPS, import into k3s's own containerd) —
**a different mechanism from step 6/redeploying-after-a-change below, deliberately not folded into
either**: `ago-console`/`ago-widget` are static frontend bundles behind nginx, each with their own
`Dockerfile` in their own repository, not another `Ago.Chat.*` .NET host `build-images.sh` already
knows how to build.

```bash
# alongside the ago-platform/ago-chat/ago-deploy clones step 6 already made:
git clone --depth=1 https://github.com/<author>/ago-console.git
git clone --depth=1 https://github.com/<author>/ago-widget.git

chmod +x ago-deploy/k8s/build-static-images.sh   # git clone does not reliably preserve the +x bit
cd ago-deploy/k8s
CONSOLE_REPO=../../ago-console WIDGET_REPO=../../ago-widget \
  AGO_API_BASE_URL=https://chat.reserve-me.ru ./build-static-images.sh
cd ../..

for img in ago-console ago-demo-shop1; do
  docker save "${img}:local" | sudo k3s ctr -n k8s.io images import -
done
sudo k3s ctr -n k8s.io images ls | grep -E 'ago-console|ago-demo-shop1'   # confirms both landed
```

```bash
cd ago-deploy/k8s
kubectl apply -k overlays/demo
kubectl get pods -n ago-chat -l 'app in (ago-console,ago-demo-shop1)' -w
```

`kubectl apply` is declarative — this also picks up `tls.yaml`'s new `demo-shop1.reserve-me.ru` SAN
and `gateway.yaml`'s new listener/`HTTPRoute` from the same overlay, alongside the two new
Deployments/Services. Watch the existing `Certificate` re-issue in place for the added SAN (`tls.yaml`'s
own comment: this is one certificate gaining a fifth hostname, not a fresh multi-SAN request replaying
every already-passed HTTP-01 challenge):

```bash
kubectl get certificate ago-public-tls -n ago-chat -w
```

**CORS**: the demo site's `allowed_origins` needs the two new public origins added — exact SQL,
matching `deploy/seed/create-demo-tenant.sh`'s own `on conflict (id) do update` shape for this same
column (extends the array, does not drop the existing `localhost` entries):

```bash
cat > /tmp/allowed-origins.sql << 'SQL'
insert into sites (id, public_key, allowed_origins)
values (
  '00000000-0000-0000-0000-000000000001',
  'demo_site',
  array[
    'http://localhost:8080',
    'http://localhost:5173',
    'https://demo-shop1.reserve-me.ru',
    'https://console.reserve-me.ru'
  ]::text[]
)
on conflict (id) do update set allowed_origins = excluded.allowed_origins;
SQL
kubectl exec -i -n ago-chat deploy/postgres -- psql -U ago -d ago_chat -v ON_ERROR_STOP=1 < /tmp/allowed-origins.sql
```

Then flush the CORS-origin cache — `local-dev.md`'s own "Running the console locally" section already
documents why this is a separate, required step: `5-01`'s per-site CORS policy caches
`allowed_origins` in Redis with no event-driven invalidation wired up yet, so a change to the row
alone is not enough:

```bash
# redis.yaml's Service carries no auth (same as the local overlay) - nothing to source first.
kubectl exec -i -n ago-chat deploy/redis -- redis-cli FLUSHALL
```

**Keycloak's `ago-console` client registration** needed no separate live action: git history shows the
domain-rename commit that added `https://console.reserve-me.ru/*`/`https://console.reserve-me.ru` to
the `ago-console` client's `redirectUris`/`webOrigins` (`6efb4cf`, "feat(8-01): domain changed to
reserve-me.ru") landed *before* the fixes that got Keycloak's pod to first reach `Running` on the live
VPS (step 8's `66feeec`/`90c4016`) — so the very first successful `--import-realm` on the real cluster
already saw the updated file. Confirmed live with a real console login, not just reasoned about.

**~~Correction to an assumption this section originally stated as fact~~ — the correction was itself
wrong, and `15-01` found out why (2026-08-25).** This section used to record `8-05`'s live finding that
editing `keycloak-realm-import.json` to add a brand-new user and restarting the pod **does** add that
user to an already-provisioned realm. The observation was real; the conclusion drawn from it was not.
The reason the new user appeared is that this Keycloak had no persistent store at all — the restart
destroyed its embedded H2 database, so the realm did not exist any more and `--import-realm` rebuilt
it from scratch, new entity and all. What looked like "the import merges into a live realm" was "the
live realm is gone every time you look away".

Retested directly under `15-01`'s persistent store: a new realm role *and* a changed
`accessTokenLifespan` were added to the file, the pod was restarted, and **neither reached the realm**.
Keycloak's own log is unambiguous about it — `Strategy: IGNORE_EXISTING` / `Realm 'ago-chat' already
exists. Import skipped`. `Import skipped` means the whole file, not just the realm's own attributes.
`adr/0036` has the mechanism; `k8s/apply-realm-settings.sh` is how realm-level settings reach a live
realm now, and clients/roles/groups need their own `kcadm.sh` call.

**Verify — from outside this network, same bar as step 11**: load `https://demo-shop1.reserve-me.ru`,
send a message through the widget in the corner; from a second tab, `https://console.reserve-me.ru`
should redirect to the public Keycloak login, `demo-operator`/`demo-operator-password` should log in,
and the message sent above should be visible in the queue and answerable, with the reply arriving back
on the demo page live — `8-02`'s own Done-when bar. **This did not pass on the first real attempt**:
the widget's own visitor-side send failed every time against the real server, silently on the wire.
Root-caused and fixed as its own backlog item (`5-12`, not folded into this deployment item silently,
matching `5-11`'s own precedent) — a widget application bug (a missing `clientMessageId` argument on
the hub invocation), not a deployment or infrastructure issue. A one-time, self-resolving red herring
came up along the way too: right after this step's own `kubectl apply`, a handful of WebSocket
connections dropped within seconds of opening, traced to NGINX Gateway Fabric reloading its data-plane
nginx config in response to the TLS Secret changing underneath it (a normal reload, which does not
preserve in-flight long-lived connections) — confirmed transient by testing again once the config
settled, not a structural Gateway problem, ruled out before `5-12`'s real cause was found. After the
`5-12` fix was built, deployed, and re-verified: a real message, sent through the real widget, landed
in Postgres and was answered by the real operator console — passed, not asserted.

## 13. A second demo tenant, and the permanent HTTP→HTTPS redirect **(session) — done 2026-08-24**

`8-05`'s own scope: a second, fully independent demo tenant (`demo-shop2.reserve-me.ru`) to show
tenant isolation live, plus the permanent HTTP→HTTPS redirect step 12's own predecessor deliberately
left out for lack of a live server to verify it against.

```bash
cd ago-widget && git pull   # picks up public-demo-2/, Dockerfile's DEMO_PAGE_DIR arg
cd ../ago-deploy && git pull   # picks up demo-shop2-static.yaml, gateway/tls changes

cd k8s
CONSOLE_REPO=../../ago-console WIDGET_REPO=../../ago-widget \
  AGO_API_BASE_URL=https://chat.reserve-me.ru ./build-static-images.sh   # now builds all three images
docker save ago-demo-shop2:local | sudo k3s ctr -n k8s.io images import -

kubectl apply -k overlays/demo
kubectl get certificate ago-public-tls -n ago-chat -w   # re-issues in place with the sixth SAN
```

**CORS** for the second site (`create-demo-tenant.sh`'s own `on conflict (id) do update` shape, same
as step 12's):

```bash
cat > /tmp/site2-seed.sql << 'SQL'
insert into sites (id, public_key, allowed_origins)
values (
  '00000000-0000-0000-0000-000000000008',
  'demo_site2',
  array['https://demo-shop2.reserve-me.ru', 'https://console.reserve-me.ru']::text[]
)
on conflict (id) do update set allowed_origins = excluded.allowed_origins;

insert into operators (id, site_id, status, capacity, external_subject_id)
values ('00000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000008', 'Online', 5, '00000000-0000-0000-0000-00000000000b')
on conflict (id) do update set external_subject_id = excluded.external_subject_id;

insert into roles (id, site_id, name, permissions)
values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000008', 'Operator',
        array['conversation:read', 'conversation:send', 'conversation:assign']::text[])
on conflict (id) do nothing;

insert into operator_roles (operator_id, role_id)
values ('00000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-00000000000a')
on conflict (operator_id, role_id) do nothing;
SQL
kubectl exec -i -n ago-chat deploy/postgres -- psql -U ago -d ago_chat -v ON_ERROR_STOP=1 < /tmp/site2-seed.sql
kubectl exec -i -n ago-chat deploy/redis -- redis-cli FLUSHALL
```

**The `demo-operator-2` Keycloak user** was added by `kubectl apply`'s own Keycloak rollout restart
picking up the changed `keycloak-realm-import.json` — which worked only because the restart wiped
Keycloak's H2 store and re-imported the realm wholesale; see step 12's corrected note above, which
`15-01` corrected a second time. That route no longer exists: since `15-01` the realm survives the
restart and the import is skipped, so a new seeded user needs an Admin API call. No separate Admin API
call was needed *at the time*, though this session used the Admin API anyway to
diagnose a real problem: the first version of this user (`lastName: "Operator (tenant 2)"`) was
created successfully but could never log in (`invalid_grant: "Account is not fully set up"`) —
Keycloak's declarative User Profile silently rejects that shape of `lastName` at login time, not at
creation time, with no actionable error. Fixed by using a plain `"Operator2"` instead
(`keycloak-realm-import.json` updated to match, so a fresh install never hits this). If a future
seeded user's login fails the same opaque way, suspect the `firstName`/`lastName` shape first, before
anything else.

**Verify — from outside this network**: load `https://demo-shop2.reserve-me.ru` (visibly different
from `demo-shop1`'s page), send a message, confirm it in Postgres tagged `demo_site2`; a direct-grant
token for `demo-operator-2`/`demo-operator-2-password` resolves via `/api/v1/operators/me` to
`siteId=...0008`, a different site than `demo-operator`'s `...0001` — all passed live. `curl -I
http://chat.reserve-me.ru/` (or any `*.reserve-me.ru` host) returns a real `301` to the `https://`
equivalent — passed live, and the existing five hostnames stayed reachable throughout the Certificate
re-issue for the new SAN.

## Redeploying after a change

1. On the VPS: `git pull` in whichever of `ago-platform`/`ago-chat` changed, re-run the relevant part
   of step 6 (re-pack the platform feed only if `ago-platform` changed; always rebuild the `ago-chat`
   images whose source changed), re-import into containerd.
2. `kubectl rollout restart deployment/ago-chat-api deployment/ago-chat-worker deployment/ago-chat-webhooks -n ago-chat`
   as needed — `edge.md`'s own rolling-deploy sequence (`preStop`, drain, reconnect) applies unchanged;
   this is the same mechanism `3-06` already proved locally, now running on a real node.
3. If `k8s/overlays/demo/` itself changed (a new route, a new resource limit): `kubectl apply -k
   k8s/overlays/demo` again — kustomize + `kubectl apply` is declarative, so this is safe to re-run.

**Rebuilding the widget/console static bundles specifically (`8-02`/`8-05`) is a different mechanism
from steps 1-3 above**, not covered by them: `git pull` in `ago-console`/`ago-widget` on the VPS,
re-run step 12's own `build-static-images.sh` + `k3s ctr images import` block (now builds all three
images), then `kubectl rollout restart deployment/ago-console deployment/ago-demo-shop1
deployment/ago-demo-shop2 -n ago-chat` — re-running
`kubectl apply -k overlays/demo` alone does **not** pick up new image content here, since the
Deployment manifest itself is unchanged (same `:local` tag) even though what that tag points to in
containerd changed; a rollout restart is what actually re-pulls (imports) the new content into a fresh
pod, the same reasoning `edge.md`'s rolling-deploy sequence already relies on for the three
`ago-chat-*` hosts above.

No CI/CD auto-redeploy exists for this environment, deliberately (`8-01`'s own "Out of scope") — this
manual sequence is the whole story until a later item decides differently.

## Applying `15-01` to this deployment — a one-time step with real data loss **(you, on the node — NOT DONE)**

`15-01`/`adr/0036` moves Keycloak's user store off the embedded H2 file in the pod's writable layer and
onto its own `keycloak` database in the existing Postgres. Verified locally, on the Docker Desktop
cluster; **not applied here.** It is a manifest-only change, so `redeploy.sh` does not carry it — that
script pulls, builds, migrates and restarts, and never applies manifests. This needs a `kubectl apply -k`.

**Read this before running it. It destroys the realm's current runtime state, and there is no
migration.** Keycloak starts against a brand-new empty database; the H2 file the running pod uses is
not read or converted. What goes:

- every account created at runtime through `10-01`'s self-registration flow;
- the `platform-owner` realm role **grant** (`12-01`/`adr/0032`) — the role definition comes back from
  the realm import, the grant to a specific user does not;
- any other by-hand realm change made through the admin console since the pod last started.

What comes back automatically: the realm itself, the `ago-console` client, and the seeded demo
operators — everything in `keycloak-realm-import.json`, because the new database is empty and
`--import-realm` therefore runs with `OVERWRITE_EXISTING` on that first boot.

There is genuinely no export path worth building: the Admin API never returns credentials, so exported
users would arrive without passwords, and `kc.sh export` cannot run against a live `start-dev` H2 file
because H2 allows one process to hold it open. So the procedure is: write down what exists, apply, put
back what can be put back, and tell anyone else affected to register again.

**1. Capture what is there (before touching anything):**

```bash
kubectl exec -n ago-chat deploy/keycloak -- sh -c '
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master \
    --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null
  echo "== users ==";               /opt/keycloak/bin/kcadm.sh get users -r ago-chat --fields username,email,firstName,lastName,enabled,emailVerified
  echo "== platform-owner ==";      /opt/keycloak/bin/kcadm.sh get "roles/platform-owner/users" -r ago-chat --fields username
' | tee ~/keycloak-pre-15-01.txt
```

**2. Add the new key to the overlay's `.env`** (it is gitignored and lives only on this node), with a
freshly generated value — `openssl rand -base64 24`:

```
KEYCLOAK_DB_PASSWORD=<generated>
```

Without it the Keycloak pod fails in its init container with `KEYCLOAK_DB_PASSWORD: not set` and never
starts. That is the intended failure: loud, and before anything else moves.

**3. Apply and watch the pod, not the rollout:**

```bash
cd ~/ago/ago-deploy && git pull --ff-only origin main
kubectl apply -k k8s/overlays/demo
kubectl get pods -n ago-chat -l app=keycloak -w        # Init:0/1 -> Running -> 1/1, ~60-90s
kubectl logs -n ago-chat deploy/keycloak -c create-keycloak-database   # CREATE ROLE / CREATE DATABASE
kubectl logs -n ago-chat deploy/keycloak -c keycloak | grep KC-SERVICES0030
#   expect: Strategy: OVERWRITE_EXISTING   ->  Realm 'ago-chat' imported     (first boot, empty DB)
```

**4. Put back what the capture recorded**: re-grant `platform-owner` to the right user (the direct
Admin API snippet is in `local-dev.md`'s own section, and works identically against
`https://auth.reserve-me.ru`), and re-seed any second demo operator that is missing. Self-registered
accounts cannot be restored — those people register again, once.

**5. Prove the thing this whole item exists for**, on this deployment and not only locally: register or
create an account, `kubectl rollout restart deployment/keycloak -n ago-chat`, and log in as that
account afterwards. Keycloak's log on that second boot should read `Strategy: IGNORE_EXISTING` /
`Realm 'ago-chat' already exists. Import skipped`, and the account should still be there. Until that
has been run here, `15-01`'s "verified live on the demo deployment" box stays unticked.

**From then on**, editing `keycloak-realm-import.json` and restarting does nothing to this realm.
Realm-level settings go through `k8s/apply-realm-settings.sh`; clients, roles and groups need their own
`kcadm.sh` call. Never `kc.sh import --override true` — it replaces the realm and takes every account
with it.

## Transactional email — `10-05`, on a self-hosted Postfix

**The provider decision was made and it went against `adr/0040`'s recommendation.** That ADR
recommended Yandex Cloud Postbox; the author chose **self-hosted Postfix on this node**. `adr/0040`'s
amendment records the reversal, what the recommendation got wrong (outbound port 25 is *not* blocked
by this hoster — verified), and what the choice costs. Read it before changing anything here.

There is therefore **no provider account and no SMTP credential.** The `KEYCLOAK_SMTP_*` block in
`k8s/overlays/demo/.env.example` carries real committed values rather than placeholders, because none
of them is sensitive.

### The shape of it

Postfix runs on the node, send-only: it accepts nothing for the domain (`mydestination = localhost`),
has no `relayhost`, and delivers directly to recipient MXes. OpenDKIM signs outbound mail in sign-only
mode with a 2048-bit key under selector `mail`.

Keycloak runs in a pod and reaches Postfix at **`10.42.0.1:25`** — the k3s flannel bridge (`cni0`)
gateway, i.e. the node as seen from inside a pod. Postfix listens on all interfaces and trusts
`10.42.0.0/16` in `mynetworks`; ufw allows that CIDR. No Service, no `Endpoints`, no `hostNetwork`.
That address is cluster-internal and identical on any default k3s install, so unlike the node's public
address it is safe to commit. No AUTH and no STARTTLS on that hop — it never leaves the machine.

### Changing the mail configuration

```bash
cd ~/ago-deploy

# 1. Edit the KEYCLOAK_SMTP_* block in k8s/overlays/demo/.env (gitignored).
# 2. Push it into the Secret. NOTE: the secretGenerator hash changes, so this rolls every Deployment
#    that mounts infra-credentials - api, worker, webhooks, keycloak, postgres, rabbitmq, minio,
#    grafana - not just Keycloak. Expect a brief blip, and do it deliberately.
kubectl apply -k k8s/overlays/demo
kubectl rollout status deployment/keycloak -n ago-chat --timeout=300s

# 3. Apply to the live realm. The Secret changing does NOT change the realm by itself - smtpServer is
#    realm state, and since 15-01 realm state only arrives through a script.
k8s/apply-smtp-settings.sh
```

### Before any send from a rebuilt node: check DNS the hard way

SPF, DKIM, DMARC and a correct PTR must all exist, **and the zone must agree with itself.** This is
not a formality — `adr/0040`'s amendment records an incident where reg.ru served this zone from
sixteen authoritative IPs of which only four carried the DKIM record. A verifier that lands on one of
the other twelve gets an authoritative `NXDOMAIN`, fails DKIM, and caches that negative answer. On an
IP with no sending reputation, that is durable harm done for a reason no single `dig` would reveal.

`dig <name>` is **not** a propagation check: it asks one recursive resolver, which asked one
authoritative server. Compare the SOA serial at every authoritative address instead:

```bash
cd ~ && for ns in $(dig +short NS reserve-me.ru); do for ip in $(dig +short A "$ns"); do
  echo "$ip $(dig +norecurse +short +time=2 SOA reserve-me.ru @"$ip" | awk '{print $3}')"
done; done | sort -k2
```

Every line must show the same serial. If they do not, wait — the zone's SOA refresh is four hours, so
a secondary that missed the `NOTIFY` catches up within that — and re-run it. Only then:

```bash
cd ~ && sudo opendkim-testkey -d reserve-me.ru -s mail -vvv
```

`key OK` means the key in DNS matches the private key OpenDKIM holds. `record not found` while `dig`
succeeds is the partial-propagation symptom above, not a key problem.

### Proving it

**From a mailbox on a domain we do not control** (Yandex, Mail.ru, Gmail — not the sending domain):
register through `https://auth.reserve-me.ru`'s hosted form with a real browser, confirm the mail
arrives **in the inbox and not the spam folder**, follow the link, and reach `10-02`'s bootstrap call
with no admin-API step anywhere in it. Then do a password reset the same way.

Inbox-versus-spam is the whole point and cannot be checked from the node: `postfix/smtp` logging
`status=sent (250 2.0.0 OK)` means the recipient *accepted* the message, which is entirely compatible
with it being filed as spam. Read the actual mailbox.

Useful without owning a mailbox at each provider: send once to a `mail-tester.com` address and read
its report, which gives an objective SPF/DKIM/DMARC/PTR verdict and a SpamAssassin score. It does not
tell you where Gmail would put the message, only whether the authentication story is sound.

### Inbound — small on purpose, and here is what it is not

The domain has an MX (`10 mail.reserve-me.ru`) and Postfix accepts mail for it. **This is not a mail
service for humans.** There is no IMAP, no webmail, no per-person account, and none is planned. It is
a handful of aliases in `/etc/aliases` delivering into one local mbox, `/var/mail/ago`:

| Alias | Why it exists |
|---|---|
| `postmaster@`, `abuse@` | RFC 2142. Where blocklist operators and receiving providers write about our sending. An unreachable `postmaster@` is itself a negative deliverability signal. |
| `no-reply@` | Keycloak's envelope sender, so **this is where bounces come back to**. A mistyped registration address produces a hard bounce that now lands here instead of nowhere. |
| `dmarc@` | DMARC `rua=` aggregate reports — **the alias exists, the DNS tag does not yet.** See below. |
| `root@` | cron and `unattended-upgrades`, otherwise silently dropped. |

Read it with `sudo less /var/mail/ago` (or `mail -f /var/mail/ago`). **Nothing reads it on a
schedule** — that is a real gap, not an oversight, and `15-03` is where notifying on it would belong.

Anything not aliased is rejected at RCPT time rather than accepted and bounced, so this node is not a
backscatter source. Adding an address means adding an alias and running `sudo newaliases`.

**Two registrar edits are still outstanding** (DNS is not managed from this repo or the node):

1. `MX 10 mail.reserve-me.ru` — without it nothing external can reach the aliases above at all.
2. DMARC gains its reporting destination: `v=DMARC1; p=none; rua=mailto:dmarc@reserve-me.ru`. It is
   currently `v=DMARC1; p=none;` with no `rua=`, which was unavoidable while there was no inbox and is
   now merely undone.

### Re-proving the port-25 properties after any change

Port 25 is open to the internet, so two properties must hold and both are cheap to check. Run these
**from a machine that is not the node** (the node itself is in `mynetworks` and would pass trivially):

```bash
# 1. NOT AN OPEN RELAY - must answer 554 5.7.1 Relay access denied
cd ~ && echo probe | curl -sv --url "smtp://mail.reserve-me.ru:25/probe.example.com" \
  --mail-from "probe@gmail.com" --mail-rcpt "probe@example.org" --upload-file - 2>&1 | grep -E "RCPT|554|550"

# 2. UNKNOWN RECIPIENT REFUSED IN-BAND - must answer 550 5.1.1 User unknown in local recipient table
cd ~ && echo probe | curl -sv --url "smtp://mail.reserve-me.ru:25/probe.example.com" \
  --mail-from "probe@gmail.com" --mail-rcpt "nosuchuser@reserve-me.ru" --upload-file - 2>&1 | grep -E "RCPT|550"
```

Both verified after the inbound change on 2026-08-25. Use an FQDN as the URL path — that becomes the
EHLO name, and `reject_non_fqdn_helo_hostname` will refuse a bare hostname — and a sender domain that
actually accepts mail, since `reject_unknown_sender_domain` refuses `example.com` (null MX).

### What bounds the junk an MX attracts

`smtpd_helo_required`, `reject_invalid_helo_hostname`, `reject_non_fqdn_helo_hostname`,
`reject_non_fqdn_sender`, `reject_unknown_sender_domain`; per-client connection/message/recipient rate
limits, from which `mynetworks` is exempt so the cluster's own path is never throttled;
`message_size_limit` 10 MB; `mailbox_size_limit` 50 MB with a `logrotate` entry
(`/etc/logrotate.d/ago-mailbox`) rotating the mbox weekly, four compressed generations — the rotation
is what stops the size limit becoming a permanent "mailbox full" rejection.

**No content filter, deliberately** — no SpamAssassin, no rspamd. Nobody reads this mailbox
conversationally, so junk costs disk rather than attention, and disk is already bounded.

**Exposure**: Postfix 3.8.6 from Ubuntu's archive, SMTP on 25 with opportunistic STARTTLS and **no
SASL** — there is no authenticated submission path, so no credential to brute-force and no submission
port open. Dovecot/IMAP/POP are not installed. Patched by `unattended-upgrades` (enabled, `-security`
origin included).

### What this costs, permanently

- **Reputation is ours to build and lose.** A provider brings shared IP reputation that is already
  good; this node brings none, and any future misstep lands on the one IP that also carries every
  legitimate verification mail.
- **Nothing monitors blocklists.** The first symptom of a Spamhaus listing will be a visitor saying
  the mail never arrived. Check `mailq` and `journalctl -u postfix` when that happens.
- **Bounces land but are not processed.** `no-reply@` receives them; nothing reads them, there is no
  suppression list, and a repeatedly-bouncing address is retried like any other.
- **SPF is `-all`**, a hard fail authorising exactly this node. Correct while all outbound comes from
  here — and it means **any future attempt to send under this domain from anywhere else fails by
  design**: a second node, a migration to a provider, a CI notification. The fix is a deliberate SPF
  change made alongside the new sender, never a surprise to diagnose.
- **Mail dies with the node.** One node, no queue anywhere else, and inbound stops too.

**And one consequence that is not about mail at all.** `adr/0034` deferred the registration CAPTCHA
partly because a spam account could never lift `verifyEmail` and so could never create a tenant.
Turning mail on deletes that bound — and `adr/0040` section 6's named replacement, the provider's own
200-messages-per-24-hours quota, **does not exist on a self-hosted Postfix.** So the trigger has fired
and its mitigation is gone. Read `adr/0040`'s amendment before treating that as settled.

## Known gaps, named plainly

- **Keycloak's realm still has `sslRequired: "none"`** (`k8s/base/keycloak-realm-import.json`) —
  inherited unchanged from the local realm import, per this item's own instruction to reuse `5-05`'s
  mechanism rather than invent a new one. Tightening this to `external` (require TLS for
  non-private-network requests) is a real, deferred hardening step, not evaluated live against this
  deployment's own `--proxy-headers=xforwarded` config in this session.
- **Keycloak runs in `start-dev` mode publicly**, not its own hardened `start` production mode —
  `adr/0026`'s own "Consequences" section named this a deliberate, stated gap: a demo IdP for one
  seeded operator, not a production identity provider. **`15-01`/`adr/0036` re-opened that decision**
  (one of its justifications had expired — `adr/0028` opened the realm to public self-registration, and
  the store `start-dev` defaulted to was destroying those accounts) and kept `start-dev` deliberately,
  with the reasoning recorded rather than inherited. The gap is now one concrete precondition instead
  of an open-ended "hardening" wish: verify end to end on this node that Keycloak trusts the
  `X-Forwarded-Proto` header NGINX Gateway Fabric sets, raise `sslRequired` from `none` to `external`
  (the bullet above), and only then evaluate `start` — which additionally wants `--optimized` and
  therefore a derived, built Keycloak image, which this deployment's registry-less image delivery does
  not have a place for yet (`15-06`).
- ~~**No firewall, and the k3s control plane faces the internet**~~ — **closed the same day it was
  found, 2026-08-25.** `ufw` now runs with `deny incoming`, allowing `22`, `80` and `443` plus the k3s
  pod (`10.42.0.0/16`) and service (`10.43.0.0/16`) ranges and the `cni0` bridge.
  `DEFAULT_FORWARD_POLICY` had to be set to `ACCEPT` first — its `DROP` default breaks pod networking
  on a k3s node, which is the trap this change exists to avoid rather than fall into. Verified after
  enabling: a fresh SSH session, 24 pods still Running, and `chat`/`auth`/`console`/both demo
  shops/apex all still 200.

  **How it was verified, because the obvious method lies.** A plain TCP probe from the author's own
  network reports *every* port reachable, including one nothing listens on — something on that path
  answers every SYN. The trustworthy evidence is content, not connectivity: before the firewall,
  `curl -sk https://<node-ip>:6443/version` returned a real Kubernetes `401` JSON body, and `:10250`
  answered `401` as well. After it, the same requests return nothing at all. Whether `32669` was ever
  reachable from outside was never actually established — that one only ever produced an ambiguous TLS
  error, and the earlier note claiming otherwise overstated what the evidence supported.
- **No visitor can complete self-registration here, and password reset does not exist** — the realm
  has no `smtpServer`, so Keycloak accepts a registration and then cannot send the verification mail;
  the account is created and permanently stuck. `10-05`/`adr/0040` built the whole delivery mechanism
  and proved it locally; what is missing on this deployment is the one thing a session cannot decide,
  the sending provider. "Turning on transactional email" above is the procedure. This is the largest
  functional gap on this deployment, not a hardening one.
- **k3s Secrets are unencrypted at rest** — `k3s secrets-encrypt status` reports `Disabled`. Host-level
  access is required to read them, so it is defence-in-depth; `17-05` owns the decision.
- **Unattended security upgrades are on and working** — checked 2026-08-25, zero pending, no reboot
  outstanding. Recorded here because it is the kind of thing later assumed to be missing.
- **One node, still** — `k8s-local.md`'s own "Known limits" (no pod anti-affinity, no real node-drain
  or network-partition testing) carry over unchanged to this real deployment. `nfr.md`'s "not an
  uptime SLA — this is a demo cluster" framing is the bar this deployment is held to, not a new one
  invented here.

## Reaching Grafana (it is no longer public)

`grafana.reserve-me.ru` was removed from the edge on 2026-08-25 (`ago-deploy`'s `gateway.yaml` carries
the reasoning). Grafana is a ClusterIP Service inside the cluster, not something the node itself
serves, so a tunnel has to point at the Service address rather than at the node's own `localhost`:

```bash
cd ~ && GRAFANA_IP=$(ssh -i ~/.ssh/ago-vps-ed25519 ago@<node-ip> 'sudo k3s kubectl get svc grafana -n ago-chat -o jsonpath={.spec.clusterIP}') && ssh -i ~/.ssh/ago-vps-ed25519 -N -L 3000:$GRAFANA_IP:3000 ago@<node-ip>
```

Then open `http://localhost:3000`. The ClusterIP is looked up rather than hardcoded because it changes
if the Service is ever recreated. Verified working 2026-08-25.

Nothing about this replaces an external liveness check — Grafana runs inside the thing it watches and
cannot report the failure that matters most. That is `backlog/15-03`'s subject, and the target is
`https://chat.reserve-me.ru/healthz/ready`, which already exercises Postgres, RabbitMQ and Redis.

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
