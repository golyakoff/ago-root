# Public deployment target: hosting, TLS, seeded demo tenant

- **Stage**: 8
- **Status**: done — live and verified 2026-08-24. `https://chat.reserve-me.ru`/`https://auth.
  reserve-me.ru` are real, reachable, TLS-terminated, and seeded; see "Shipped in" below for the seven
  real bugs found and fixed live along the way.
- **Depends on**: `8-00` (base image, sequenced first per the author's own explicit instruction) —
  otherwise nothing new architecturally, reusing `1-05-seed-demo-tenant.md`'s seed script and
  `5-05-operator-oidc-authentication.md`'s Keycloak realm-import verbatim, pointed at a new
  environment instead of inventing a new seeding mechanism

## Goal

A stranger's browser can reach a public HTTPS URL and get real TLS-terminated traffic to a real,
running instance of the full AGO Chat stack — `Ago.Chat.Api`/`Worker`/`Webhooks`, Postgres, Redis,
RabbitMQ, MinIO, Keycloak — seeded with exactly one demo site and one demo operator, the same
fixed-id rows `1-05`'s script and `5-05`'s realm-import already produce locally, now reachable at a
real domain with a real certificate instead of `localhost`. This item is the ground everything else
in Stage 8 stands on: `8-02`'s demo page and console, and the live link `8-03`'s README points to,
both need this to exist first.

## Context to read first

`architecture/edge.md`'s "What balances what" table — it already carries a "Balanced by (demo
deploy)" column (CDN for `widget.js`, cloud L4 LB for the rest) anticipating exactly this item, so
the edge shape is not being invented here, only stood up for real. `adr/0014` — NGINX Gateway
Fabric was chosen specifically because it was "the cheapest point... rather than the most expensive
one (Stage 8, real TLS, real traffic)"; this item is the ADR's own prediction coming due.
`runbooks/k8s-local.md` in full, especially "Known limits of this setup" (one node; Docker Desktop's
resource ceiling) — this item states plainly which of those limits carry over to the public
deployment and which don't. `backlog/1-05-seed-demo-tenant.md` and `backlog/5-05-operator-oidc-
authentication.md` — the seeding and Keycloak realm-import mechanisms this item reuses rather than
reinvents. `architecture/repositories.md`'s "Everything is public" section — "no secrets, ever," and
the existing precedent that a *throwaway* demo credential is not a secret in the sense that rule
means. `architecture/nfr.md`'s "Availability behaviour" note — "not an uptime SLA — this is a demo
cluster" — the honest bar this deployment is held to, not a production SLA it never promised.

## Scope

- Decide and record the hosting target in an ADR: a small managed Kubernetes offering, or a k3s VPS
  — `roadmap.md` names both without choosing, and this item's own Open questions below name why
  neither is picked here. The ADR states cost, how much of the existing `deploy/k8s/base/` Kustomize
  manifests and `adr/0014`'s Gateway API choice transfer unchanged vs. what a from-scratch k3s
  install would need instead, and the one-node reality either way (`k8s-local.md`'s own limits
  section already names this honestly for local; the public deployment inherits the same limit
  unless the chosen provider genuinely changes it).
- A registered domain (or a subdomain of one already owned) with DNS pointed at the chosen host, and
  TLS termination at the edge — cert-manager + Let's Encrypt if NGINX Gateway Fabric continues to be
  the edge component, or the hosting provider's own managed-LB TLS if that turns out cheaper/simpler
  (state which was used and why).
- Deploy the full stack from the manifests `deploy/k8s/base/` already carries — `Ago.Chat.Api`/
  `Worker`/`Webhooks`, Postgres, Redis, RabbitMQ, MinIO, Keycloak — via a new
  `deploy/k8s/overlays/demo/`, matching the existing `overlays/local/` pattern
  (`naming-and-structure.md`). The overlay carries whatever genuinely differs from local: replica
  counts and resource limits sized to a small/low-cost node, public hostnames, and how secrets are
  sourced.
- Secrets (Keycloak admin, DB password, IdP client secret, `Auth:JWT_SIGNING_KEY` equivalents) come
  from the hosting provider's own secret mechanism — a Kubernetes `Secret` applied out-of-band, or a
  VPS env file that is never committed — `deploy/k8s/overlays/demo/` carries only `.example` files,
  the same convention every other overlay already follows.
- Seed exactly one demo site and one demo operator against this new environment, using `1-05`'s
  script and `5-05`'s Keycloak realm-import unmodified — pointed at the new Postgres/Keycloak
  instances, not a new mechanism built for this stage.
- Verify health and reachability from *outside* the deployment — a real request from a machine not
  on the same network as the host, matching `k8s-local.md`'s own "verified means actually run"
  standard, not `kubectl get pods` alone.
- **Base image note added 2026-08-25, resolved by `8-00`**: the research this note originally recorded
  (Ubuntu Chiseled over Alpine, why, and the ICU/shell caveats to verify) is now a separate item,
  `docs/backlog/8-00-minimal-production-base-image.md`, done ahead of this item rather than deferred
  to it — the author asked for it resolved before `8-01` starts, not when it starts. This item now
  simply inherits whichever base image `8-00` shipped; no further base-image decision is this item's
  own job.

## Out of scope

- The demo landing page and the public console deployment — `8-02`, which needs this item's live
  API and Keycloak to point at but is its own separable piece of work (a different repository's
  static bundle, a different kind of verification).
- Alerting or uptime monitoring beyond what `7-03`'s dashboards already ship — `nfr.md`'s own "not
  an uptime SLA" framing already rejects treating this as a Stage 8 goal. **Now Stage 15's**
  (`15-03-alerting-and-notification.md`, 2026-08-24) — still not an SLA, but a deployment that has
  started holding other people's accounts (`10-01`) needs to be able to tell someone it is broken.
- Autoscaling or a multi-node topology — one small node is enough for a demo a recruiter opens
  occasionally; `nfr.md`'s scale targets are Stage 7's job, proven on a cluster built for that
  purpose, not this one.
- A CI/CD pipeline that auto-redeploys this environment on every push — a documented manual runbook
  is enough for a portfolio artifact that changes occasionally; nothing in `roadmap.md` asks for
  continuous deployment here, and building one would be scope this item did not need. **Still true**:
  Stage 15's `15-06-image-registry-and-deploy-rollback.md` deliberately makes deploys repeatable and
  reversible without making them automatic, and keeps auto-deploy out of scope for the same reason
  stated here.

## Done when

- [x] An ADR names the hosting choice and the reasoning (cost, manifest reuse, the one-node
      reality), accepted before any manifest work in this item starts. **`adr/0026`**, written and
      accepted in this pass — hosting/domain were the author's own prior calls; the VPS tier
      (Timeweb Cloud MSK 80 recommended, real sizing math; Fornex Cloud NVMe 6 actually purchased —
      see `adr/0026`'s "Post-decision update"), the image-delivery mechanism (build-on-VPS,
      import into containerd), and the TLS approach (cert-manager + Let's Encrypt, HTTP-01) are this
      ADR's own contribution, argued with alternatives.
- [x] A real request (`curl`, or a browser) from a network unrelated to the deployment reaches the
      public HTTPS URL, receives a valid certificate with no browser warning, and `/healthz/live`
      returns 200 — verified live, not asserted from the manifests. **Done 2026-08-24**:
      `curl https://chat.reserve-me.ru/healthz/live` → `200`, body `Healthy`, real Let's Encrypt
      certificate, run from a machine outside the VPS's own network. `runbooks/public-deploy.md` §11
      has the full transcript.
