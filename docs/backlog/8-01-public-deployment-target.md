# Public deployment target: hosting, TLS, seeded demo tenant

- **Stage**: 8
- **Status**: in progress — design/prep done (`adr/0026`, `runbooks/public-deploy.md`,
  `ago-deploy/k8s/overlays/demo/`), live deployment not yet done. See "Done when" below for exactly
  which boxes this covers and which still need a real VPS.
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
  an uptime SLA" framing already rejects treating this as a Stage 8 goal.
- Autoscaling or a multi-node topology — one small node is enough for a demo a recruiter opens
  occasionally; `nfr.md`'s scale targets are Stage 7's job, proven on a cluster built for that
  purpose, not this one.
- A CI/CD pipeline that auto-redeploys this environment on every push — a documented manual runbook
  is enough for a portfolio artifact that changes occasionally; nothing in `roadmap.md` asks for
  continuous deployment here, and building one would be scope this item did not need.

## Done when

- [x] An ADR names the hosting choice and the reasoning (cost, manifest reuse, the one-node
      reality), accepted before any manifest work in this item starts. **`adr/0026`**, written and
      accepted in this pass — hosting/domain were the author's own prior calls; the VPS tier
      (Timeweb Cloud MSK 80, with real sizing math), the image-delivery mechanism (build-on-VPS,
      import into containerd), and the TLS approach (cert-manager + Let's Encrypt, HTTP-01) are this
      ADR's own contribution, argued with alternatives.
- [ ] A real request (`curl`, or a browser) from a network unrelated to the deployment reaches the
      public HTTPS URL, receives a valid certificate with no browser warning, and `/healthz/live`
      returns 200 — verified live, not asserted from the manifests. **Not done — no real VPS exists
      yet for this session to deploy to.** `runbooks/public-deploy.md` §11 has the exact commands a
      future session with real VPS access should run to close this box; leaving it unchecked here
      rather than asserting it from the manifests, matching Stage 6/7's own load-report honesty
      discipline.
- [ ] The seeded demo site's public key and demo operator's Keycloak credentials work against this
      environment exactly as `local-dev.md`'s "Getting a working operator session locally" section
      describes for local — verified with the same direct-grant curl pattern, pointed at the public
      Keycloak issuer instead of `127.0.0.1:8081`. **Not done — same reason as above**; the
      direct-grant command against `auth.ago.golyakov.net` is written and ready in
      `runbooks/public-deploy.md` §11, not run.
- [x] A new runbook section (in `runbooks/k8s-local.md` or a new `runbooks/public-deploy.md` —
      whichever this item finds reads more honestly once written) covers bring-up, where secrets
      live, and how to redeploy after a change, to the same "a session with no memory can repeat
      this" bar every other runbook is held to. **`runbooks/public-deploy.md`**, new file — a
      dedicated runbook reads more honestly than folding this into `k8s-local.md`, since large parts
      of it (provisioning, DNS, secret generation) are steps only the author can perform, marked
      **(you)** throughout, distinct from the **(session)** steps a future session with real SSH
      access can run directly. Its own status line states plainly that it has not been run against a
      real node yet.
- [x] No secret value appears in any file this item commits — the same audit this repository already
      applies everywhere (`repositories.md`). `k8s/overlays/demo/.env.example` and `tls.yaml`'s ACME
      `email` field carry placeholder text only (`<generate-a-real-password-do-not-commit>`, a
      non-real `letsencrypt-admin@golyakov.net` address under the domain itself, never the author's
      own personal inbox) — audited by re-reading every new/changed file in this pass before
      handback.

## Open questions — resolved 2026-08-24, author's own decision

- **Hosting target: k3s VPS**, not a managed Kubernetes offering — the author's explicit call,
  choosing lower cost over `deploy/k8s/base/`'s manifests transferring with zero new surface. This
  item's own ADR — **now written, `adr/0026`** — covers the provisioning work `k8s-local.md` never
  had to (Ubuntu 24.04 LTS, the k3s install command with Traefik disabled, confirming the Gateway
  API's NGINX Gateway Fabric install from `k8s-local.md` transfers onto k3s unchanged) in
  `runbooks/public-deploy.md`; the tier itself (Timeweb Cloud MSK 80) and the reasoning are in the
  ADR.
- **Domain: the author's own `golyakov.net`**, with `*.ago.golyakov.net` subdomains — `chat.ago.
  golyakov.net` (Api/hub traffic), `console.ago.golyakov.net` (operator console), `demo-shop1.ago.
  golyakov.net` / `demo-shop2.ago.golyakov.net` (seeded demo tenant sites for the widget to embed
  on), with the author open to adding more subdomains under the same `*.ago.golyakov.net` pattern for
  any further tool this stage or a later one needs. No separate domain purchase needed. This item's
  ADR — **`adr/0026`** — records the exact subdomain-to-service mapping, including one addition the
  original plan above did not name: `auth.ago.golyakov.net` for Keycloak, required by `5-05`'s own
  exact-issuer-match validation and `8-02`'s planned browser redirect, neither of which works against
  an internal-only Keycloak hostname. DNS is not yet actually configured (no VPS exists to point it
  at) — the ADR's table is the plan `runbooks/public-deploy.md` §2 hands to the author to apply by
  hand once a VPS exists.

Both answered — this item is no longer blocked. Status changed to `ready`; still depends on `8-00`
landing first per the author's own explicit sequencing. Design/prep work in this pass (`adr/0026`,
`runbooks/public-deploy.md`, `ago-deploy/k8s/overlays/demo/`) does not itself require `8-00` to have
landed — nothing here builds an image — but the live bring-up in `public-deploy.md` does need
whichever base image `8-00` ships, per this item's own "Depends on" line above.
