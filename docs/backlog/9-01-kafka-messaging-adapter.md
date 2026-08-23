# Ago.Platform.Messaging.Kafka: the same port, a genuinely different broker

- **Stage**: 9
- **Status**: ready
- **Depends on**: `5-11-fix-competing-consumer-queue-collision.md` (the current, corrected shape of
  `IEventConsumer.SubscribeAsync` - `consumerName` included; transitively carries `2-01`'s port and
  `2-03`'s RabbitMQ adapter as the reference implementation)

## Goal

`IEventPublisher`/`IEventConsumer` (`2-01`, amended by `5-11`) have a second real adapter, talking to
an actual Kafka broker, that a caller cannot tell apart from the RabbitMQ one by behaviour alone
within the port's own contract: publish, ack/nack/dead-letter, `Competing` vs `Broadcast`
subscription, and the same `consumerName` identity rule all work. No product code touched - this
proves the adapter against the port in isolation, the same way `2-03` proved RabbitMQ in isolation,
and is one half of Stage 9's actual claim: that `messaging.md`'s "largest common denominator" port
was pitched correctly, not just written to look reusable.

## Context to read first

`docs/architecture/messaging.md` in full, especially "The abstraction (and its honest limits)" and
"Known leaks" - this adapter is where those leaks stop being predictions and become real code:
partition key vs. consistent-hash queue for ordering scope, retry topic vs. delay/retry exchange,
offset replay vs. no replay at all. `docs/adr/0006-broker-abstraction.md` in full, including the
`5-11` amendment - `consumerName` is not optional scope, it is the current port contract.
`docs/backlog/2-03-rabbitmq-adapter.md` - read it as "what does implementing this port for real
actually involve," including its own Status note about the one deliberate scope reduction (single
shared queue per `Competing` topic, not an N-queue consistent-hash topology) - decide explicitly
whether this item's Kafka adapter matches that same simplification (a Kafka topic's partition count
standing in for the queue-count question) or whether Kafka's native per-partition model makes the
simplification unnecessary here; state the answer in code comments the way `2-03` did.
`docs/architecture/resilience.md`'s "RabbitMQ / Kafka" boundary row - timeout, retry with jittered
backoff, and (per that row) no circuit breaker at this boundary, unchanged for this adapter.
`docs/architecture/concurrency.md`'s partition-key ordering statement - the property this adapter must
actually hold, not merely accept as a parameter.

## Scope

- `Ago.Platform.Messaging.Kafka` project, referencing `Ago.Platform.Abstractions` only (matches
  `Ago.Platform.Messaging.RabbitMq`'s own boundary - `naming-and-structure.md` already reserves this
  project's name).
- `KafkaEventPublisher`: maps `EventEnvelope.Type` to a topic, `PartitionKey` to Kafka's own message
  key (letting the broker's own partitioner place same-key messages in the same partition - this is
  what makes per-key ordering real on this broker, not a routing-key convention as it is on RabbitMQ).
  Publish acknowledgement uses the client library's own delivery-report/ack mechanism, not
  fire-and-forget (`resilience.md` names this explicitly for the RabbitMQ adapter; the same
  requirement applies here even though the mechanism differs).
- `KafkaEventConsumer`: explicit ack via offset commit, nack/requeue, and dead-letter to a configured
  DLQ topic after N attempts (retry policy per subscription, matching the RabbitMQ adapter's
  configuration shape so callers configure both adapters the same way). `Competing` mode maps to
  Kafka's native consumer-group mechanism, keyed by the required `consumerName` - every replica of one
  logical consumer uses the same `consumerName` as its group id (correctly sharing partitions,
  `Competing`'s actual purpose); `Broadcast` mode needs a unique, derived group id per node so every
  node gets every message, the same intent `messaging.md`'s `CacheInvalidated` row already describes
  for RabbitMQ's per-node exclusive queue, expressed through Kafka's own mechanism instead.
- `KafkaOptions` bound from `Messaging:Kafka:*` config keys, validated at startup - mirrors
  `RabbitMqOptions`'s shape (`naming-and-structure.md`'s configuration-key convention) so the two
  adapters read as siblings, not as differently-designed newcomers.
- Connection/client lifecycle: the client library's own reconnect/retry behaviour on broker
  unavailability, so the adapter resumes cleanly when Kafka returns without a process restart
  (`resilience.md`: "outbox accumulates while it is down" applies identically here).
- Topic/partition-count provisioning for the adapter's own integration tests (auto-create in the
  Testcontainers broker, or an explicit admin-client call at test setup - whichever the chosen client
  library makes the more honest default; state which and why).
- A brief note in `docs/architecture/messaging.md`'s "Known leaks" section confirming which leaks were
  actually observed while building this adapter (parallelism-via-partition-count, replay-by-offset,
  ordering-scope-per-partition) versus predicted in advance - this is raw material for `9-04`, not a
  rewrite of the section.

## Out of scope

- Wiring this into `Ago.Chat.Worker`/`Ago.Chat.Module`, or making it the active provider anywhere - the
  provider switch and CI matrix are `9-03`. This item's tests exercise the adapter directly against a
  Testcontainers Kafka broker, the same way `2-03`'s tests exercised RabbitMQ directly.
- Any change to `Ago.Platform.Abstractions`'s port shape - the whole point is proving the existing
  contract is honourable on a second broker, not adjusting the contract to fit this broker better. If
  building this adapter reveals the port cannot honestly express something Kafka needs, that is a
  finding for `9-04`, not a silent port edit here.
- Kafka-specific strengths the port does not expose - compaction, long retention, replay-driven
  rebuilds (`adr/0006`'s own "Consequences" already name these as unavailable through the port by
  design).

## Done when

- [ ] `Ago.Platform.Integration.Tests` (Testcontainers Kafka): publish-then-consume round-trip,
      `Competing` mode with two consumers sharing one `consumerName` where each message is delivered to
      exactly one of them, `Broadcast` mode with two different `consumerName`s where both receive every
      message - the same three shapes `2-03`'s own Done-when proved for RabbitMQ, run against Kafka
      instead.
- [ ] A test proves two different logical consumer types (two different `consumerName`s) subscribed
      `Competing` to the same topic both receive every message independently - the Kafka-side regression
      test for the exact bug class `messaging.md`'s `5-11` section documents on RabbitMQ, proven here so
      the same mistake cannot silently reappear on the second adapter.
- [ ] A test stops the Kafka broker mid-publish and asserts the publisher surfaces a retryable failure
      rather than hanging or throwing unhandled.
- [ ] A test proves nack/requeue redelivers, and dead-letter after N attempts lands the full envelope on
      the configured DLQ topic, not silently dropped.
- [ ] A test proves per-partition-key ordering: N messages published with the same partition key, in
      order, are consumed in that same order - `concurrency.md`'s guarantee, demonstrated on this broker
      specifically rather than assumed from the RabbitMQ result.
- [ ] `Ago.Platform.Architecture.Tests` green - this adapter references `Ago.Platform.Abstractions`
      only, never `Ago.Chat.*`.
- [ ] `CHANGELOG.md` entry and version bump for the new package (`repositories.md`'s SemVer rule - this
      is new public surface, a new `.nupkg`, even though no existing port shape changed).

## Open questions

None. The port and its current contract (`consumerName` included) are already settled by `2-01` and
`5-11`; this item implements against them, it does not renegotiate them.
