# Repository structure and naming

Topology and the reasoning behind it: `docs/architecture/repositories.md`, `adr/0012`. This file is
the layout itself.

## The repositories

All of them are siblings inside one parent folder, and all of them are public:

```
ago/
  ago-root/        this one — docs, ADRs, conventions, .claude skills, backlog, reviews/, load/
  ago-platform/    Ago.Platform.*    -> NuGet packages
  ago-chat/        Ago.Chat.*        -> Docker images (Api, Worker, Webhooks)
  ago-calendar/    Ago.Calendar.*    -> Docker images (Api, Worker)  [Stage 20, adr/0027]
  ago-widget/      embeddable script -> versioned CDN bundle
  ago-console/     operator SPA
  ago-landing/     the public marketing page
  ago-deploy/      docker-compose, Kustomize, seed
```

`ago-business` is the one exception to "all of them are public": it holds commercial strategy and is
private. No technical decision lives there.

**`docs/reviews/<date>-<topic>.md`** is where an investigation lands when its output is *evidence for
a decision not yet made*. Added 2026-08-26 with the platform-boundary review, because the four
existing homes each say the wrong thing about such a document: `architecture/` describes what is,
so it would make an open question read as settled; `adr/` records a decision, and there is not one
yet; `backlog/` holds work, and a review is not work to do; `conventions/` holds rules. The
precedent is `load/reports/`, which already separates "what we measured" from "what we decided".
A review is dated, never revised after the decision it fed, and linked from whatever ADR that
decision produces — the ADR is the live document, the review is why it says what it says.

Cross-repository links in documentation are always relative (`../ago-root/docs/...`), so the tree can
be moved or renamed without rewriting them. From `ago-root` the others are additionally reachable as
`platform/`, `chat/`, `widget/`, `console/`, `deploy/` through Windows junctions — a convenience for
sessions, gitignored, and recreated after any move (`runbooks/workspace.md`). Each repository is
still committed in its own checkout.

## `ago-platform`

```
src/
  Ago.Platform.Kernel/                Result<T>, Error, id primitives, IClock, IIdGenerator
  Ago.Platform.Abstractions/          technical ports: IEventPublisher, ICache, IFileStorage,
                                      IRateLimiter, IUnitOfWork, IConnectionRegistry
  Ago.Platform.Messaging.RabbitMq/
  Ago.Platform.Persistence.Postgres/  UoW, transactions, outbox/inbox plumbing, EF conventions
  Ago.Platform.Caching.Redis/
  Ago.Platform.Storage.S3/
  Ago.Platform.Realtime/              connection registry, node routing, hub base types
  Ago.Platform.Resilience/            timeout, retry, circuit breaker, bulkhead policies
  Ago.Platform.Hosting/               IProductModule, AddPlatformKernel, SystemClock - and nothing
                                      else: every host of every product must reference this one, so
                                      what it declares, every host pays for (adr/0046)
  Ago.Platform.Observability/         OpenTelemetry wiring: AddPlatformObservability, Otel:* options,
                                      the "Ago.*" ActivitySource/Meter wildcards. Web hosts only -
                                      its Prometheus scrape endpoint needs an IEndpointRouteBuilder
tests/
  Ago.Platform.Tests/
  Ago.Platform.Architecture.Tests/    the platform's own smaller half of the arch-test list -
                                      Kernel stays dependency-free, nothing here ever sees Ago.Chat.*
  Ago.Platform.Integration.Tests/
```

`Ago.Platform.Kernel` is deliberately narrow: primitives with no dependencies, small enough to read
in one sitting. There is no project named `Common`, `Shared`, `Utils` or `Core` here or anywhere —
those names are where unrelated code goes to hide.

## `ago-chat`

```
src/
  Ago.Chat.Domain/
  Ago.Chat.Application/
    Abstractions/                     product-specific ports only
    UseCases/
      SendMessage/
        SendMessage.cs                the command
        SendMessageHandler.cs
        SendMessageValidator.cs
      GetConversationHistory/
    Mapping/                          domain event -> integration contract
  Ago.Chat.Contracts/                 integration events, public and versioned
  Ago.Chat.Infrastructure.Postgres/   EF model, repositories, Dapper read stores
  Ago.Chat.Infrastructure.MySql/      Stage 10
  Ago.Chat.Module/                    IProductModule: DI, endpoints, hubs, consumers
  Ago.Chat.Api/                       host: connections, commands, queries
  Ago.Chat.Worker/                    host: consumers, outbox dispatch, assignment, jobs
  Ago.Chat.Webhooks/                  host: outbound delivery to tenant endpoints
tests/
  Ago.Chat.Domain.Tests/
  Ago.Chat.Application.Tests/
  Ago.Chat.Architecture.Tests/
  Ago.Chat.Integration.Tests/
  Ago.Chat.Concurrency.Tests/
```

One folder per use case, holding everything that use case owns. A reviewer opening
`UseCases/SendMessage/` should see the whole feature without navigating elsewhere — the
vertical-slice half of the structure, coexisting with the layer rule rather than replacing it.

## `ago-widget` and `ago-console`

```
ago-widget/  src/  (protocol, ui, bootstrap)   demo/  (hostile host page)   dist/
ago-console/ src/                              e2e/
```

The widget's demo page exists to prove style and global isolation against a deliberately hostile
host, and it is part of the deliverable, not a toy.

## `ago-deploy`

```
docker/                  compose for the fast inner loop
k8s/base/                workloads, services, probes, resources
k8s/overlays/local/      Docker Desktop cluster
seed/                    demo tenant, operator, MinIO bucket
```

Manifests carry operational concerns only. Business behaviour — per-site CORS, tenant rate limits,
auth decisions — lives in application code where it is testable (`architecture/edge.md`).

## Naming rules that matter

- Project names mirror namespaces exactly.
- Files are named for their single public type.
- SQL objects are `snake_case`, C# is `PascalCase`, and the mapping is configured once rather than
  per entity.
- Configuration keys are hierarchical and match their options class:
  `Messaging:RabbitMq:PrefetchCount` binds to `RabbitMqOptions`. Every options class is validated at
  startup — a typo in a key must fail the pod, not silently disable a feature.
- Package versions follow SemVer; a breaking platform port change is a major bump with a changelog
  entry (`architecture/repositories.md`).