- [x] The seeded demo site's public key and demo operator's Keycloak credentials work against this
      environment exactly as `local-dev.md`'s "Getting a working operator session locally" section
      describes for local — verified with the same direct-grant curl pattern, pointed at the public
      Keycloak issuer instead of `127.0.0.1:8081`. **Done 2026-08-24**: the direct-grant call against
      `auth.reserve-me.ru` returned a real signed JWT (issuer correctly `https://auth.reserve-me.ru`,
      confirming the `--hostname` patch works), and that token was accepted by
      `https://chat.reserve-me.ru/api/v1/operators/me` with `200`, resolving to the seeded
      `demo-operator` row — the full chain proven, not just the token mint step.
- [x] A new runbook section (in `runbooks/k8s-local.md` or a new `runbooks/public-deploy.md` —
      whichever this item finds reads more honestly once written) covers bring-up, where secrets
      live, and how to redeploy after a change, to the same "a session with no memory can repeat
      this" bar every other runbook is held to. **`runbooks/public-deploy.md`**, new file — a
      dedicated runbook reads more honestly than folding this into `k8s-local.md`, since large parts
      of it (provisioning, DNS, secret generation) are steps only the author can perform, marked
      **(you)** throughout, distinct from the **(session)** steps a session with real SSH access can
      run directly. **Fully run live end to end 2026-08-24** — its own status line now says so, with
      the seven real bugs found along the way documented in place at the step each was found.
- [x] No secret value appears in any file this item commits — the same audit this repository already
      applies everywhere (`repositories.md`). `k8s/overlays/demo/.env.example` and `tls.yaml`'s ACME
      `email` field carry placeholder text only (`<generate-a-real-password-do-not-commit>`, a
      non-real `letsencrypt-admin@reserve-me.ru` address under the domain itself, never the author's
      own personal inbox) — audited by re-reading every new/changed file in this pass before
      handback.

## Shipped in

`https://chat.reserve-me.ru`, `https://auth.reserve-me.ru`, `https://console.reserve-me.ru`
(`8-02`'s own future backend), `https://grafana.reserve-me.ru` (author's own call, mid-deployment —
public over TLS + Grafana's own real generated password, gated the same way console/chat are, not
kept SSH-tunnel-only) — all TLS-terminated via a real Let's Encrypt certificate, all live on a real
Fornex VPS (`217.177.74.184`). Full bring-up in `runbooks/public-deploy.md`, real numbers/decisions in
`adr/0026` including its own "Post-decision update" for where the live purchase (Fornex Cloud NVMe 6,
domain `reserve-me.ru`) differs from the ADR's original recommendation (Timeweb MSK 80,
`*.ago.golyakov.net`).

