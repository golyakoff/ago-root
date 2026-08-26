# Coding style

Formatting is settled by `.editorconfig` and is not a review topic. What follows is about intent.

## C#

- File-scoped namespaces, one public type per file, filename matches the type.
- `sealed` by default. Inheritance is opt-in, and needs a reason.
- Nullable reference types on, warnings as errors. A `!` needs a comment explaining why it holds.
- `var` when the type is obvious from the right-hand side, explicit otherwise.
- Prefer `readonly record struct` for value objects and ids; strongly-typed ids everywhere
  (`ConversationId`, not `Guid`) - mixing up two `Guid` parameters is a bug that compiles.
- Expression-bodied members only when the whole thing fits on the line without becoming a puzzle.
- No regions, no `#pragma` without justification, no `dynamic`.

## Naming

- Interfaces for ports read as capabilities: `IConversationRepository`, `IEventPublisher`.
  Never `IManager`, `IHelper`, `IService` - if the best name is `Service`, the responsibility is unclear.
- Use cases are `<Verb><Noun>` commands with `<Verb><Noun>Handler`: `SendMessage` / `SendMessageHandler`.
- Integration events are past-tense facts: `MessageAccepted`, `ConversationAssigned`.
- Async methods end in `Async`. No sync wrapper of an async method - ever.
- Booleans read as assertions: `isAssigned`, `hasAttachments`, `canAcceptMore`.

## Errors

- Expected outcomes return `Result<T>` with a typed `Error` (code + message). Not-found, forbidden
  and capacity-exceeded are outcomes, not exceptions.
- Exceptions are for bugs and infrastructure faults. Never used for control flow, never swallowed.
- Every catch either handles, enriches and rethrows, or logs with enough context to act on. `catch {}`
  is a defect.
- Public API errors follow RFC 7807 problem details (`api-design.md`).

## Logging

- Structured, message templates only: `logger.LogInformation("Assigned {ConversationId} to {OperatorId}", ...)`.
  Never string interpolation into the template - it destroys aggregation.
- Levels: `Debug` for developer detail, `Information` for state transitions worth an audit,
  `Warning` for retried/degraded conditions, `Error` for failed work needing attention.
  A lost optimistic-concurrency race is `Debug`, not `Error` - noisy logs train people to ignore logs.
- Never log message bodies, tokens, presigned URLs or anything from a visitor's keyboard.
  Log identifiers, and correlate through the trace id.
- **This rule is not only about C#.** `17-02` found the hub's bearer token in the edge's access log, in
  full, on every successful WebSocket upgrade — not because any code logged it, but because nothing
  configured NGINX's log format and its default logs the whole request line. A component whose logging
  nobody has chosen is logging whatever its default logs. When a request carries a secret anywhere but
  a header (a WebSocket handshake has no other option), every logger on its path is in scope for this
  rule, including ones configured in YAML (`architecture/edge.md`).
- **And it is not only about the loggers you wrote.** `16-05` swept 1.19 M log lines off a running
  cluster and found every hand-written `Log*()` call in `Ago.Chat.*` clean — and **over 99% of the
  volume coming from framework categories nobody had configured**: ASP.NET Core's request logging on
  two of the three hosts, and EF Core's full SQL statement text on all three. Neither carried personal
  data, because parameters are logged as `?` while nothing calls `EnableSensitiveDataLogging` — but
  "we do not log bodies" was a statement about *our* code, and the log file is not. Set the level for
  a framework category deliberately, the way `appsettings.json` now does, and treat "`Default:
  Information` and see what happens" as a decision rather than an absence of one.
- **The same goes for span attributes, which are easier to leak into than log statements.**
  Instrumentation adds attributes nobody wrote: `db.query.text` carries the whole SQL statement,
  `url.full` carries the whole outbound URL. Both are safe today only because every value in them is
  a parameter or is redacted by a default. `Ago.Chat.Integration.Tests.TelemetryLeakGuardTests` is the
  test that fails if either stops being true — a guard rather than a convention, for exactly the
  reason the previous bullet exists.

## Comments

Comment *why*, never *what*. A comment explaining a non-obvious trade-off, a race, or a protocol
requirement is valuable; a comment restating the line above it is noise that will rot.
