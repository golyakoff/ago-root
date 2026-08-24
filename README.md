# AGO Platform

> **Status: live.** A shop can embed AGO Chat right now — try it at the links below. This is a
> portfolio project: **AGO Platform** is a backend platform (hosting, realtime transport, messaging,
> persistence, caching, object storage, observability); **AGO Chat** is the first product on it, a
> customer-support chat a shop embeds with one script tag. **AGO Calendar** (planned, `docs/roadmap.md`
> Stage 20) is the second — a real product decision, not a stand-in, chosen because it shares nothing
> with chat except the platform underneath and proves the platform boundary holds for an unrelated
> product, not just in theory. The whole thing exists to demonstrate concurrency, database work under
> load, message-broker work, and Clean Architecture, in a form another engineer can review — end to
> end, not just in slides.

## Try it live

Two independent demo shops, deliberately different-looking, on the same running deployment — proof
that tenant isolation is real, not asserted:

| | Shop's own page (widget) | Operator login |
|---|---|---|
| **Tenant 1** | [demo-shop1.reserve-me.ru](https://demo-shop1.reserve-me.ru) | `demo-operator` / `demo-operator-password` at [console.reserve-me.ru](https://console.reserve-me.ru) |
| **Tenant 2** | [demo-shop2.reserve-me.ru](https://demo-shop2.reserve-me.ru) | `demo-operator-2` / `demo-operator-2-password` at [console.reserve-me.ru](https://console.reserve-me.ru) |

Open a shop's page, send a message through the widget in the corner; open the console in a second
browser context (a private/incognito window — the console's session is a cookie, so one identity per
browser context), log in with that tenant's own operator credential, and answer it. Neither operator
login can see the other tenant's conversations — every value above is a real, working, deliberately
public credential, safe to publish (it only ever grants access to its own disposable demo data, never
anything real).

## Stack

.NET 10 · ASP.NET Core Minimal API + SignalR · PostgreSQL (EF Core writes, Dapper reads) · RabbitMQ
(Kafka joins as a second, swappable implementation in Stage 9) · Redis · S3/MinIO · Kubernetes (k3s in
production, Docker Desktop locally) · OpenTelemetry → Prometheus/Grafana/Jaeger

## Architecture, in one diagram

```
   visitor page                 operator console
  [ widget.js ]                 [    SPA      ]
        |                              |
        |  WebSocket (SignalR) + REST  |          file bytes go straight to storage,
        +--------------+---------------+          never through the API  ---------+
                       |                                                          |
                 [ NGINX Gateway ]  TLS, coarse rate limits, least_conn,          |
                       |           no sticky sessions (edge.md)                   |
                       v                                                          |
        +--------------------------------+                                        |
        |  Chat.Api (N replicas)         |  holds connections, handles commands,   |
        |  Minimal API + SignalR hubs    |  serves read queries, signs upload URLs |
        +----+--------------+------------+                                        |
             |              |                                                     |
   outbox write        publish / subscribe                                        |
             |              |                                                     |
             v              v                                                     v
   +----------------+  +--------------+                              +--------------------+
   |   PostgreSQL   |  |   RabbitMQ   |                              | S3 / MinIO         |
   | source of truth|  |  (-> Kafka)  |                              | attachments        |
   +----------------+  +------+-------+                              +--------------------+
             ^                |                                                     ^
             |                v                                                     |
   +---------+-----------------------------+                                        |
   |  Chat.Worker (N replicas)             |  outbox dispatcher, persistence,       |
   |  background consumers                 |  assignment engine, thumbnails, -------+
   +---------------------------------------+  orphan cleanup
                       |
                  +----+-----+
                  |  Redis   |  cache + rate limits + connection registry + presence
                  +----------+
```

Three hosts (`Api`, `Worker`, a third `Webhooks` bulkhead not pictured) share the same
Application/Domain code but never call each other synchronously — the broker is the only path
between them. Full detail: [docs/architecture/overview.md](docs/architecture/overview.md).

## Numbers (Stage 7)

Every figure below is copied verbatim from
[`load/reports/2026-08-24-stage-7-summary.md`](load/reports/2026-08-24-stage-7-summary.md) — read
that file before trusting any of these as more than what they are. **All nine load scenarios ran at
roughly 1-3% of `nfr.md`'s stated production scale**, on one development workstation, not the
provisioned cluster — a checkmark below means "held at this reduced scale," never "meets the full
target."

- **300 concurrent WebSocket connections**, 0 failures, 0 unexpected drops across a 90 s hold
  (1.5% of the 20,000-connection target) — `connection-storm`.
- **35.4 msg/s sustained ingest**, zero errors across 10,672 sends, 240 s plateau (~1.2% of the
  3,000 msg/s target) — `steady-ingest`.
- **Every p50/p95 latency target was missed at this reduced scale**, in every scenario, without
  exception — stated here because the report states it, not smoothed away.
- **3 of 5 correctness bullets passed** at reduced scale (no duplicate persisted messages despite
  at-least-once delivery; operator capacity never exceeded; no unbounded memory growth under
  sustained overload); **1 was not run** (pod-kill mid-load, blocked by a tool permission denial,
  not a failure); **1 was not measured by any scenario** (in-conversation message ordering).
- **One real regression confirmed fixed**: the per-tenant webhook bulkhead, which `6-06` had found
  never rejecting anything, correctly rejected 152 excess deliveries under the identical saturation
  burst that first found the bug.
- **One real bug found and filed, still open**: operator capacity never releases on an ordinary
  conversation close (only on a bulk disconnect sweep), capping the assignment queue's throughput
  under sustained traffic — [`6-09`](docs/backlog/6-09-release-operator-capacity-on-close.md).

## Decisions — every accepted ADR

| # | Decision |
|---|---|
| [0001](docs/adr/0001-record-architecture-decisions.md) | Record architecture decisions — this index exists because the project decided to keep one |
| [0002](docs/adr/0002-clean-architecture-layering.md) | Clean Architecture layering and the dependency rule — Domain knows nothing, Application knows only Domain |
| [0003](docs/adr/0003-platform-product-split-and-two-hosts.md) | Platform/product split, modular monolith, two hosts — Api and Worker never call each other synchronously |
| [0004](docs/adr/0004-postgres-ef-writes-dapper-reads.md) | PostgreSQL, EF Core for writes, Dapper for reads — write-model safety without paying its cost on hot reads |
| [0005](docs/adr/0005-transactional-outbox.md) | Transactional outbox for reliable publishing — a state change and its event commit in one transaction |
| [0006](docs/adr/0006-broker-abstraction.md) | Broker abstraction at topic + partition key + at-least-once — RabbitMQ today, Kafka behind the same port |
| [0007](docs/adr/0007-connection-registry-instead-of-backplane.md) | Connection registry instead of a SignalR backplane — a Redis-backed "who holds connection X" table |
| [0008](docs/adr/0008-presigned-direct-uploads.md) | Presigned direct-to-storage uploads — attachment bytes never pass through the API |
| [0009](docs/adr/0009-redis-is-not-truth.md) | Redis is a cache and coordination store, never truth — losing it degrades, never corrupts |
| [0010](docs/adr/0010-no-sticky-sessions.md) | No sticky sessions at the edge — any node can hold any connection, by design |
| [0011](docs/adr/0011-utc-datetimeoffset-everywhere.md) | All instants are UTC `DateTimeOffset`, rendered per request — ordering never depends on wall-clock time |
| [0012](docs/adr/0012-multi-repo-with-package-boundary.md) | Multiple repositories, platform published as packages — the platform genuinely cannot see the product |
| [0013](docs/adr/0013-deployables-and-webhook-bulkhead.md) | Three deployables, split by failure profile, and outbound webhooks as a bulkhead — a slow third party can't stall chat |
| [0014](docs/adr/0014-nginx-gateway-fabric-instead-of-ingress-nginx.md) | NGINX Gateway Fabric (Gateway API) instead of ingress-nginx — the latter was archived with no further releases |
| [0015](docs/adr/0015-ci-packs-ago-platform-from-source.md) | `ago-chat`'s CI packs `ago-platform` from source, no hosted feed yet — superseded by 0018 |
| [0016](docs/adr/0016-rbac-authorization-model.md) | Granular permissions (RBAC), scoped per tenant, as the authorization model |
| [0017](docs/adr/0017-generic-outbox-inbox-writer.md) | Outbox/inbox writer is generic over `DbContext`, not per-product — one mechanism, reusable by any product |
| [0018](docs/adr/0018-github-packages-nuget-feed.md) | `ago-platform` publishes to GitHub Packages; `ago-chat`'s CI restores from it — a real hosted feed, not source-packing |
| [0019](docs/adr/0019-partitioned-messages-widens-the-unique-index.md) | Partitioning `messages` widens its unique index to include `created_at` — a real partitioning-scheme trade-off |
| [0020](docs/adr/0020-fanout-delivery-bypasses-the-outbox.md) | Node-delivery fan-out publishes directly, bypassing the outbox — delivery is best-effort, persistence is not |
| [0021](docs/adr/0021-assignment-engine-skip-locked-vs-redis-lock.md) | Operator assignment: `SKIP LOCKED` (default) vs. a per-operator Redis lock — the database stays the arbiter |
| [0022](docs/adr/0022-oidc-keycloak-operator-authentication.md) | OIDC via Keycloak replaces the operator dev-auth stub — real identity, not a hand-rolled token |
| [0023](docs/adr/0023-console-framework-react.md) | React for `ago-console` — decided against a widened scope, unblocked Stage 5 |
| [0024](docs/adr/0024-webhook-signature-and-secret-lifecycle.md) | Webhook signature scheme and secret lifecycle — HMAC, rotation, replay protection |
| [0025](docs/adr/0025-otlp-direct-to-jaeger-no-collector.md) | Direct OTLP export to Jaeger, no collector — one fewer moving part at this scale |
| [0026](docs/adr/0026-k3s-vps-public-hosting.md) | k3s VPS hosting, `*.reserve-me.ru` domain plan, VM sizing, and TLS — the deployment this README's links point at |
| [0027](docs/adr/0027-operator-identity-across-products.md) | Operator identity across products — separate per-product entities, unified only through Keycloak |

## What I would do differently

- **The outbox, retry/dead-lettering, and cross-node connection fan-out are hand-built** where a
  production team should reach for something off the shelf (MassTransit for the first two, a SignalR
  Redis backplane for the third, in three lines). They're hand-built here because demonstrating the
  mechanism is the point of a portfolio project, not because it's the right call for a real team
  shipping this tomorrow.
- **The platform/product repository split has a real coordination cost**: a change that genuinely
  spans both repositories is four separate branches and merge requests — platform, product, deploy
  manifests, docs — each rebased onto its own `main`
  ([`architecture/repositories.md`](docs/architecture/repositories.md)). It's the right shape for
  proving the platform boundary is real (the platform genuinely cannot import product code), but it
  is real friction, paid on every cross-cutting change, and a single-repo monorepo with enforced
  package boundaries would very likely be the more pragmatic choice for an actual team.
- **The local cluster is one node** — no pod anti-affinity, no real node-drain or network-partition
  testing has ever run against it
  ([`runbooks/k8s-local.md`](docs/runbooks/k8s-local.md#known-limits-of-this-setup)). The public VPS
  deployment above is the same shape, for the same reason (cost) — it is explicitly a demo, not
  something carrying an uptime claim.
- **Stage 7's load numbers are honest, but small.** Every scenario ran at 1-3% of the target scale on
  a development workstation, not the provisioned cluster — see the Numbers section above and the full
  report it's copied from. A full-scale run is real, unfinished work, not a footnote.
- **A real bug reached this README's own live demo before being caught**: the widget's visitor-side
  send silently failed against every real deployment until this session's own verification pass found
  it (missing a required hub-invocation argument — [`5-12`](docs/backlog/5-12-fix-widget-visitor-send-missing-client-message-id.md)).
  It's a reminder that "the tests pass" and "a stranger can actually use it" are different bars, and
  only the second one is the one that matters to a user.

## Where to read

| | |
|---|---|
| What it is and why | [docs/vision.md](docs/vision.md) |
| How it is shaped | [docs/architecture/overview.md](docs/architecture/overview.md) |
| Why decisions were made | [docs/adr/](docs/adr/) |
| What gets built, in what order | [docs/roadmap.md](docs/roadmap.md) |
| How the public deployment above was built | [docs/runbooks/public-deploy.md](docs/runbooks/public-deploy.md) |
| Rules for contributors and AI sessions | [CLAUDE.md](CLAUDE.md), [SKILLS.md](SKILLS.md) |

## How this repository is worked on

Implementation is done in AI sessions (Claude Code) driven by the rules in this repository:
[CLAUDE.md](CLAUDE.md) holds the non-negotiables, [SKILLS.md](SKILLS.md) indexes the procedures, and
`docs/adr/` keeps decisions stable across sessions that share no memory. That tooling is public on
purpose — directing this kind of work reproducibly, at the scale this repository's own commit history
shows, is part of what the project demonstrates.
