# Clean Architecture in this project

This file is the arbiter for "where does this code go". When a session is unsure, it reads this file
and states the rule it applied.

## Two orthogonal splits

There are **two** boundaries in this codebase, and confusing them is the most likely way to make a
mess:

1. **Layers** (vertical): Domain -> Application -> Infrastructure -> Hosts. Enforced by the
   dependency rule.
2. **Platform vs product** (horizontal): AGO Platform is the reusable substrate; AGO Chat is the
   first product on it. AGO Calendar will be the second (`adr/0027` on why its Operator is not
   `Ago.Chat.Domain.Operator` reused, even though the two look similar).

A file's location is the intersection: "product Chat, layer Application" or "platform, layer
Infrastructure".

## The one rule

**Source-code dependencies point inwards only.** Inner layers know nothing about outer ones - not
the type, not the namespace, not the NuGet package.

```
        Hosts (Platform.Api, Platform.Worker)   composition root, DI wiring, endpoints/hubs
                       |
        Infrastructure (platform + product)     adapters: Postgres, RabbitMQ, Redis, S3, clock
                       |
        Application (per product)               use cases + the ports they need
                       |
        Domain (per product)                    entities, value objects, invariants, domain events
```

Platform code sits at the same layers, but is never allowed to depend on a product. The arrow
between them points one way only: **products depend on the platform; the platform never knows a
product exists.**

## Project layout

The full layout lives in `docs/conventions/naming-and-structure.md`; the shape that matters here is:

```
ago-platform (NuGet packages)          ago-chat (Docker images)
  Ago.Platform.Kernel                    Ago.Chat.Domain
  Ago.Platform.Abstractions              Ago.Chat.Application
  Ago.Platform.Messaging.RabbitMq        Ago.Chat.Contracts
  Ago.Platform.Persistence.Postgres      Ago.Chat.Infrastructure.Postgres
  Ago.Platform.Caching.Redis             Ago.Chat.Module
  Ago.Platform.Storage.S3                Ago.Chat.Api | Worker | Webhooks   <- the deployables
  Ago.Platform.Realtime
  Ago.Platform.Resilience
  Ago.Platform.Hosting
```

Two things follow from this being two **repositories** rather than two folders (`adr/0012`):

- The platform cannot reference a product even by accident - it has no access to the source.
- The hosts belong to the product, because a host must reference the module it composes. The
  platform contributes `Ago.Platform.Hosting` (the `IProductModule` contract, health checks,
  telemetry, configuration binding) as a library.

## What qualifies as platform

A candidate is platform only if **all** of these hold:

- It contains no domain concept. `IEventPublisher` qualifies; `IConversationRepository` never will.
- A second product would plausibly use it unchanged.
- It can be described without naming chat, visitors, or operators.

Otherwise it stays in the product, even if it feels generic. The failure mode of a platform is
premature generalisation: an abstraction extracted from exactly one caller is a guess about the
second one. Until a real second product exists, treat anything ambiguous as product code and
promote it later - promotion is cheap, and the arch tests make the illegal direction impossible to
introduce quietly. AGO Calendar (Stage 20) is now that second caller for real, and `adr/0027` is a
worked example of the test above rejecting a tempting-looking promotion (a shared `Operator`
aggregate) even with a genuine second caller in hand - a second caller makes promotion *possible*,
not automatically correct.

## Layer by layer

### Domain - `Ago.Chat.Domain`

Contains: entities (`Conversation`, `Message`, `Operator`), value objects (`SiteId`, `VisitorId`,
`MessageBody`), domain events, domain exceptions, and the invariants that make illegal states
unrepresentable.

Allowed dependencies: **none** except `Ago.Platform.Kernel` (which itself depends on nothing but the
BCL). No EF attributes, no `[JsonPropertyName]`, no DI, no `Ago.Platform.Abstractions`.

Rules:

- Constructors and factory methods reject invalid state. `new MessageBody("")` throws; there is no
  such thing as a validated-somewhere-else entity.
- No public setters. State changes go through intention-revealing methods
  (`conversation.AssignTo(operatorId, now)`) that enforce the invariant and raise a domain event.
- Time and identity are passed **in**, never read. The Domain never calls `DateTime.UtcNow`, because
  a rule you cannot control in a test is a rule you cannot test.
- Domain events are internal facts (`ConversationAssigned`), not wire contracts. `Contracts` holds
  the wire shape, and the two are mapped deliberately.

### Application - `Ago.Chat.Application`

Contains: one folder per use case (`UseCases/SendMessage/`) holding the command/query, its handler,
its validator; plus `Abstractions/` with the **product-specific** ports.

