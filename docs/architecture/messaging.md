# Messaging

## Why the broker exists here

Three jobs, and it is worth being explicit about which is which:

1. **Cross-node delivery** - node A holds the visitor, node B holds the operator. B learns about A's
   message through the broker.
2. **Decoupled work** - persistence follow-ups, thumbnails, cache invalidation, notifications. Slow
   or failing work must never sit in the request path.
3. **Reliability** - combined with the outbox, a message that was acknowledged is a message that will
   be delivered, even if every process restarts.

The broker is never a store and never a source of truth. If a scenario needs to "read from the queue"
to answer a question, the design is wrong.

## The abstraction (and its honest limits)

Ports in `Ago.Platform.Abstractions`:

```
IEventPublisher   PublishAsync(EventEnvelope envelope, CancellationToken ct)
IEventConsumer    subscribe(handler) with explicit Ack / Nack(requeue) / DeadLetter
EventEnvelope     MessageId, Type, Version, PartitionKey, OccurredAt, CorrelationId, Payload
```

The abstraction is deliberately pitched at **"topic + partition key + at-least-once + explicit ack"**.
That is the largest common denominator of RabbitMQ and Kafka that does not lie:

- **Partition key** is a first-class field, because ordering-per-key is a guarantee we depend on
  (`concurrency.md`), and it is the only way both brokers can honour it.
- **Explicit ack** is exposed, because auto-ack silently breaks the durability story.
- **Retry and dead-lettering** are declared per subscription (attempts, backoff, DLQ name) and
  implemented per adapter - RabbitMQ with a delay/retry exchange, Kafka with a retry topic.
  These are genuinely different mechanisms behind one intent.

What the abstraction deliberately does **not** expose: exchanges, bindings, routing-key patterns,
consumer groups, offsets, partitions. Those live in the adapter's configuration. Any use case that
needs one of them has a design problem, not a missing feature.

Known leaks, written down rather than pretended away (`adr/0006`):

- Consumer parallelism means different things (queue consumers vs partition count) and is configured
  per adapter.
- Kafka replays by offset; RabbitMQ does not replay at all. Anything needing replay must be
  reconstructible from PostgreSQL instead.
- Ordering scope differs: Kafka per partition, RabbitMQ per consistent-hash queue. Equivalent for our
  key, not identical in general.

## Event contracts

Integration events live in `Ago.Chat.Contracts` - plain records, no domain types, no behaviour.
They are a public API: once published, the shape is a promise.

- Names are past-tense facts: `MessageAccepted`, `ConversationAssigned`, `OperatorWentOffline`.
  Never commands, never `ShouldDoX`.
- Every event carries `MessageId` (idempotency key), `OccurredAt`, `SiteId`, `CorrelationId`.
- **Versioning**: additive changes only within a version - a new optional field is fine, a renamed or
  removed field is not. A breaking change means `V2` published alongside `V1` until consumers move.
- Payloads are small: identifiers plus what a consumer cannot cheaply look up. Do not ship a whole
  conversation because it is convenient.

Domain events (inside `Domain`) and integration events (in `Contracts`) are different things and must
not be the same type. Mapping happens in Application when writing to the outbox - otherwise a
refactor of an entity becomes a breaking wire change, which is exactly the coupling the layering is
supposed to prevent.

## Topics

| Event | Key | Consumers |
|---|---|---|
| `MessageAccepted` | `conversation_id` | Fan-out to connections, unread counters |
| `ConversationAssigned` / `Closed` | `conversation_id` | Fan-out, cache invalidation, metrics |
| `OperatorStatusChanged` | `operator_id` | Assignment engine, cache invalidation |
| `AttachmentConfirmed` | `conversation_id` | Thumbnailer (image content types only) |
| `CacheInvalidated` | key namespace | All nodes (fan-out to every replica, not competing consumers) |

Note the last row is the one exception to competing-consumer semantics: every node must receive it.
In RabbitMQ that is a per-node exclusive queue on a fanout exchange; in Kafka, a unique consumer
group per node. The adapter hides this; the subscription declares intent as `Broadcast` vs `Competing`.

**Real, currently-shipping bug, found live while verifying `5-10`, tracked in `5-11`**: `Competing`
mode is only correct when exactly one logical consumer *type* subscribes to a topic - `MessageAccepted`
above has two ("Fan-out to connections, unread counters" = `ConnectionFanoutConsumer` +
`UnreadCounterConsumer`), and `Ago.Platform.Messaging.RabbitMq/RabbitMqEventConsumer.cs` names a
`Competing` queue after the bare topic with no consumer-identity component, so both consumer types
end up bound to the *same* queue and RabbitMQ round-robins each message to one or the other, never
both. In practice this has meant real-time message delivery has been unreliable since `3-02` - proven
live: ten operator-sent messages, zero delivered as a real-time push to the visitor, all ten present
and correctly delivered only once the widget reconnected and used the resume-by-sequence path instead
(which reads Postgres directly, bypassing this broken path entirely). `5-11` has the full diagnosis,
the fix (a required consumer-group parameter on `IEventConsumer.SubscribeAsync`), and the regression
test that should have caught this originally.

**Shipped in `5-04`**: named `AttachmentConfirmed`, not the `AttachmentUploaded` this table originally
planned - it fires from `Attachment.ConfirmReady` (the confirm step, after HEAD-verification), not
from the client's own unverified "uploaded" claim, and the domain-event/contract naming split needed
a name distinct from `Ago.Chat.Domain.AttachmentReady` regardless (the same
`MessageAdded`/`MessageAccepted` split). Keyed by `conversation_id`, not `attachment_id` as originally
planned - consistent with every other per-conversation event on this page, even though
`AttachmentThumbnailConsumer` has no actual ordering requirement of its own (each attachment
thumbnails independently); `attachment_id` would have worked exactly as well.

## Delivery guarantees and idempotency

At-least-once, everywhere, in both directions. Therefore:

- Every consumer records `message_id` in the `inbox` table inside the same transaction as its work.
  A duplicate is detected, skipped, and acked.
- Handlers must be safe to run twice regardless of the inbox - the ledger is a fast path, not the
  only defence. Prefer naturally idempotent writes (upserts, unique constraints).
- Poison messages: N attempts with exponential backoff, then dead-letter with the full envelope and
  the last exception. A DLQ with no alert and no runbook entry is a silent data-loss channel, so
  Stage 7 gives it both.

## Outbox dispatcher

Runs in `Worker`. Claims unpublished rows with `FOR UPDATE SKIP LOCKED` in batches, publishes,
marks published. Multiple replicas run it concurrently and safely by construction. Latency of this
loop is a measured number (it sits directly in the end-to-end p95), and is the reason the dispatcher
is poll-with-notify rather than a naive fixed 1-second poll.

The write side (staging an outbox/inbox row on a product's own `DbContext` so its own
`SaveChangesAsync` persists it atomically) is generic platform code, not hand-rolled per product -
`adr/0017`.
