# the deployment moves to a provider that issues the documents

- **Stage**: 25
- **Status**: ready — **and it is the launch's critical path**
- **Depends on**: `24-07` established the question. Nothing depends on this that can start before it.
- **Decision**: the author's, 2026-09-06 — **Fornex is out**. The provider question below is open.

## Goal

The machine holding every tenant's and every visitor's personal data sits somewhere we can produce a
document about, from a provider that issues one.

## What decided this, 2026-09-06

The author's call: **Fornex does not provide the documents `152-ФЗ` compliance needs**, so launching on
it means launching in breach. That is not a fact about where the machine physically stands — `24-07`'s
RIPE check makes Russia likely — it is a fact about **evidence**. An inspection asks for a document,
and a provider that does not issue one cannot be made to.

The named alternatives are **VK Cloud, Yandex Cloud or Selectel**: providers that sell into this market
specifically on being able to answer this question in writing.

## Why this is bigger than a hostname change

Everything is on one machine (`adr/0026`). Verified 2026-09-06:

- **Eighteen Kubernetes deployments**, including the stateful ones — Postgres (holding both `ago_chat`
  and `keycloak`), Redis, RabbitMQ, MinIO, Keycloak — plus Prometheus, Grafana, Jaeger, Alertmanager.
- **k3s itself**, and the NGINX Gateway Fabric edge.
- **Node services outside Kubernetes**: Postfix and OpenDKIM (`adr/0040`'s amendment — mail never
  leaves the machine, so there is no sending provider to repoint), and the backup systemd units
  (`k8s/backup/`, which `redeploy.sh` and `kubectl apply` both deliberately do not reach).
- **Seven DNS records and one certificate** with seven SANs, whose renewal is HTTP-01 — so the cutover
  order matters the same way `22-09` proved it does, in reverse.
- **The Telegram relay** (`adr/0070`), which egresses through the author's own personal endpoint
  because direct calls from *this* node failed. Whether that is still needed from a different network
  is a real question the move gets to re-ask.

## The open question, and it is two questions

**Which provider** is the author's. But the choice that actually shapes the work is the second one:

### Lift and shift, or adopt managed services

| | Lift and shift | Managed services |
|---|---|---|
| What moves | One VM, k3s, every manifest as-is | Postgres, Redis, RabbitMQ and object storage become the provider's; only the app deployments stay ours |
| Migration risk | Lower — the shape is known and `k8s/overlays/` already describes it | Higher — four ports get new adapters' worth of configuration, and `adr/0026`'s sizing stops applying |
| Operational burden after | Unchanged: backups, upgrades, disk, and a single node whose loss is total | Much lower for exactly the things that are hardest to do well alone — Postgres backups and point-in-time recovery, broker upgrades |
| Compliance paperwork | We hold the location document; everything above it is ours to evidence | Usually more of it comes from the provider, which is the entire reason this item exists |
| Cost | Comparable to today | Materially higher, and per-service |
| What it costs the portfolio argument | Nothing | **Something real**: `adr/0004`, `adr/0006` and `adr/0026` are about operating these things, and handing them to a managed service removes the part a reviewer is being shown |

That last row is why this is not an obvious call. This project's stated purpose includes demonstrating
database and broker work under load; managed services do not remove the code, but they do remove the
operating.

**A third shape exists and should be named rather than discovered later:** move as-is *now* to unblock
the launch, and treat managed services as a separate later decision. It costs one migration extra if
managed wins eventually, and it is the only option that does not put a new-provider learning curve on
the critical path two weeks before a launch.

## Scope

- Choose the provider and the shape, and record both in an ADR that **supersedes `adr/0026`** — that
  ADR's whole reasoning is about a specific 6 GB VPS and its headroom.
- Move the deployment, in an order that keeps the certificate valid throughout — `22-09`'s own Outcome
  has the shape of that trap, and this is the same trap with the arrow reversed: **DNS must point at
  the new node before its certificate can be issued, and the old node must keep serving until it does.**
- Obtain and file the location confirmation from the new provider. That is `24-07`'s remaining
  Done-when, and it closes only here.
- Re-ask whether the Telegram relay is still needed from the new network (`adr/0070`).
- Update `adr/0026`, `adr/0050` (where backups are pulled from), `public-deploy.md`, `personal-data.md`'s
  residency section and `processing-instruction-facts.md`'s Element 5.

## Out of scope

- The compliance checklist itself — that is `25-02`, and it is what says whether *everything else* is
  ready, not just the machine.
- Any change to what the application does. This is a move, and a move that changes behaviour cannot be
  verified as a move.

## Done when

- [ ] The deployment runs at the new provider, with every check `smoke.sh` makes passing there.
- [ ] A written location confirmation from the provider is filed, and `24-07` can close against it.
- [ ] An ADR supersedes `adr/0026`, stating the provider, the shape, and what was given up.
- [ ] Backups are being taken and pulled from the new node, verified by the artifact and its age —
      not by the absence of an error (`take-a-backup`'s own third failure mode).
- [ ] The old node is decommissioned only after a backup from the new one has been restored somewhere
      and read.

## Open questions

- **Which provider, and lift-and-shift or managed** — the table above, and it is the author's.
- **What the move costs in downtime the author is willing to accept.** With no live tenants it is
  nearly free; that stops being true on the day the first one signs up, which is the same deadline
  everything else here is measured against.
