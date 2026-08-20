---
name: vertical-slice
description: Add a feature to AGO Platform end to end - Domain, Application, Infrastructure, module registration and tests - in the correct order with the correct layering. Use whenever implementing a new use case, endpoint, hub method, consumer, or backlog item.
---

# Adding a vertical slice

Follow this order. Each step names the layer rule that puts the code where it goes; state that
reason in your response (teaching mode is a project rule, see `CLAUDE.md`).

## 0. Before writing anything

- Read `docs/architecture/clean-architecture.md` and any architecture doc the feature touches:
  `concurrency.md`, `messaging.md`, `data-model.md`, `caching.md`, `file-storage.md`.
- Decide: **platform** or **product** code? Apply the qualifying rules - if in doubt it is product
  code. Promotion later is cheap; a wrong platform abstraction is not.
- Confirm you are on a feature branch. Never commit (project rule).

## 1. Domain first

Does this feature introduce or change a business invariant?

- If yes: add the method to the aggregate (`conversation.AssignTo(...)`), enforce the invariant,
  raise the domain event. Write the domain unit test **before** the implementation - it needs no
  infrastructure, so there is no excuse.
- Pass time and identity in as parameters (`DateTimeOffset now`). Never read a clock in Domain.
- If the feature has no invariant (a pure query), skip to step 2 and say so.

## 2. Application: the use case

Create `UseCases/<Name>/` containing:

- `<Name>.cs` - the command or query record.
- `<Name>Handler.cs` - `sealed`, orchestration only: load, domain call, persist, outbox, return
  `Result<T>`. Any `if` about business meaning belongs in Domain instead.
- `<Name>Validator.cs` - shape validation (lengths, required, ranges), not business rules.

Ports: if the handler needs something it cannot do itself, declare an interface.

- Product-specific (`IConversationRepository`) goes in `Ago.Chat.Application/Abstractions/`.
- Generic technical (`ICache`, `IEventPublisher`, `IFileStorage`) already exists in
  `Ago.Platform.Abstractions` - reuse it, do not duplicate.
- Shape the port around the use case, never around the database. No `IQueryable`, no `IRepository<T>`.

Writes others must learn about: insert the outbox row **in the same transaction** as the state change
(`adr/0005`). Map the domain event to an `Ago.Chat.Contracts` integration event - never publish a
domain type.

## 3. Infrastructure: implement the ports

- EF Core for writes, Dapper for reads (`adr/0004`). Keyset pagination only.
- New table or column? Use the `db-migration` skill.
- Retries, backoff, serialisation and circuit breaking live here, never in the handler.

## 4. Wire it up

Register in `Ago.Chat.Module` (services, endpoints, hub methods, consumers). Hosts stay
product-agnostic. Endpoint bodies map DTO to command, dispatch, map `Result` to HTTP - nothing else.

## 5. Tests (a slice without tests is not done)

Per `docs/conventions/testing.md`: domain unit, then application unit with hand-written fakes, then
integration with Testcontainers. Add a concurrency test if the slice touches shared state, ordering,
or capacity.

## 6. Docs

Update any architecture doc the change made wrong. Write an ADR if you chose between real
alternatives. Both go in the same branch as the code.

## Self-check before reporting done

- [ ] Domain references nothing but `Ago.Platform.Kernel`; Application references no infrastructure.
- [ ] Every async method takes and honours a `CancellationToken`.
- [ ] No `DateTime`, no `DateTime.UtcNow`, no `Guid.NewGuid()` outside Infrastructure.
- [ ] State change and its integration event share one transaction.
- [ ] Consumer paths are idempotent.
- [ ] `Ago.Chat.Architecture.Tests` green.
- [ ] You stated which layering principle drove each placement decision.
