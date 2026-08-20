# Application layer: StartConversation, SendMessage, GetConversationHistory

- **Stage**: 1
- **Status**: done — 21 tests in `Ago.Chat.Application.Tests` (all fakes, no container), including
  the DST-boundary test, plus 12 arch (unchanged) and 30 Domain (unchanged). All passed on the first
  run - no bug found this time, unlike `1-01`.
  - `SendMessage` and `GetConversationHistory` each split into two entry points
    (`SendVisitorMessage`/`SendOperatorMessage`, `HandleAsVisitorAsync`/`HandleAsOperatorAsync`)
    rather than one command with a `MessageAuthorKind` discriminator - matches `1-01`'s own
    two-method split on `Conversation`, for the same reason (`coding-style.md`: two same-typed
    parameters that must not be confused is a bug that compiles).
  - `IVisitorRepository` was added to `Abstractions/` - not named in this file's original scope, but
    needed to persist the `Visitor` `1-01` built with "real invariants" and nothing yet to call. Not
    scope creep: it completes what `1-01` already committed to, not a new concern.
  - **Deviation from `naming-and-structure.md`'s example tree**: no `*Validator.cs` per use case.
    `MessageBody`'s constructor already enforces the one real invariant (non-empty, bounded length);
    a separate validation layer for three small use cases would be structure with no second rule to
    justify it yet. Flagged here rather than silently omitted - revisit if a use case gains a
    validation rule `MessageBody` cannot express.
- **Depends on**: `1-01-domain-model.md`

## Goal

`Ago.Chat.Application` gains the three use cases Stage 1 needs, each as a self-contained
`UseCases/<Name>/` folder (command/query, handler, validator), plus the product-specific ports they
need (`IConversationRepository`, `IConversationReadStore`) declared in `Abstractions/`. Every handler
is provably correct against hand-written fakes, with no database involved yet.

## Context to read first

`docs/architecture/clean-architecture.md` (Application section, "how to add a feature"),
`docs/architecture/authorization.md`, `docs/adr/0016-*` (the RBAC model this item implements the
check for), `docs/conventions/testing.md` (fakes, not mocks, for ports we own),
`docs/conventions/coding-style.md` (`Result<T>`, naming), `docs/adr/0004-*` (why reads bypass the
aggregate).

## Scope

- `IConversationRepository` (`Abstractions/`): load-by-id, save. Shaped by the use cases
  (`GetActiveForVisitor`-style methods), never a generic `IRepository<T>`.
- `IConversationReadStore` (`Abstractions/`): `GetHistoryAsync(conversationId, cursor, pageSize, ct)`
  returning a DTO page — keyset-shaped from the start, so the Dapper implementation in `1-04` has no
  redesign to do.
- `StartConversation`: visitor + site in, a new `Waiting` conversation out (or its existing open one,
  if the vision.md scenario "visitor returns and sees history" means "resume," not "always create" —
  resolve this while writing the handler, it is an implementation detail, not an open question).
- `IPermissionChecker` (or similar; `Abstractions/`) — resolves whether a caller (an operator id +
  site id) holds a given `Permission` (`adr/0016`). For Stage 1 this has exactly one real
  implementation path: the caller's single hardcoded `"Operator"` role, seeded by `1-05`. A visitor
  caller never goes through this port at all — their check is "does this token's conversation id
  match," handled directly in the handler, since a visitor holds a capability, not a role
  (`adr/0016`).
- `SendMessage`: conversation id + author + body in. For an operator author, checks
  `conversation:send` via `IPermissionChecker` first; for a visitor author, checks the token's
  conversation id matches. Only then loads the conversation and calls `Conversation.AddMessage`
  (`1-01`) — which still separately enforces its own participant/state invariant. Persists, returns
  the assigned `sequence`.
- `GetConversationHistory`: conversation id + cursor + author in, same two-shaped check as
  `SendMessage` (`conversation:read` for an operator, token-match for a visitor) before reading via
  `IConversationReadStore` — never touches the write-side repository.
- `Ago.Chat.Application.Tests`: hand-written fakes for both ports (no mocking framework —
  `testing.md`), a fake `IClock`, one test per handler outcome (success and each `Result` failure).
  At least one test exercises a fake clock stepping across a DST boundary, per `date-and-time.md`'s
  "if that test never existed, the code has not been proven" — even though nothing in this slice does
  zone-aware rendering yet, the discipline starts here, not when it is first convenient.

## Out of scope

- Anything that touches Postgres, Dapper, or EF — `1-04`.
- Publishing anything to an outbox — Stage 2; handlers do not need `IEventPublisher` yet, and
  `Ago.Platform.Abstractions` (which would host it) is not created until something in this codebase
  actually needs it, to avoid guessing its shape from zero callers (`clean-architecture.md`: "an
  abstraction extracted from exactly one caller is a guess about the second one").
- Visitor token issuance and operator-JWT validation — `1-06` (Host concern, not Application).

## Done when

- [x] All three handlers pass their tests using only fakes — no container, no real clock.
- [x] Every handler returns `Result<T>` for expected failures (not found, wrong participant,
      permission denied) and never throws for them.
- [x] A test proves an operator without `conversation:send`/`conversation:read` for the relevant site
      is rejected by `SendMessage`/`GetConversationHistory` before either reaches the repository.
- [x] `Ago.Chat.Architecture.Tests`' existing rules (`Application` depends on nothing from
      `Infrastructure`/hosts; every `Task`-returning public method takes a `CancellationToken`; every
      handler is `sealed` under `UseCases/`) pass against the new code with zero test changes.
- [x] The DST-boundary test exists and passes.

## Open questions

None.
