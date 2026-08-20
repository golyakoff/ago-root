# Domain model: Site, Visitor, Operator, Conversation, Message

- **Stage**: 1
- **Status**: ready
- **Depends on**: nothing (Stage 0 complete)

## Goal

`Ago.Chat.Domain` (currently an empty scaffold) contains real entities and value objects for the
five core concepts, each constructed only in a valid state, with the state transitions Stage 1 needs
expressed as intention-revealing methods rather than public setters. Nothing outside this project can
represent "a conversation with a negative sequence" or "a message with no body" — the type system and
the constructors make it unrepresentable, not a validator layered on top.

## Context to read first

`docs/architecture/clean-architecture.md` (Domain section — allowed dependencies, no public setters,
time/identity passed in), `docs/architecture/data-model.md` (initial table shape — informs which
fields each entity carries, not the schema itself; that is `1-04`'s job), `docs/architecture/vision.md`
(actors, core scenarios), `docs/conventions/coding-style.md`, `docs/conventions/date-and-time.md`.

## Scope

- Strongly-typed ids: `SiteId`, `VisitorId`, `OperatorId`, `ConversationId`, `MessageId` — each a
  `readonly record struct` wrapping a `Guid`, implementing `IStronglyTypedId` (`Ago.Platform.Kernel`).
- `MessageBody` value object: rejects empty/whitespace-only content and enforces a maximum length
  (pick and state a number — this is exactly the kind of decision an ADR is not needed for, but a
  comment explaining the choice is).
- `Site`, `Visitor`, `Operator`, `Conversation`, `Message` entities per `data-model.md`'s initial
  column list, minus everything that is storage detail (no `version` column modeled directly — EF's
  optimistic-concurrency token is a persistence concern, not a domain one; `1-04` owns it).
- `Conversation` state machine: `Waiting -> Assigned -> Closed`, exposed as methods (`Start`,
  `AssignTo`, `Close`) that enforce legal transitions and raise domain events
  (`ConversationStarted`, `ConversationAssigned`, `ConversationClosed`). `AssignTo` here is a trivial
  direct assignment (one operator claims one conversation) — **not** the queue/capacity-aware
  assignment engine, which is Stage 4's centerpiece and does not exist yet.
- `Message` creation via `Conversation.AddMessage(authorKind, authorId, body, idGenerator, now)`,
  which assigns the next `sequence` and enforces that the author is an actual participant (the
  visitor who owns the conversation, or its assigned operator) — see the open question below on how
  far this check goes.
- Every entity takes `IIdGenerator`/`IClock` (or an already-computed id/`DateTimeOffset`) as a
  parameter into its factory method — never reads either directly (`date-and-time.md`).
- `Ago.Chat.Domain.Tests`: one test per invariant, named `<Method>_When<Condition>_<Outcome>`
  (`testing.md`). No infrastructure, no fakes needed beyond a literal `DateTimeOffset`/`Guid`.

## Out of scope

- Queue-based, capacity-checked assignment — Stage 4.
- `version`/optimistic-concurrency plumbing, EF configuration, migrations — `1-04`.
- Domain events actually being raised anywhere durable (outbox) — Stage 2. Stage 1's events are
  in-memory facts a handler can inspect and map to a `Contracts` DTO if it chooses to; nothing
  publishes them yet.

## Done when

- [ ] Every entity's invalid-construction paths have a failing-first test, then pass.
- [ ] `Conversation`'s state machine rejects every illegal transition (`Assigned -> Assigned`,
      `Closed -> AssignTo`, etc.), each with a test.
- [ ] No entity has a public setter; `dotnet build` with `TreatWarningsAsErrors` stays clean.
- [ ] `Ago.Chat.Architecture.Tests`' existing Domain-layering rule (`Ago.Chat.Domain` depends on
      nothing but `Ago.Platform.Kernel` and the BCL) still passes with zero changes to that test.

## Open questions

None. `adr/0016` decided the authorization model (RBAC). `Conversation.AddMessage` still enforces its
own participant/state invariant ("is this operator the conversation's assigned operator") — that is a
domain fact, distinct from the RBAC permission check, which lives in `Application` (`1-02`) and gates
the handler call before `AddMessage` is ever reached.
