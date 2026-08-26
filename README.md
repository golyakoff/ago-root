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

.NET 10 · ASP.NET Core Minimal API + SignalR · PostgreSQL (EF Core writes, Dapper reads) · RabbitMQ,
behind a port that declares topic, partition key and at-least-once rather than hiding them
([`adr/0006`](docs/adr/0006-broker-abstraction.md)) · Redis · S3/MinIO · Kubernetes (k3s in
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
   | source of truth|  | behind a port|                              | attachments        |
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

> There is a real server now, and these numbers predate it.
> [`7-10`](docs/backlog/7-10-load-run-on-the-provisioned-server.md) re-runs the same scenarios against
> the public deployment to find where it actually stops and what stops it. Deliberately queued rather
> than deleted: what a cheap, named, externally-hosted box holds is a far more useful statement than
> either an apology or a missing section.

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

## Decisions

Every choice worth arguing about is an ADR, written when the decision was made and naming the
alternative that lost: **[docs/adr/](docs/adr/)** — 51 so far, indexed in
[docs/adr/README.md](docs/adr/README.md), which is the list that stays current. This README does not
keep a copy of that index; the copy it used to keep had stopped at 0027 and was quietly wrong.

These are the ones a reviewer usually asks about first, and each answers "why on earth" rather than
asserting a preference:

| | |
|---|---|
| [0006](docs/adr/0006-broker-abstraction.md) | **Why not MassTransit.** The port declares topic, partition key and at-least-once instead of hiding them, because a generic `Send(object)` makes the ordering guarantee unimplementable — and it leaks *silently*, which is worse than leaking loudly. MassTransit is named there as the right choice for production work with a deadline, with the trigger that would bring it in |
| [0007](docs/adr/0007-connection-registry-instead-of-backplane.md) | **Why not a SignalR Redis backplane.** A backplane broadcasts to every node and offers neither ordering nor delivery — the two things this product is. Nodes register their connections in Redis and delivery is targeted at the nodes that own them, so cost scales with *involved* nodes, not cluster size |
| [0005](docs/adr/0005-transactional-outbox.md) | A state change and its integration event commit in one transaction; publishing is a separate step. Nothing publishes from inside a request handler |
| [0021](docs/adr/0021-assignment-engine-skip-locked-vs-redis-lock.md) | Operator assignment uses `SKIP LOCKED` rather than a Redis lock — the decision that keeps a capacity check inside the transaction that depends on it |
| [0009](docs/adr/0009-redis-is-not-truth.md) | Redis is cache and coordination, never truth. Losing it degrades the system; it never corrupts it |
| [0056](docs/adr/0056-schema-migrations-are-a-separate-deployable.md) | Migrations are their own deployable, and a host refuses to start against a schema older than its own build — written after a redeploy left the API three migrations behind while every page still returned 200 |
| [0027](docs/adr/0027-operator-identity-across-products.md) | Operator identity across products — the decision that keeps a second product additive instead of a fork |

## Where to read

| | |
|---|---|
| What it is and why | [docs/vision.md](docs/vision.md) |
| How it is shaped | [docs/architecture/overview.md](docs/architecture/overview.md) |
| Why decisions were made | [docs/adr/](docs/adr/) |
| Where it is weak, and what a team with a deadline would do differently | [docs/known-limits.md](docs/known-limits.md) |
| What gets built, in what order | [docs/roadmap.md](docs/roadmap.md) |
| How the public deployment above was built | [docs/runbooks/public-deploy.md](docs/runbooks/public-deploy.md) |
| Rules for contributors and AI sessions | [CLAUDE.md](CLAUDE.md), [SKILLS.md](SKILLS.md) |

## How this repository is worked on

Implementation is done in AI sessions (Claude Code) driven by the rules in this repository:
[CLAUDE.md](CLAUDE.md) holds the non-negotiables, [SKILLS.md](SKILLS.md) indexes the procedures, and
`docs/adr/` keeps decisions stable across sessions that share no memory. That tooling is public on
purpose — directing this kind of work reproducibly, at the scale this repository's own commit history
shows, is part of what the project demonstrates.
