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
- **Integration events carry no message body, and that is now a privacy property, not only a size
  one** (`16-01`, `personal-data.md`). `MessageAccepted` ships ids, kinds and a sequence; a consumer
  that needs the text reads `GetConversationHistory`. The consequence is that `outbox.payload` -
  a table nothing ever prunes - holds no copy of anything a visitor typed, which is the single reason
  erasure in this event-driven system is a two-place problem instead of a five-place one. Adding a
  body field to a contract is therefore not an additive change in the sense the rule above means: it
  is additive on the wire and load-bearing for deletion. Say so in the change, and update
  `personal-data.md` in the same commit.

**The one place a body does cross the broker, so nobody rediscovers it the hard way.** The realtime
fan-out path is not an integration event in this sense: `NodeFanoutPublisher` publishes a
`NodeDelivery` whose `PayloadJson` is a serialised `MessageDto`, body included, because its whole job
is to hand the bytes to a socket on another node (`realtime.md`, `adr/0020`). Those messages are
`Persistent = true` on durable queues, consumed in milliseconds in steady state - but a node queue
outlives the pod it was named after, so a replaced pod can leave message text sitting in RabbitMQ
indefinitely. This is accepted rather than solved (`NodeDeliveryConsumer`'s own remarks: nothing here
has a queue-retention policy yet); it is recorded in `personal-data.md` so a backup or residency
decision counts the broker's volume as a personal-data store rather than as plumbing.

Domain events (inside `Domain`) and integration events (in `Contracts`) are different things and must
not be the same type. Mapping happens in Application when writing to the outbox - otherwise a
refactor of an entity becomes a breaking wire change, which is exactly the coupling the layering is
supposed to prevent.

## Topics

