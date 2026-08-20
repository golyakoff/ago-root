---
name: clean-architecture-guard
description: Decide where a type belongs, whether a dependency is legal, and how to express a port and adapter in AGO Platform. Use when unsure which project a file goes in, when tempted to reference infrastructure from an inner layer, or when reviewing a change for layering violations.
---

# Where does this code go?

Authoritative source: `docs/architecture/clean-architecture.md`. This skill is the decision procedure.

## The two questions, in order

**1. Which product?** Does the code mention a domain concept (conversation, visitor, operator, ad
campaign)? Then it is product code (`Ago.Chat.*`). Is it purely technical, plausibly reusable by a
second product, and describable without naming chat? Then it may be platform (`Ago.Platform.*`).
Ambiguous means product.

**2. Which layer?**

| The code... | Layer | Project |
|---|---|---|
| expresses a business rule or invariant | Domain | `Ago.Chat.Domain` |
| orchestrates a use case, needs a capability it cannot implement | Application | `Ago.Chat.Application` |
| talks to Postgres, Rabbit, Redis, S3, HTTP, or the clock | Infrastructure | `Ago.Chat.Infrastructure.*`, `Ago.Platform.*` adapters |
| maps HTTP or hub input, wires DI, configures the host | Host / Module | `Ago.Chat.Api`, `Ago.Chat.Worker`, `Ago.Chat.Module` |

## Legal dependencies

```
Domain          -> Ago.Platform.Kernel only
Application     -> Domain, Platform.Kernel, Platform.Abstractions
Infrastructure  -> Application, Domain, Kernel, Abstractions, its own SDK
Hosts / Module  -> everything
Ago.Platform.*  -> never any Ago.<Product>.*
```

Anything else is a violation. There is no "temporary" exception - the arch test is the rule.

## Writing a port

1. Declare the interface **where it is consumed**: Application, or `Platform.Abstractions` if generic.
2. Name it as a capability in the domain's language: `IConversationRepository`, `IFileStorage`.
3. Shape methods around the use case's need. Never return provider types, `IQueryable`, a
   `DbContext`, or a driver connection.
4. Every method is async and takes a `CancellationToken`.
5. Implement it in an Infrastructure project. That implementation may be provider-specific and ugly -
   that is precisely its job.
6. Register it in the module or host, selectable by configuration wherever a swap is a stated goal.

## Smells and their fixes

| Smell | Why it breaks the rule | Fix |
|---|---|---|
| `DbContext` injected into a handler | Application depends on EF; the provider swap dies | Repository port with use-case-shaped methods |
| `IRepository<T>.Query()` returning `IQueryable` | Leaks the persistence model through the port | Named query method, or a Dapper read port |
| Domain entity with EF or JSON attributes | Domain depends on infrastructure concerns | Configure the mapping in Infrastructure |
| `DateTime.UtcNow` inside a handler | Untestable behaviour, banned by `adr/0011` | Inject `IClock`, pass `now` into Domain |
| A business `if` in an adapter or endpoint | The rule becomes invisible to domain tests | Move it into Domain or the handler |
| Publishing a domain event over the broker | Refactoring an entity becomes a breaking wire change | Map to `Ago.Chat.Contracts` first |
| `Ago.Platform.*` referencing `Ago.Chat.*` | The platform claim becomes false | Invert it with an extension point on the module |
| A new project called `Common` / `Shared` / `Utils` | A dependency magnet with no rule | Put it where it is used, or name the actual capability |

## When a rule genuinely blocks something

Say so explicitly, propose the compliant shape, and if the deviation is still the right call, write an
ADR recording what was traded away. A documented deviation is engineering; a silent one is what arch
tests exist to prevent.
