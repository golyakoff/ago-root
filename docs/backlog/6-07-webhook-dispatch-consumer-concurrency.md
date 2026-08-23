# Give the webhook-dispatch consumers genuine concurrent processing

- **Stage**: 6
- **Status**: ready
- **Depends on**: `6-06` (this is the backlog item that run's own bulkhead gap recommended)

## Goal

`6-05`'s per-tenant bulkhead (`MaxConcurrency=4`, `MaxQueuedActions=16`) becomes reachable in practice,
not just correct in isolation. After this item, a burst of webhook-triggering events for one site can
actually produce more than ~1-2 concurrent delivery attempts, and a burst large enough to exceed the
configured cap produces a real `BulkheadRejected` outcome.

## Context to read first

`docs/backlog/6-06-webhooks-load-proof.md`'s "Bulkhead" section — the root cause was found by reading
the actual consumer code, not guessed: `Ago.Platform.Messaging.RabbitMq.RabbitMqEventConsumer.SubscribeAsync`
registers one `ReceivedAsync` handler per subscription that `await`s the caller's handler **inline**,
before returning control to the client library:

```csharp
consumer.ReceivedAsync += async (_, delivery) =>
{
    ...
    try { await handler(envelope, context, cancellationToken); }
    catch (Exception) { await context.NackAsync(requeue: true, cancellationToken); }
};
```

`PrefetchCount` (default 50) bounds how many *unacked* messages the broker will buffer for the channel,
but it does not make **processing** concurrent — each invocation completes before the next is
dispatched. `ConversationAssignmentWebhookDispatchConsumer` and `ConversationClosedWebhookDispatchConsumer`
are two independent subscriptions, so at most two deliveries for one site can ever be in flight at once
today — structurally short of `MaxConcurrency=4`, and nowhere near the 16-item queue depth that would
even make a rejection possible. `4-05`'s in-process message pipeline already uses a bounded-channel
worker-pool shape elsewhere in this codebase — the precedent to match, not a new pattern to invent.

`docs/architecture/concurrency.md`'s ordering guarantees — per-conversation order must survive whatever
concurrency this item adds; a worker pool draining a single queue in submission order needs a design
that doesn't let two workers race on the same conversation's events out of order.

## Scope

- Give `RabbitMqEventConsumer` (or, if a narrower change is preferable, just the two webhook-dispatch
  consumer registrations) real concurrent message processing: a bounded worker pool draining a local
  channel fed by `ReceivedAsync`, sized independently of `PrefetchCount`.
- Preserve per-conversation ordering (`concurrency.md`) — concurrent processing must not let two events
  for the same conversation race each other out of order; a partitioned/keyed dispatch (by conversation
  id or site id) into the worker pool is the likely shape, not a single unordered pool.
- Re-run `6-06`'s own burst scenario (`tests/Ago.Chat.LoadDriver` + `tests/Ago.Chat.WebhookDispatchRunner`,
  `load/scenarios/`) after the fix and confirm a real `BulkheadRejected` outcome is observed for the
  first time — update `load/reports/` with the follow-up numbers rather than only asserting the fix
  works.

## Out of scope

- Any change to the Polly bulkhead policy itself (`Ago.Platform.Resilience`'s `GetSiteBulkheadPipeline`)
  — `6-06` found no defect in the policy, only that the caller never offered it enough concurrent work
  to gate.
- Changing `PrefetchCount` alone as a fix — it bounds unacked buffering, not processing concurrency;
  raising it without also parallelizing `ReceivedAsync` handling would not change this item's own root
  cause.
- Applying the same fix to every other `Competing`-mode consumer in the codebase — scoped to the
  webhook-dispatch consumers this item's own motivating report measured; a broader audit is separate
  work if ever wanted.

## Done when

- [ ] A bounded worker pool (or equivalent real concurrency mechanism) is in place for the webhook-
      dispatch consumers, with per-conversation ordering preserved and proven by a test.
- [ ] A new or updated `Ago.Chat.Concurrency.Tests` (or `Ago.Platform.Messaging.RabbitMq` test) proves
      more than one delivery for the same site can be in flight at once, and that same-conversation
      events still process in order.
- [ ] `6-06`'s burst scenario re-run against the fix: a real `BulkheadRejected` observed and recorded in
      a new `load/reports/` entry, closing the gap `6-06` left open.

## Open questions

None — the root cause, the fix shape, and the verification method are all named by `6-06`'s own report.
