# Architecture tests

- **Stage**: 0
- **Status**: ready
- **Depends on**: `0-01-repositories-and-skeleton.md`

## Goal

The layering rules are enforced by a test run, not by discipline. A violation fails the build on the
branch that introduced it.

## Context to read first

`docs/architecture/clean-architecture.md` (the arch-test list), `docs/adr/0002`, `docs/adr/0003`.

## Scope

`Ago.Chat.Architecture.Tests` using NetArchTest (in `ago-chat`; the platform gets its own smaller
set in `ago-platform`), one test per rule, each named after the rule:

- Domain depends only on `Ago.Platform.Kernel` and the BCL.
- Application depends on no Infrastructure or host project.
- No platform assembly references any `Ago.Chat.*` assembly — the package boundary makes this true
  by construction, and the test states it anyway so a future merge cannot quietly undo it.
- Domain and Application reference no `DbContext`, `IDbConnection`, `IConnection`,
  `IConnectionMultiplexer`, `IAmazonS3`, `HttpClient`.
- `DateTime`, `DateTime.UtcNow`, `DateTimeOffset.UtcNow`, `Guid.NewGuid()` appear only in
  Infrastructure (`adr/0011`).
- Use-case handlers are `sealed` and live under `UseCases/`.
- Public methods returning `Task` accept a `CancellationToken`.

## Out of scope

- Style rules that `.editorconfig` already enforces.
- Rules about code that does not exist yet (consumers, adapters) — add them with their stage.

## Done when

- [ ] Each rule has a test, and each test fails when the rule is deliberately broken. **Verify this
      by actually breaking each one temporarily** — an arch test that cannot fail is decoration.
- [ ] The suite runs in CI on every branch.
- [ ] `clean-architecture.md` and the test names say the same thing.

## Open questions

None.