**Six real bugs found and fixed live**, each documented in place in `runbooks/public-deploy.md` at the
step it was found, not just listed here:

1. `kubectl kustomize <remote-github-url>` hit its own hardcoded 27s timeout on this VPS's network
   path to GitHub — not blocked, genuinely slower than that timeout for a real data-transfer fetch
   (confirmed: `git ls-remote` was instant, a real `git clone` took ~39s). Worked around with a local
   clone, no VPN needed.
2. `dotnet pack` without `-p:Version=...` silently used `Directory.Build.props`'s stale placeholder
   version (`0.2.2`) instead of the real, CI-matching, `CHANGELOG.md`-derived version (`0.14.0`) —
   every image build failed `NU1102` until packed the same way `ago-platform`'s own CI does.
3. `docker.io`'s Ubuntu package ships without BuildKit's `buildx` component; `build-images.sh`'s
   `--build-context` flag needs it. Fixed: `sudo apt-get install -y docker-buildx` (not
   `docker-buildx-plugin` — that package name doesn't exist).
4. `keycloak`'s Deployment got the `imagePullPolicy: Never` patch by mistake (copied from the three
   `ago-chat-*` entries) — real upstream image, never built locally, `ErrImageNeverPull` until removed.
5. `keycloak`'s default `RollingUpdate` strategy deadlocked its own embedded H2 database (single-
   writer exclusive lock, old+new pod briefly co-running) on any rollout — fixed with
   `strategy: { type: Recreate }`.
6. `keycloak`'s liveness probe (`initialDelaySeconds: 20`) was far too aggressive for a real first
   boot (~23s of Quarkus augmentation alone, measured live, plus a schema migration and realm import
   after that) — Kubernetes killed the pod mid-startup on every attempt (`exit 143`, not an internal
   crash) until the delay was raised to 90s. A long-running local-dev Keycloak pod never re-exercises
   a cold first boot, so this was never hit before a real cluster start.
7. (a seventh, cert-manager rather than `ago-deploy`) cert-manager's plain static-manifest install
   does not enable Gateway API support by default — every ACME challenge failed
   (`gateway api is not enabled`) until the controller was patched live with
   `--enable-gateway-api=true`. One-time cluster-level flag, not part of any committed manifest.

## Open questions — resolved 2026-08-24, author's own decision

- **Hosting target: k3s VPS**, not a managed Kubernetes offering — the author's explicit call,
  choosing lower cost over `deploy/k8s/base/`'s manifests transferring with zero new surface. This
  item's own ADR — **now written, `adr/0026`** — covers the provisioning work `k8s-local.md` never
  had to (Ubuntu 24.04 LTS, the k3s install command with Traefik disabled, confirming the Gateway
  API's NGINX Gateway Fabric install from `k8s-local.md` transfers onto k3s unchanged) in
  `runbooks/public-deploy.md`; the tier itself (recommended: Timeweb Cloud MSK 80; actually purchased:
  Fornex Cloud NVMe 6, 6 GB not 8 GB — `adr/0026`'s own "Post-decision update" has the real tradeoff)
  and the reasoning are in the ADR.
- **Domain: `reserve-me.ru`** — a dedicated domain purchased via reg.ru specifically for this
  deployment (2026-08-24), superseding the original plan's `*.ago.golyakov.net` subdomain-of-a-personal-
  domain approach (`adr/0026`'s own "Post-decision update" has the full account of the change).
  Subdomains: `chat.reserve-me.ru` (Api/hub traffic), `console.reserve-me.ru` (operator console),
  `demo-shop1.reserve-me.ru` / `demo-shop2.reserve-me.ru` (seeded demo tenant sites for the widget to
  embed on), with room to add more subdomains under the same pattern for any further tool this stage
  or a later one needs. This item's ADR — **`adr/0026`** — records the exact subdomain-to-service
  mapping, including one addition the original plan above did not name: `auth.reserve-me.ru` for
  Keycloak, required by `5-05`'s own exact-issuer-match validation and `8-02`'s planned browser
  redirect, neither of which works against an internal-only Keycloak hostname. The real VPS now exists
  (Fornex, `217.177.74.184`) and DNS records for all five subdomains above are being added at reg.ru
  as this item's own live deployment work proceeds — `runbooks/public-deploy.md` §2 has the exact
  records.

Both answered — this item is no longer blocked. Status changed to `ready`; still depends on `8-00`
landing first per the author's own explicit sequencing. Design/prep work in this pass (`adr/0026`,
`runbooks/public-deploy.md`, `ago-deploy/k8s/overlays/demo/`) does not itself require `8-00` to have
landed — nothing here builds an image — but the live bring-up in `public-deploy.md` does need
whichever base image `8-00` ships, per this item's own "Depends on" line above.
