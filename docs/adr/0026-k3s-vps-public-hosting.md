# ADR-0026: k3s VPS hosting, `*.reserve-me.ru` domain plan, VM sizing, and TLS

- **Status**: Accepted
- **Date**: 2026-08-24
- **Stage**: 8

## Context

`8-01-public-deployment-target.md` needs the full `Ago.Chat.*` stack (`Api`/`Worker`/`Webhooks`,
Postgres, Redis, RabbitMQ, MinIO, Keycloak) reachable at a real public HTTPS URL instead of
`localhost`. `roadmap.md` names two hosting shapes without choosing between them — a small managed
Kubernetes offering, or a self-installed k3s VPS — and `k8s-local.md`'s "Known limits" section already
states the local cluster is one node; this item has to say plainly which of those limits carry over to
a public deployment and which do not.

Two decisions arrived pre-made from the author, recorded here rather than re-argued because they were
made outside this ADR's own reasoning chain and this ADR's job is to record them alongside the parts
that were still genuinely open:

- **Hosting: a k3s VPS**, chosen over a managed Kubernetes offering for lower cost, accepting that
  `deploy/k8s/base/`'s manifests transfer with zero new surface only on a managed offering — the VPS
  path needs its own bring-up work this ADR designs.
- **Domain: `reserve-me.ru`** (the author's own), with `*.reserve-me.ru` subdomains — no new
  purchase, and the pattern is left open for more subdomains later.

What this ADR still had to resolve, because nothing upstream picked an answer: the concrete
subdomain-to-service map (the backlog note flagged a gap — Keycloak had no subdomain of its own),
the specific VPS tier, how a container image reaches a node with no shared Docker Desktop image
store, and the TLS mechanism.

### Real payment constraint behind the provider choice

Timeweb Cloud, a Russian hosting provider, was the candidate evaluated below at the time this ADR was
first written — not Hetzner, DigitalOcean, or another Western provider, because the author's payment
cards are Russian-issued. Visa/Mastercard/Amex cards issued by Russian banks stopped clearing at
Western merchants after 2022; paying a Western VPS provider directly is not possible without a
third-party intermediary, which adds cost, friction, and a dependency this ADR would rather avoid than
route around. This is a real constraint on the option set, not a preference. **The author ended up
purchasing from Fornex instead (a Spain-registered European provider with a Russia-region VPS line and
working direct payment) — see "Post-decision update" below**; the constraint and the reasoning that
led to evaluating Timeweb first stay accurate, they just did not end up naming the actual provider
used.

### Post-decision update — actual purchase differs from this ADR's own recommendation (2026-08-24)

The author independently shopped and purchased before this ADR's own recommendation was applied
verbatim. Recorded here rather than silently edited into the analysis above, so the reasoning trail
stays honest about what was actually decided versus what was actually bought:

- **Provider/tier actually purchased: Fornex, "Cloud NVMe 6"** (4 vCPU / **6 GB RAM** / 80 GB NVMe,
  Russia location, Ubuntu 24.04 LTS) — not Timeweb Cloud MSK 80 as recommended below. Fornex's own
  Russia-region tier was not part of the original comparison (only Timeweb was evaluated); the sizing
  math below still applies to it directly since it targets the same workload regardless of provider.
- **6 GB vs. the recommended 8 GB — real, stated tradeoff, not silently accepted**: the sizing math
  below puts the *typical steady-state* footprint (requests floor + k3s/NGF/cert-manager/OS overhead)
  at ≈3.65–4.25 GiB, leaving ≈1.75–2.35 GiB of headroom on 6 GB — comfortable for a demo cluster opened
  occasionally, matching `nfr.md`'s own "not an uptime SLA" framing for this deployment. What 6 GB does
  **not** cover is the full *worst-case* scenario in the table below (every pod simultaneously at its
  configured memory limit, ≈6.3–6.6 GiB before k3s/NGF/cert-manager/OS overhead, ≈7–7.5 GiB after) — a
  genuine, accepted OOM risk in that specific unlikely-but-possible scenario, not a risk this ADR's own
  math says doesn't exist. 8 GB (Timeweb MSK 80 or an equivalent-spec Fornex tier, if one exists) would
  close that gap; the author chose 6 GB anyway, informed by this exact number, not despite it.
- **Domain actually purchased: `reserve-me.ru`** (via reg.ru), **not** a subdomain of the author's own
  `golyakov.net` as originally planned — a dedicated domain bought specifically for this project, not
  a shared personal one, so the `*.ago.` isolation prefix the original plan used (to avoid colliding
  with anything else on a multi-purpose personal domain) is dropped: subdomains are `chat.reserve-me.ru`,
  `auth.reserve-me.ru`, `console.reserve-me.ru`, `demo-shop1.reserve-me.ru`, `demo-shop2.reserve-me.ru`
  directly, not `*.ago.reserve-me.ru`. Every reference to the domain elsewhere in this ADR and in
  `runbooks/public-deploy.md`/`ago-deploy/k8s/overlays/demo/` has been updated to match — this is a
  find-and-replace of the domain value, not a re-litigation of the subdomain-to-service mapping
  decided below, which stays exactly as reasoned.

## Decision

### Subdomain-to-service map

| Subdomain | Routes to | Owner |
|---|---|---|
| `chat.reserve-me.ru` | `Ago.Chat.Api` — REST + both SignalR hubs | this item |
| `auth.reserve-me.ru` | Keycloak (OIDC issuer + login UI) | this item — **new, not named in the backlog's own subdomain list** |
| `console.reserve-me.ru` | `ago-console` static bundle | routing designed here; the Service and bundle are `8-02`'s job |
| `demo-shop1.reserve-me.ru`, `demo-shop2.reserve-me.ru` | two independent seeded demo tenant sites the widget embeds on | routing designed here; `demo-shop1`'s Service/bundle are `8-02`'s job, `demo-shop2`'s (a second, isolated tenant, for demonstrating tenant isolation live) are `8-05`'s |

**`auth.reserve-me.ru` is this ADR's own addition to the plan**, not a re-litigation of the
domain/subdomain-pattern decision. The backlog's subdomain list covered API, console, and the two demo
shops, but Keycloak was never given a public name of its own — `Ago.Chat.Api`'s Operator JWT scheme
validates a token's `iss` claim by exact string match (`5-05`'s own documented gotcha:
`127.0.0.1`/`localhost` are different issuers to it even though they reach the same container), and
`ago-console`'s browser redirect (`5-06`, Authorization Code + PKCE) needs Keycloak reachable from the
visitor's own browser, not only from inside the cluster. Both requirements are unmet by routing
`Auth:Keycloak:Authority` at the internal `keycloak` Service, so a public hostname for Keycloak is not
optional — it falls out of mechanics `5-05`/`5-06` already built, not a new feature this item invents.
Same `*.reserve-me.ru` pattern, so it costs nothing beyond one more DNS record and one more
`HTTPRoute`/`Certificate` DNS name.

