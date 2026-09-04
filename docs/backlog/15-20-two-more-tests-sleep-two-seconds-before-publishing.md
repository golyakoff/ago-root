# two more tests sleep two seconds before publishing

- **Stage**: 15
- **Status**: ready
- **Found**: 2026-09-04, by `15-18`'s shape-based search — the one its own Done-when demanded
  instead of re-running the grep that had already missed something.

## The gap

`UnreadCounterEndToEndTests.cs:106` and `AttachmentThumbnailEndToEndTests.cs:139` both do

```csharp
await Task.Delay(TimeSpan.FromSeconds(2));
```

after starting their consumers and before the dispatcher's NOTIFY-driven publish can run. Same
defect as the nine `15-17` and `15-18` fixed: if the subscription has not reached
`BasicConsumeAsync`, the publish lands on an exchange with no queue bound to it, **RabbitMQ discards
the message silently**, and the wait that follows observes zero for ever.

Both files already carry a comment describing the failure exactly — *"a fanout exchange drops a
message published before any queue is bound to it"*. The mechanism was understood; only the remedy
was a guess at a duration.

## Why these two were missed twice

`15-17`'s list was assembled by grepping for `Task.Delay(TimeSpan.FromMilliseconds(500))`. **These
sleep two seconds.** `15-18` found them only because its Done-when insisted the search be repeated
by *shape* — any fixed-duration wait preceding a publish or a subscribe, whatever the literal —
rather than by re-running the search that had already proved incomplete.

That is the reusable part: a list built from one literal is not an inventory, and a second run of
the same query is not a second look.

## What it needs

`RabbitMqSubscriptionTestHelpers` is on `main` and is what these use. Establish each test's
subscription **mode** first — `Competing` queues are named `{topic}.{consumerName}` and can be
polled by name; `Broadcast` queues carry a random suffix and go through the exchange-bindings
listing. The helper for the wrong mode waits on a name that will never exist and simply times out.

Wait on a consumer actually attached (step 4), never on the queue existing (step 1) — the mistake
`15-17` shipped and had to correct.

## Deliberately not in scope

`OutboxDispatcherTests.cs:132` sleeps 500 ms for a Postgres `LISTEN` registration. The same shape
with a different mechanism, so none of the above applies to it and no ready-made fix exists. It
needs a decision of its own, and folding it in here would repeat the mistake this item documents.

## Done when

- [ ] Both tests wait for their subscriptions to be observable rather than for a duration.
- [ ] Each new wait is shown to distinguish the racing state from the settled one — the structural
      proof `15-17` and `15-18` both used, since the CI failure does not reproduce on a quiet machine.
- [ ] The shape search is run once more afterwards and reported, including what it found and
      classified as *not* a defect.
