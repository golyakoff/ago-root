---
name: testing-guide
description: Write tests for AGO Platform at the right level - domain units, application units with fakes, Testcontainers integration tests, concurrency stress tests. Use when adding tests, when a test is flaky, or when deciding what level a behaviour should be tested at.
---

# Writing tests

Authoritative source: `docs/conventions/testing.md`.

## Pick the level first

Ask what would have to break for this test to fail:

- A business rule → **domain unit test**, no infrastructure. If it needs a container, the rule leaked
  out of the Domain and the fix is the code.
- Orchestration, mapping, error paths → **application unit test** with hand-written fakes and a fake clock.
- SQL, migrations, broker behaviour, adapter wiring → **integration test** with Testcontainers.
- Ordering, races, capacity, shutdown, backpressure → **concurrency test**.
- Throughput or latency → **load test** in `load/`. Never assert performance in a unit test; it will
  be flaky on someone else's laptop and prove nothing.

## How to write them

- Name the rule: `AssignTo_WhenOperatorAtCapacity_ReturnsCapacityExceeded`.
- One behaviour per test; no `if`, no loops that decide expectations.
- Hand-written fakes for our own ports - readable, reusable, and free of accidental call-order
  assertions. Mocking frameworks only for third-party interfaces.
- Never mock the database. A mocked repository proves the test compiles.
- Time is a fake `IClock`. At least one test crosses a DST boundary in a non-UTC zone (`adr/0011`).
- No `Thread.Sleep`. Wait on a signal or poll a condition with a timeout.
- Builders with sane defaults, so each test names only what it cares about.

## Integration tests

- Containers per collection, migrations applied once, tests isolated by tenant or truncation - never
  by execution order.
- Assert observable behaviour, except where the schema *is* the guarantee (unique
  `(conversation_id, sequence)`, outbox row in the same transaction).

## Concurrency tests

Structure: N iterations of (spawn M workers, hammer one resource, assert the invariant). Assert the
invariant, not the timing. Required scenarios are listed in `conventions/testing.md`; ordering,
capacity, idempotency, shutdown and backpressure are the five that must exist.

## Flaky tests

A concurrency test failing one run in fifty has found a real bug. Do not retry it, do not add a
sleep, do not `[Skip]` it. Reproduce with a tighter loop, name the interleaving, fix the code. If it
truly is test-harness flakiness, fix the harness and say what was wrong with it.

## Before reporting done

- [ ] The new behaviour fails if you revert the implementation (check this - a test that passes
      against the old code tests nothing).
- [ ] No test depends on wall-clock time, machine speed, or execution order.
- [ ] Fast suite still fast: no containers in domain or application tests.
