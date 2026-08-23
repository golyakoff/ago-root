# Public deployment target: hosting, TLS, seeded demo tenant

- **Stage**: 8
- **Status**: blocked
- **Depends on**: nothing new architecturally — reuses `1-05-seed-demo-tenant.md`'s seed script and
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
- **Note added 2026-08-25, author's own reminder — resolve when this item actually starts, not before**:
  every `Ago.Chat.*` host's shared `Dockerfile` currently builds its final stage from
  `mcr.microsoft.com/dotnet/aspnet:10.0` (Debian-based). For a real public deployment, switch to a
  smaller production base image before shipping — current .NET guidance (verified 2026-08-25, not
  assumed) leans toward **Ubuntu Chiseled** (`mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled`) as
  the default for production with no special requirements — smaller than Alpine's own musl-based image
  in practice, no shell/package manager (smallest attack surface), and glibc-based so it avoids the
  musl-compatibility risk Alpine carries for native dependencies. **Alpine**
  (`mcr.microsoft.com/dotnet/aspnet:10.0-alpine`) is the fallback if Chiseled's own lack of a shell
  breaks something this project's `Dockerfile`/entrypoint actually needs, or if a native dependency in
  this project's stack (Npgsql, StackExchange.Redis, RabbitMQ.Client) turns out not to be musl-clean —
  verify against the real image before deciding, not assumed clean either way. Chiseled images drop ICU
  by default (no globalization support) unless the `-extra` variant is used — check whether this
  project's own `DateTimeOffset`-only, UTC-everywhere convention (`docs/conventions/date-and-time.md`)
  means culture-specific formatting was never a real dependency here, before pulling in the larger
  `-extra` variant just to be safe.

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

- [ ] An ADR names the hosting choice and the reasoning (cost, manifest reuse, the one-node
      reality), accepted before any manifest work in this item starts.
- [ ] A real request (`curl`, or a browser) from a network unrelated to the deployment reaches the
      public HTTPS URL, receives a valid certificate with no browser warning, and `/healthz/live`
      returns 200 — verified live, not asserted from the manifests.
- [ ] The seeded demo site's public key and demo operator's Keycloak credentials work against this
      environment exactly as `local-dev.md`'s "Getting a working operator session locally" section
      describes for local — verified with the same direct-grant curl pattern, pointed at the public
      Keycloak issuer instead of `127.0.0.1:8081`.
- [ ] A new runbook section (in `runbooks/k8s-local.md` or a new `runbooks/public-deploy.md` —
      whichever this item finds reads more honestly once written) covers bring-up, where secrets
      live, and how to redeploy after a change, to the same "a session with no memory can repeat
      this" bar every other runbook is held to.
- [ ] No secret value appears in any file this item commits — the same audit this repository already
      applies everywhere (`repositories.md`).

## Open questions

- **Which hosting target**: a small managed Kubernetes offering, or a k3s VPS. `roadmap.md` leaves
  this genuinely open ("a small managed cluster or a k3s VPS"), and nothing else in the repository
  decides it. This is the author's call, likely driven by cost and by how much of the existing
  Kustomize/NGINX Gateway Fabric setup should transfer unchanged — a managed Kubernetes offering
  keeps `deploy/k8s/base/` and `adr/0014`'s Gateway API choice intact with the least new surface; a
  bare k3s VPS still supports the Gateway API but adds provisioning work `k8s-local.md` never had to
  cover for the Docker-Desktop-managed local cluster.
- **Which domain name**, and who owns/pays for it and any hosting cost. Not decided anywhere in this
  repository. `CLAUDE.md`'s "do not invent numbers, benchmarks, or 'typical' production figures"
  means this item cannot silently assume a specific provider, domain, or cost figure — the author
  states both, and this item's ADR records them once chosen.

This item does not start until both are answered.
