# ADR-0097: A `Competing` subscription's queue lifetime is explicit, never inferred, never swept

- **Status**: Accepted
- **Date**: 2026-09-04
- **Stage**: 15
- **Decides**: `15-15`
- **Amends**: `docs/architecture/messaging.md` — `Competing`'s queue durability gains a documented
  exception

## Context

`RabbitMqEventConsumer` declared every `Competing`-mode queue `durable: true, autoDelete: false`,
unconditionally. Correct for the topic table `messaging.md` describes — every consumer there is a
genuinely durable subscription that must survive a rolling deploy.

Wrong for `NodeDeliveryConsumer`'s own node-delivery queue (`deliver-to-connections.<pod>`), whose
`Competing` consumer name **is the pod**. A durable queue named after an ephemeral thing outlives it
by design, and nothing ever deleted it. Measured on the live broker:

```
total queues                        140
deliver-to-connections.<pod>         72
of those with no consumer            71
live ago-chat-api pods                1
```

A running total of every pod the cluster had ever had, each still bound to the fanout exchange and
routed into on every publish. They held no messages, which is the only reason this was a queue-count
problem rather than a disk one.

**The obvious first move is the trap this ADR exists to name.** Making `Competing` queues auto-delete
would hit `OperatorRemovedFromSite.operator-removed`, `ConversationAssignedToOperator.conversation-assignment-fanout`
and every other durable subscription in the system — silently dropping messages published while no
replica happened to be attached. The symptom would be lost work, not an error.

## Decision

**A `Competing` subscription's queue lifetime is a property the caller states explicitly, never
inferred and never cleaned up after the fact.**

`Ago.Platform.Abstractions` gains `QueueLifetime`: `Durable` (the default, and the only shape
`Competing` had before this) or `ProcessScoped` (the queue exists only while its declaring connection
is open — `exclusive: true, autoDelete: true` under RabbitMQ).

It arrives as a **second `SubscribeAsync` overload**, not a default parameter: `CancellationToken` is
always required and last in this codebase, so an optional `QueueLifetime` cannot sit before it without
reordering every existing call site. The six-argument overload is unchanged and forwards with
`Durable`, so every existing subscription — in the platform and in `ago-chat` — compiles unedited and
keeps today's guarantee.

`NodeDeliveryConsumer` is the one caller that opts in.

**A subscription's retry queue shares its main queue's lifetime; its dead-letter queue does not.** The
retry queue serves one queue's own redelivery loop and has no life independent of it. A dead-letter
queue is different in kind: a monitored destination for poison messages regardless of which consumer
instance produced them, and legitimately **shared by name across independent subscriptions**.

That last point was not reasoned out in advance — it was found. A first draft tied the DLQ's
exclusivity to `QueueLifetime` too, and a **pre-existing, unrelated test**
(`RabbitMqPublishConsumeTests.Broadcast_TwoConsumers_BothReceiveEveryMessage`) failed against a real
broker with `RESOURCE_LOCKED` the moment a second subscription declared the same DLQ name as
exclusive. So the DLQ declaration stays `durable: true, exclusive: false, autoDelete: false`
regardless, and `NodeDeliveryConsumer`'s own DLQ is instead renamed from per-node to one shared name —
safe **only** because that handler never actually dead-letters (`MaxAttempts: 1`, and it acks even on
failure).

## Consequences

- `NodeDeliveryConsumer`'s queue and retry queue no longer outlive their pod. Proven against a real
  broker: close the declaring connection, the queue is gone.
- Every existing durable subscription is provably unaffected. A dedicated test subscribes durably,
  drops the only consumer, **publishes into the gap**, reattaches, and asserts the message arrives
  with every field intact. That half is the one that would have been easy to skip and the one that
  proves nothing was broken.
- `IEventConsumer` now has two `SubscribeAsync` overloads. A reader has to understand why, which is
  what this ADR and the enum's own remarks are for.
- **A `ProcessScoped` queue is invisible to any other connection's inspection while its owner is
  alive** — RabbitMQ answers `RESOURCE_LOCKED` (405), not `NOT_FOUND` (404). A genuine operational
  difference from every other queue here, worth knowing before debugging one with `rabbitmqctl` from a
  different session. It also had to be handled in the test helper: collapsing both codes to "absent"
  made the durable test's first assertion fail against correct code.
- **The 71 existing orphans are not removed by this.** They were declared under the old code, and this
  only changes what new pods declare. Their removal is a one-time operational cleanup, and it must
  happen *after* the fix is deployed — done before, new pods would simply recreate them.
- A future `ProcessScoped` consumer that genuinely dead-letters needs its own DLQ-sharing design. This
  decision does not give it one.

## Alternatives considered

- **A periodic janitor sweeping consumer-less `deliver-to-connections.*` queues.** Rejected: it cleans
  a mess rather than preventing one, and races a pod that is starting — briefly consumer-less without
  being orphaned. Building it alongside the real fix would also have hidden whether the real fix alone
  sufficed. It did.
- **Inferring lifetime from the consumer name** ("looks like a pod name"). Rejected as the kind of
  cleverness that breaks silently on the first name that does not match the pattern. The caller
  already knows which shape it needs; asking it to encode that in a string for this method to decode
  back out is strictly worse than asking for it directly.
- **A third `SubscriptionMode` value.** Rejected: it would conflate the routing axis (how a message is
  routed) with the lifetime axis (how long the queue sticks around), which are independent.
  `Broadcast` never takes `QueueLifetime` at all — its queue is already exclusive and auto-delete by
  construction, for its own reason.
- **Tying the dead-letter queue's lifetime in too**, for a uniform story. Tried first, rejected by a
  real broker error against a pre-existing test — see the Decision.
