# First real consumer: unread counters, proven idempotent

- **Stage**: 2
- **Status**: done
- **Depends on**: `2-04-worker-outbox-dispatcher.md`

## Goal

A `MessageAccepted` event published by `2-04` is consumed for real, exactly once in its effect even
though delivery is at-least-once: the recipient's unread count for that conversation goes up by one
per message, never more, even under duplicate delivery or a crash-and-retry. This is Stage 2's proof
that the whole publish → broker → consume → idempotent-write chain works end to end, chosen over a
synthetic do-nothing consumer because `messaging.md` already names unread counters as a real consumer
of this exact event - this item gives that a home instead of inventing scope.

## Context to read first

`docs/architecture/messaging.md` (delivery guarantees and idempotency section - the `inbox` ledger
rule, "handlers must be safe to run twice regardless of the inbox"), `docs/architecture/concurrency.md`
(idempotency is a named `Ago.Chat.Concurrency.Tests` concern per `testing.md`), `docs/conventions/testing.md`'s
Concurrency row, `2-01`'s `IInboxChecker`.

## Scope

- `conversations` gains an unread-count concept. Simplest shape that satisfies "the recipient's unread
  count": per-participant, so both a visitor-side and operator-side count exist independently (a
  visitor doesn't see the operator's own messages as unread to the operator, and vice versa) - exact
  column shape is the implementer's call, but it must survive `GetConversationHistory` reads unaffected
  (this is a write-side concern, not a new read query) and reset-on-read is **out of scope** here (see
  below).
- `UnreadCounterConsumer` in `Ago.Chat.Worker`, subscribed `Competing` to `MessageAccepted`: inside one
  transaction, check `2-01`'s `IInboxChecker` for `(MessageId, "unread-counter")`, skip if already
  processed, otherwise increment the counter for whichever side did *not* author the message, record
  the inbox row, ack.
- Handler must be naturally idempotent even without the inbox ledger being consulted correctly
  (`messaging.md`'s explicit rule) - prefer an `UPDATE ... SET unread_count = unread_count + 1` guarded
  by the inbox insert's uniqueness rather than a read-then-write increment that a race could double.
- `Ago.Chat.Concurrency.Tests` project created (per `testing.md`'s table, which already assigns
  idempotency and shutdown tests to it - this item is what actually creates the project, ahead of its
  full use in Stage 4). Two tests belong here specifically:
  - **Idempotency**: publish the same `MessageAccepted` twice (simulating redelivery), assert exactly
    one increment and one `inbox` row.
  - **Shutdown**: kill the consumer host mid-batch, restart it, assert no message is double-counted and
    none is silently dropped.

## Out of scope

- Exposing unread counts over the API/hubs, or resetting them on read - nothing in Stage 1's or Stage
  2's `Api` surface asks for this yet, and `GetConversationHistory`'s existing shape does not need it
  to keep working. Wiring the number into a response is a small, separate follow-up once something
  actually displays it (Stage 5's frontends), not invented here.
- `Broadcast`-mode consumers, cache invalidation, anything else in `messaging.md`'s topics table -
  `MessageAccepted`'s only other named consumer ("fan-out to connections") is Stage 3, blocked on the
  Redis registry as already established.
- Capacity/assignment concerns - Stage 4.

## Done when

- [x] `Ago.Chat.Concurrency.Tests` exists as a real project (not a placeholder), referenced from
      `Ago.Chat.slnx`, running in CI per `testing.md`'s table.
- [x] Idempotency test: two deliveries of the same event, one increment, one inbox row - real
      Postgres + real RabbitMQ, not mocked.
- [x] Shutdown test: kill-mid-batch-and-restart leaves the counter exactly right, no double count, no
      loss. Own, non-shared containers, same reasoning as `2-04`'s container-failure test: it forcibly
      kills a connection mid-batch, and sharing infrastructure with the idempotency test caused
      exactly the cross-test interference that precedent exists to avoid.
- [x] `Ago.Chat.Integration.Tests`: a message sent through the full `2-02`→`2-04` chain results in the
      correct party's unread count incrementing, observed live (not by inspecting internal state).
      Also own, non-shared containers - the real `MessageAccepted` this test publishes was found
      polluting `OutboxDispatcherTests`' exact-count assertions when run against the shared fixture.
- [x] `docs/architecture/data-model.md` updated with the unread-count column(s), matching how `1-04`
      and `2-02` closed out their own schema additions.

## Open questions

None - the author already chose unread counters as this item's consumer over a synthetic alternative.
