# Testing

## Levels, and what belongs where

| Level | Project | Uses | Runs |
|---|---|---|---|
| Domain unit | `Ago.Chat.Domain.Tests` | Nothing external | Every build, milliseconds |
| Application unit | `Ago.Chat.Application.Tests` | Fakes for ports, fake clock | Every build |
| Architecture | `Ago.Chat.Architecture.Tests` | Reflection over assemblies | Every build |
| Integration | `Ago.Chat.Integration.Tests` | Testcontainers: Postgres, RabbitMQ, Redis, MinIO | Every build (slower), and CI |
| Concurrency | `Ago.Chat.Concurrency.Tests` | Real infra + stress loops | CI, and on demand |
| Load | `load/` (k6) | Deployed cluster | Stage 7 and before any performance claim |

Rule of thumb: a test that needs a container to prove a business rule means the business rule leaked
out of the Domain.

## How tests are written

- Names state the rule: `AssignTo_WhenOperatorAtCapacity_ReturnsCapacityExceeded`.
- Arrange/Act/Assert, one behaviour per test, no logic in the test body (no loops deciding
  expectations, no `if`).
- **No mocking framework for ports we own.** Hand-written fakes are readable, reusable and do not
  encode call-order assumptions nobody meant to make. Mocks are acceptable for third-party interfaces.
- Never mock the database. Use Testcontainers - a mocked repository proves the test compiles, nothing more.
- Fixed, controllable time via a fake `IClock`. No `Thread.Sleep` in tests: wait on a signal, poll a
  condition with a timeout, or use a deterministic scheduler.
- Test data through builders with sensible defaults, so a test names only what it cares about.

## Integration tests

- One Postgres/RabbitMQ/Redis/MinIO container set per test class collection, migrations applied once.
- Each test isolates itself by tenant (`site_id`) or by truncation - never by ordering.
- Assert observable behaviour, not table internals, except where the schema *is* the guarantee
  (unique `(conversation_id, sequence)`, outbox rows in the same transaction).
- **Every fixture that starts Testcontainers acquires `DockerResourceLock` first and releases it only
  after every one of its containers is disposed** (`Ago.Chat.Integration.Tests/DockerResourceLock.cs`).
  Testcontainers already isolates each fixture correctly (dynamic ports, separate containers) - this
  lock exists purely to bound how many container fleets are alive on the local Docker daemon at once,
  since parallel work (multiple background workers, each in their own git worktree, running
  integration tests at the same time) is a real CPU/memory contention risk that isolation alone
  doesn't address. Deliberate trade-off: this makes container lifetimes fully sequential machine-wide,
  even within a single test run that would otherwise start several collections' containers at once -
  correct under the assumption that avoiding Docker contention matters more than single-run
  parallelism; revisit (a small bounded concurrency count instead of strict 1) if that assumption
  stops holding.

## Concurrency tests

These are the project's headline claims, so they are explicit:

- Ordering: K messages, M threads, one conversation, repeated N times - persisted sequence must be a
  gap-free ascending run.
- Capacity: many workers racing to assign, asserting no operator ever exceeds capacity.
- Idempotency: deliver the same event twice, assert one row and one delivery.
- Shutdown: kill a host mid-load, assert zero acknowledged-but-lost messages.
- Backpressure: saturate the channel, assert flat memory and no silent drops.

Flaky is not tolerated: a concurrency test that fails one run in fifty has found a real bug. Quarantine
the *bug*, not the test.

## Coverage

No target percentage. Coverage is a diagnostic, not a goal: the question asked in review is whether
every rule in the ADRs and the concurrency doc has a test that would fail if it were broken.
