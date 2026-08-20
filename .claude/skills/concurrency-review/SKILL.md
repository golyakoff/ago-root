---
name: concurrency-review
description: Review or write concurrent code in AGO Platform - channels, background services, locks, ordering guarantees, cancellation and shutdown. Use when touching anything with threads, async pipelines, consumers, shared state, or when a race is suspected.
---

# Concurrency review

Authoritative source: `docs/architecture/concurrency.md`. This is the checklist and the failure catalogue.

## Async hygiene (mechanical, check every time)

- [ ] Every async method accepts a `CancellationToken`, passes it down, and honours it in loops.
- [ ] No `.Result`, `.Wait()`, `.GetAwaiter().GetResult()`, no `async void`, no `Task.Run` used to
      make sync code look async.
- [ ] No `lock` held across an `await`. Use `SemaphoreSlim` when exclusion must span an await.
- [ ] No fire-and-forget. Background work lives in a supervised `BackgroundService`.
- [ ] `PeriodicTimer` for periodic work; loops exit on cancellation rather than on an exception.
- [ ] Every `BackgroundService` loop catches, logs with context, and continues - one unobserved
      exception must not silently kill a consumer.

## Shared state

- [ ] Anything reachable from two threads is `ConcurrentDictionary`, `Interlocked`, immutable, or
      guarded. A plain `Dictionary` or `List` shared across threads is a bug even when it "works".
- [ ] Check-then-act on shared state is a race unless it is atomic. In the database that means a
      conditional `UPDATE` with a row-count check; in memory, `Interlocked` or a single-writer design.
- [ ] Unbounded collections are forbidden. Every in-memory queue is a **bounded** `Channel<T>`;
      state that grows per conversation or per connection has an eviction path.

## Ordering

- [ ] Anything that must stay ordered is keyed by `conversation_id` as the partition key.
- [ ] Parallel consumers never process two events of one conversation at the same time
      (`ConversationSequencer`).
- [ ] The database enforces it too: unique `(conversation_id, sequence)`.
- [ ] Nothing orders by a timestamp. Ever (`adr/0011`).

## Correctness at the boundaries

- [ ] Consumers are idempotent; redelivery produces no second row and no second delivery.
- [ ] Acks are sent only after the durable commit, never before.
- [ ] Losing an optimistic-concurrency race is normal: retry, log at `Debug`, do not treat as an error.
- [ ] Backpressure slows producers; it never drops silently and never grows memory.

## Shutdown

- [ ] `ApplicationStopping` is wired: stop intake, drain channels, flush the batch writer, ack
      in-flight work, dispose.
- [ ] Drain has a bounded deadline that fits inside `terminationGracePeriodSeconds`.
- [ ] Readiness goes false before liveness - a draining pod must not be killed for shedding load.

## Tests that must accompany the change

Anything touching this list needs a test in `Ago.Chat.Concurrency.Tests`: ordering under M threads,
capacity under contention, duplicate delivery, kill-mid-load, channel saturation. A concurrency claim
without a test proving it is a claim, not a guarantee.

## Reporting

When reviewing, describe the concrete interleaving that breaks - "thread A reads capacity 4, thread B
reads 4, both increment to 5, capacity was 5" - not a general worry. If you cannot name the
interleaving, say the code looks correct and why, rather than inventing a hazard.