### VPS tier: Timeweb Cloud MSK 80 (4 vCPU / 8 GB RAM / 80 GB NVMe, ≈1 800 ₽/month, annual billing)

Sizing math, from the actual manifests this item extends (`k8s/base/*.yaml`'s own `resources:`
blocks), summed across everything that runs on this one node — Postgres, RabbitMQ, Redis, MinIO,
Keycloak, `Ago.Chat.Api`/`Worker`/`Webhooks` (one replica each — see "Replica counts" below),
Prometheus, Grafana, Jaeger:

| | Memory requests (scheduling floor) | Memory limits (worst case ceiling) |
|---|---|---|
| Application + infra pods (sum of `k8s/base/*.yaml`) | ≈2.19 GiB | ≈5.63 GiB |
| k3s control plane + kubelet + containerd (typical, not measured on this project's own hardware) | ≈0.3–0.5 GiB | same |
| NGINX Gateway Fabric data-plane pod | ≈0.1 GiB | ≈0.15 GiB |
| cert-manager (controller + webhook + cainjector, three light pods) | ≈0.15 GiB | ≈0.2 GiB |
| OS (Ubuntu Server, minimal) | ≈0.2–0.3 GiB | same |
| **Total** | **≈3.0–3.3 GiB** | **≈6.3–6.6 GiB** |

8 GB leaves roughly 1.4–1.7 GB of headroom above the *worst-case limits ceiling*, not just the request
floor — meaning even if every pod simultaneously hit its configured memory limit (Postgres under a
burst, RabbitMQ's own documented Erlang-VM startup spike, Keycloak's JVM warming up), the node still
has margin before the kernel OOM-killer has to pick a pod. `8-02`'s console/demo-page addition is a
static bundle behind a lightweight server (tens of MB, not hundreds) and does not change this
materially.

**MSK 50 (4 GB RAM, ≈1 080 ₽/month) was rejected, not just skipped**: 4 GB sits *below* this stack's
own limits ceiling before k3s/NGF/cert-manager/OS overhead are even added — running this stack there
means the kernel OOM-killer, not this project's own resource budgets, decides which pod dies first
under any real concurrent load. That is a named, real risk, stated plainly rather than glossed over:
a smaller tier would save ≈720 ₽/month but trade away the exact behaviour `nfr.md`'s "zero
acknowledged-but-lost messages" correctness bar depends on never happening by accident.

**MSK 100 (12 GB RAM, ≈2 790 ₽/month) was considered and rejected as unnecessary cost**: the sizing
math above already clears MSK 80's ceiling with real margin: paying ≈990 ₽/month more for headroom
this workload's own measured/budgeted footprint does not need would not be "safer" in any way this
project can point to — CLAUDE.md's own instruction against inventing numbers cuts against padding a
recommendation with unearned safety margin as much as it cuts against understating one.

CPU is not the deciding factor either way: summed CPU limits (~6–7 vCPU across all pods) exceed 4
vCPU, but CPU limits are compressible — a pod that hits its CPU limit is throttled, not killed — and
this is a demo cluster a recruiter opens occasionally, not `nfr.md`'s own Stage-7 scale targets (that
target concurrency profile is explicitly out of scope for this item, per the backlog's own "Out of
scope" section).

Storage is not a deciding factor either: PVCs sum to ~7 GiB (Postgres 2, RabbitMQ 1, Redis 0.5, MinIO
2, Prometheus 1, Grafana 0.5) against 80 GB NVMe on MSK 80 — enormous headroom even after container
images and OS.

### Image delivery: build directly on the VPS, import into k3s's own containerd — no registry

> **Amended by `adr/0047` (2026-08-25) — this section only.** Everything else in this ADR stands.
> Images now go to GHCR under their full commit SHA, pushed by `ago-chat`'s CI; the demo overlay
> pulls them and the three `imagePullPolicy: Never` patches are gone. The reasoning below was
> answering "how does a container reach a node with no shared image store" and answered it correctly
> for that. What it did not weigh — because nothing had yet made it visible — is that a mutable
> `:local` tag leaves *no earlier artifact anywhere*, so there is nothing to roll back to, and *no way
> to tell from a running pod which commit it carries*. Both costs came due on 2026-08-25, in one day.
> The "new credential" objection below also turned out not to hold: a repository's own `GITHUB_TOKEN`
> publishes to GHCR with no new secret, and a public package needs none to pull either. Read this
> section for the reasoning trail; read `adr/0047` for what is true now.

`k8s/overlays/local/kustomization.yaml`'s own `imagePullPolicy: Never` works because images are built
straight into the local Docker daemon's store that the same machine's Kubernetes reads from
(`k8s-local.md`). A remote VPS has no such shared store, so this item had to pick a real mechanism:

**Chosen: `git clone` the public repositories onto the VPS, build with the existing
`k8s/build-images.sh` unchanged, then `k3s ctr images import` the result into the node's containerd
content store.** Concretely (`public-deploy.md` has the full runbook):

```bash
git clone https://github.com/<author>/ago-platform.git
git clone https://github.com/<author>/ago-chat.git
cd ago-platform && dotnet pack Ago.Platform.slnx -c Release -o ../ago-deploy/.nuget-feed && cd ..
cd ago-chat && ../ago-deploy/k8s/build-images.sh   # CHAT_REPO/NUGET_FEED already default to this layout
for img in ago-chat-api ago-chat-worker ago-chat-webhooks; do
  docker save "${img}:local" | sudo k3s ctr -n k8s.io images import -
done
```

This reuses `build-images.sh` **unmodified**, including its existing `:local` tags — the demo
overlay's own `imagePullPolicy: Never` patch (below) is copied verbatim from the local overlay for
exactly that reason: same tags, same policy, same "forgot to build" failure mode
(`ErrImageNeverPull`, not a silent hang against a registry that was never going to have this tag). No
new NuGet config file, no image-tag-substitution patch, nothing in `ago-chat` changes — this is `git
clone` of already-public repositories (`repositories.md`: "everything is public") plus commands
already proven locally, run on a different machine.

**Rejected: a hosted registry (GHCR, Docker Hub)** — a real, working alternative, and the one most
production deployments would reach for. Rejected here because it is a new dependency and a new
credential this project does not otherwise need: pushing to GHCR from the VPS (or from CI) needs a
PAT with `write:packages`, a second token alongside the `read:packages` one `adr/0018` already
introduced for `ago-platform`'s own package feed, and a registry pull step this item's own "no CI/CD
auto-redeploy" scope note explicitly declines to build. Build-on-VPS costs real CPU/memory on a
resource-constrained node during the build — acceptable for a stack that redeploys occasionally by a
documented manual runbook (this item's own scope), not for one that redeploys on every push.

### TLS: cert-manager + Let's Encrypt, HTTP-01 challenge

NGINX Gateway Fabric remains the edge component (`adr/0014`, unchanged by this item). `edge.md`'s
"Balanced by (demo deploy)" column already named cert-manager + Let's Encrypt as this item's own
prediction; this ADR confirms it and picks the challenge type: **HTTP-01**, not DNS-01. DNS-01 would
need a DNS-provider API credential for `reserve-me.ru`'s registrar wired into the cluster as a secret —
a new credential and a new integration this single-node, HTTP-reachable deployment does not need.
HTTP-01 only needs port 80 open and DNS already pointed at the node, both true here. cert-manager's
`gatewayHTTPRoute` ACME solver (stable since cert-manager 1.5) drives the challenge directly through
the Gateway API `Gateway`/`HTTPRoute` this project already uses, with no `Ingress` resource involved.

`ago-deploy-8-01/k8s/overlays/demo/tls.yaml` carries the `ClusterIssuer` (Let's Encrypt production
directory) and `Certificate` (one cert covering `chat.`, `auth.`, and `console.reserve-me.ru` via
`dnsNames`) resources — full detail in that file, not restated here.

## Consequences

- A public Keycloak endpoint (`auth.reserve-me.ru`) is new attack surface this ADR's own domain
  plan did not originally carry — mitigated by Keycloak already being designed to be internet-facing
  (it is a mainstream IdP, not a project-internal tool), and by `8-00`'s minimal base image work
  covering the `Ago.Chat.*` hosts, not Keycloak's own upstream image, which is out of this item's
  control either way.
- Redeploying after a source change means re-running the build-on-VPS sequence by hand — slower than a
  registry-backed rolling update, and a real cost the "no CI/CD auto-redeploy" scope accepted going in.
  **Superseded by `adr/0047`** for the three `Ago.Chat.*` hosts: `ago-deploy/k8s/deploy.sh <sha>`
  moves the cluster to an image CI already published, with no build on the node at all. The four
  static bundles still work exactly as described here.
- The MSK 80 tier's cost (≈1 800 ₽/month) is the author's own recurring expense for as long as this
  demo stays up — stated in real currency, not glossed over, since `CLAUDE.md` calls this out
  explicitly as real infrastructure cost, not a hypothetical.
- One node means `k8s-local.md`'s own "Known limits" (no pod anti-affinity, no real node-drain or
  network-partition testing) carry over unchanged to the public deployment — this item does not
  change that reality, it only moves it to a real, internet-reachable machine. `nfr.md`'s "not an
  uptime SLA — this is a demo cluster" framing is the honest bar this deployment is held to.
- Keycloak keeps running in `start-dev --import-realm` mode (matching local, per the backlog's own
  instruction to reuse `5-05`'s realm-import mechanism unmodified) with `--hostname`/`--proxy-headers`
  flags added so its issuer URL matches the public route — full production hardening of Keycloak
  itself (its own `start` production mode, its own TLS) is a deliberately named gap, not silently
  skipped: a demo IdP serving one seeded operator does not carry the same stakes as a production
  identity provider, and hardening it is not named anywhere in this item's scope.
- `k8s/base/keycloak-realm-import.json`'s `ago-console` client gains `https://console.reserve-me.ru/*`
  alongside its existing local `redirectUris`/`webOrigins` entries — a shared base file, so this is a
  small, deliberate deviation from "reuse `5-05`'s realm-import verbatim": the array is *extended*, not
  changed, and the addition is inert for the local overlay (Keycloak simply allows one more origin it
  will never see traffic from locally).

## Alternatives considered

- **A small managed Kubernetes offering** (the option the backlog names as the alternative to a k3s
  VPS) — `deploy/k8s/base/`'s manifests and `adr/0014`'s Gateway API choice would transfer with zero
  new surface, and a managed control plane removes the k3s-install and Traefik-conflict work this ADR
  had to do instead. Rejected: this was the author's own explicit call, made before this ADR was
  written, trading that zero-new-surface property for lower recurring cost. Recorded here as the
  alternative for a reader who would reasonably ask why not, not re-argued.
- **DNS-01 challenge instead of HTTP-01** — works without exposing port 80, and is the only option for
  a wildcard certificate. Rejected: this deployment needs three named hosts, not a wildcard, so DNS-01's
  main advantage does not apply, and it would add a DNS-provider API credential this project does not
  otherwise need. HTTP-01 needs nothing beyond what this deployment already has (DNS pointed at one
  node, port 80 reachable).
- **GHCR/Docker Hub image registry** — see "Image delivery" above; rejected for the credential and
  scope reasons stated there, not restated here. **Reversed by `adr/0047` on 2026-08-25**: GHCR was
  adopted, and the credential objection turned out to be wrong (publishing needs no new secret, and
  a public package needs none to pull).
- **A single subdomain with path-based routing** (e.g. `chat.reserve-me.ru/api`, `/console`) instead of
  per-service subdomains — would need one fewer DNS record and one fewer TLS SAN. Rejected: path-based
  routing at the edge for functionally separate services (API/hub traffic vs. a static SPA bundle vs.
  an IdP) invites exactly the kind of edge-side routing logic `edge.md`'s "What the edge must not be
  responsible for" already warns against, and per-subdomain routing is what the backlog's own plan
  already committed to before this ADR started.