| Event | Key | Consumers |
|---|---|---|
| `MessageAccepted` | `conversation_id` | Fan-out to connections, unread counters, `14-04`'s offline auto-reply |
| `ConversationAssigned` | `conversation_id` | Fan-out, cache invalidation, metrics |
| `ConversationClosed` (wire contract `ConversationEnded` - `6-02`'s own "contract gets a different bare name than its domain event" convention) | `conversation_id` | Fan-out, cache invalidation, metrics, `6-05`'s webhook dispatch |
| `OperatorStatusChanged` | `operator_id` | Assignment engine, cache invalidation |
| `AttachmentConfirmed` | `conversation_id` | Thumbnailer (image content types only) |
| `CacheInvalidated` | key namespace | All nodes (fan-out to every replica, not competing consumers) |

### AGO Calendar's own topics

A separate product with a separate broker vhost and a separate database (`adr/0027`); listed on this
page because the delivery semantics, the outbox rule and the versioning rule are the platform's and
are identical. Nothing here is consumed by AGO Chat and nothing there is consumed here.

| Event | Key | Consumers |
|---|---|---|
| `BookingConfirmed` (`20-04`) | `event_id` | `20-05`'s SMS delivery. None wired yet |

`BookingConfirmed` is a past-tense fact: the operator veto window closed with nobody acting (or an
operator confirmed early), and the visit is on. Staged to the outbox in the **same transaction** as
the `PendingConfirmation -> Booked` transition (`CLAUDE.md` rule 4), by
`Ago.Calendar.Infrastructure.Postgres.ExpiredBookingConfirmer`.

- **Payload**: `EventId`, `TenantId`, `CalendarId`, `CustomerId`, `StartsAt`, `EndsAt`, `LocalDate`,
  `OccurredAt`, `CorrelationId`.
- **Ids for anything with a life of its own, values for what is immutably true of this booking.**
  `CustomerId` resolves to whatever the lead card says when a consumer reads it - including "no longer
  there", which is the correct answer after an erasure. `StartsAt`/`EndsAt`/`LocalDate` are values
  because they cannot change: there is no reschedule in v1, so the slot a booking took is fixed, and
  making a consumer re-read them would be a round trip for data that cannot have moved.
- **No phone number, no name, and that is a rule.** An integration event crosses a broker to consumers
  this product does not control, and it lands in an `outbox` table nothing prunes. `20-05` looks the
  phone up from `CustomerId` at send time. Same reasoning `api-design.md` already gives for a webhook
  payload carrying no message body: what leaves the write path is what an erasure request can no
  longer reach. Held by a test that asserts the serialised payload contains no phone-shaped string.
- **`CalendarId` is present for one specific reason**: the calendar owns the IANA zone (`adr/0049`),
  and a consumer rendering "Tuesday at 14:00" for a human cannot do it from an instant alone.
- **Keyed per booking, not per tenant.** The only ordering that matters is between events about one
  booking; a tenant-wide key would serialise a busy shop's confirmations behind each other for a
  guarantee nobody needs.
- **`MessageId` is the `EventId` itself**, so a consumer deduplicating on message id is deduplicating
  on "this booking was confirmed" - which is the idempotency key it actually wants (rule 5).

Note the last row is the one exception to competing-consumer semantics: every node must receive it.
In RabbitMQ that is a per-node exclusive queue on a fanout exchange; in Kafka, a unique consumer
group per node. The adapter hides this; the subscription declares intent as `Broadcast` vs `Competing`.

**`Competing` requires a consumer-identity name, shipped in `5-11`**: `Competing` mode is only correct
when every logical consumer *type* subscribed to a topic is distinguishable from every other one -
`MessageAccepted` above has three since `14-04` (`ConnectionFanoutConsumer`, `UnreadCounterConsumer` and
`OfflineAutoReplyConsumer`, names `connection-fanout`/`unread-counter`/`offline-auto-reply`), and until
`5-11`, `Ago.Platform.Messaging.RabbitMq/RabbitMqEventConsumer.cs` named a `Competing` queue after the
bare topic with no consumer-identity component, so both silently shared one queue and RabbitMQ
round-robined each message to one or the other, never both - real-time message delivery had been
unreliable since `3-02` as a result. `IEventConsumer.SubscribeAsync` now takes a required
`consumerName`: every replica of one logical consumer passes the *same* name (correctly sharing a
queue - `Competing`'s actual purpose, horizontal scaling), two different consumer types pass different
names (correctly getting one queue each). This is not `adr/0006`'s consumer-group *mechanism* leaking
through the port - it is the caller declaring identity, which `Competing` cannot mean anything without
on either broker (see that ADR's own amendment). Found live while verifying `5-10`: ten operator-sent
messages, zero delivered as a real-time push to the visitor, all ten present and correctly delivered
only once the widget reconnected and used the resume-by-sequence path instead (which reads Postgres
directly, bypassing the broken path entirely) - `RabbitMqPublishConsumeTests.Competing_TwoDifferentConsumerTypes_BothReceiveEveryMessageIndependently`
reproduces the bug against a real broker and is the regression test that should have caught this
originally.

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
- **A consumer that decides to do nothing is not a failure**, and `14-04` is the first one where the
  distinction is load-bearing enough to write down. `OfflineAutoReplyConsumer` acks immediately on
  every "correctly decided not to reply" outcome (the flag is off, somebody is online, this is not a
  visitor message) and throws only on a genuine fault. Retrying a message a consumer correctly
  declined declines it again, more slowly, and eventually dead-letters a message the rest of the
  system handled fine.
- **A consumer that produces a message of its own must not be able to feed itself.** `14-04`'s
  auto-reply is an ordinary message on the same topic that triggered it, and what stops the recursion
  is structural rather than a runtime check: the reply is authored `MessageAuthorKind.System` by the
  only method that can create one, and the consumer acts on `Visitor` alone (`adr/0066`). A future
  consumer that writes into a topic it also reads should copy the shape - or say plainly why the loop
  is bounded some other way.
- **`13-02`: the first inbound, HTTP-triggered idempotency ledger, not a broker consumer.** ЮKassa
  calls `Ago.Chat.Api` directly over HTTP - there's no RabbitMQ hop and no `EventEnvelope.MessageId`
  for an inbound third-party webhook, so the platform's generic `(message_id, consumer)` inbox doesn't
  fit. `billing_webhook_events`'s own `(yookassa_payment_id, event_type)` unique index plays the
  identical role inside one plain database transaction (`BillingWebhookApplier`) - insert-and-catch-
  unique-violation is "detected, skipped, acked" realized without a broker, because there is no broker
  in this path to realize it with. See `adr/0071`.

## Outbox dispatcher

Runs in `Worker`. Claims unpublished rows with `FOR UPDATE SKIP LOCKED` in batches, publishes,
marks published. Multiple replicas run it concurrently and safely by construction. Latency of this
loop is a measured number (it sits directly in the end-to-end p95), and is the reason the dispatcher
is poll-with-notify rather than a naive fixed 1-second poll.

The write side (staging an outbox/inbox row on a product's own `DbContext` so its own
`SaveChangesAsync` persists it atomically) is generic platform code, not hand-rolled per product -
`adr/0017`.