Allowed dependencies: `Ago.Chat.Domain`, `Ago.Platform.Kernel`, `Ago.Platform.Abstractions`.
**Not** EF Core, Npgsql, RabbitMQ.Client, StackExchange.Redis, AWSSDK, ASP.NET Core.

Rules:

- A handler orchestrates: load aggregate -> call a domain method -> persist -> write the outbox row ->
  return. Business rules live in Domain; an `if` about business meaning inside a handler is misplaced.
- **Ports are declared by their consumer.** Product-specific ports (`IConversationRepository`) live
  here; generic technical ports (`ICache`, `IEventPublisher`, `IFileStorage`) live in
  `Ago.Platform.Abstractions`, which is dependency-free and therefore safe to reference inwards.
  Either way, the implementation always lives further out and points in. This is dependency
  inversion, and it is the half most often got wrong.
- Ports are shaped by the use case, not by the storage engine. `IConversationRepository.GetActiveForVisitor`
  is a port; `IRepository<T>.Query()` returning `IQueryable` is not - it leaks the persistence model
  and makes the adapter unreplaceable, which defeats the entire point.
- Read queries may bypass the aggregate through a dedicated read port (`IConversationReadStore`)
  returning DTOs. See `adr/0004`.
- Expected failures (not found, forbidden, capacity full) return `Result<T>`. Exceptions are for bugs
  and infrastructure faults.

### Infrastructure - platform adapters + `Ago.Chat.Infrastructure.Postgres`

One project per external technology, so swapping one does not force recompiling the others and the
arch test can assert "only this project references Npgsql".

Contains: EF `DbContext` and configurations, Dapper read stores, RabbitMQ publisher/consumer, Redis
cache and registry, S3 client, `SystemClock`. Every type implements a port declared further in.

Rules:

- Persistence models may differ from Domain entities; the mapping lives here, never in Domain.
- No business decisions. An adapter that decides *whether* to do something is a misplaced use case.
- Retry, backoff, circuit-breaking, and serialisation belong here.

### Hosts - `Ago.Chat.Api`, `Ago.Chat.Worker`, `Ago.Chat.Webhooks`

Contains: `Program.cs`, module loading, DI registration, middleware, auth, health checks, telemetry.

Rules:

- The **only** place that knows concrete implementations. `AddPostgresPersistence()`,
  `AddRabbitMqMessaging()` extension methods live in their own Infrastructure projects and are
  selected by configuration (`Persistence:Provider = postgres|mysql`, `Messaging:Provider = rabbitmq|kafka`).
- Endpoints and hub methods do no work: map DTO -> command, dispatch, map `Result` -> HTTP status or
  hub response. A SignalR hub is a transport detail, not a place for logic.

## How to add a feature (the canonical order)

1. Domain: does an entity gain a method or an invariant? Write it and its unit test first.
2. Application: create `UseCases/<Name>/` - command, handler, validator; declare any missing port.
3. Infrastructure: implement the port(s).
4. Module/Host: expose it (endpoint, hub method, or consumer registration).
5. Tests: domain unit -> application unit with fakes -> integration with Testcontainers.
6. Docs: update the relevant `docs/architecture/*`, and add an ADR if a real choice was made.

The `vertical-slice` skill is this list as an executable checklist.

## Arch tests (`Ago.Chat.Architecture.Tests`)

The rules on this page, made non-negotiable:

- `Ago.Chat.Domain` depends on nothing but `Ago.Platform.Kernel` and the BCL.
- `Ago.Chat.Application` does not depend on any `Infrastructure` or host project.
- **No platform project depends on any `Ago.Chat.*` project.** This is the one that keeps the
  platform claim honest.
- No type in Domain or Application references `DbContext`, `IDbConnection`, `IConnection`,
  `IConnectionMultiplexer`, `IAmazonS3`, or `HttpClient`.
- `DateTime.Now` / `DateTime.UtcNow` / `Guid.NewGuid()` appear only in Infrastructure.
- Every use-case handler is `sealed` and lives under `UseCases/`.
- Every public method returning `Task` accepts a `CancellationToken`.

When one of these fails, the fix is the code, never the test.

## Deliberate deviations

Clean Architecture is a means, not a religion. Where we knowingly deviate, it gets recorded:

- **No MediatR by default.** Handlers are invoked through a thin dispatcher. The indirection buys
  little here and hides the call graph from a reviewer. Revisit if cross-cutting behaviours multiply.
- **The read side bypasses the domain model.** Queries return DTOs straight from SQL: the aggregate
  is a write-side consistency tool, not a query tool.
- **Platform ports live in a shared abstractions package**, not in each product's Application layer.
  Textbook Clean Architecture would duplicate `ICache` per product; one dependency-free package is
  the pragmatic trade, and the arch test that forbids infrastructure references inside it is what
  makes that safe.
