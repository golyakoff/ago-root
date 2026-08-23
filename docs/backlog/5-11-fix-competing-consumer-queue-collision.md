# Fix: Competing-mode consumers of the same topic silently steal each other's messages

- **Stage**: 5
- **Status**: done
- **Depends on**: nothing - `ago-platform` only, no product-side prerequisite

## Goal

Two independent `Competing`-mode consumers subscribed to the same topic currently share one RabbitMQ
queue and split its messages between them, instead of each independently receiving every one. After
this item, two unrelated consumer types on the same topic never collide, proven by a test that would
have caught this the first time.

## Context to read first

`docs/architecture/messaging.md`'s `Competing`/`Broadcast` distinction. `Ago.Platform.Messaging.RabbitMq/RabbitMqEventConsumer.cs`
- the whole bug is one line: `var queueName = mode == SubscriptionMode.Competing ? topic : $"{topic}.{Guid.NewGuid():N}";`.
`Ago.Chat.Worker/Program.cs` - `UnreadCounterConsumer` and `ConnectionFanoutConsumer` both call
`consumer.SubscribeAsync(nameof(MessageAccepted), SubscriptionMode.Competing, ...)` today; this is the
concrete case that surfaced the bug, not a hypothetical.

## How this was found

Found live while verifying `5-10` (widget attachments), not something the design ever intended.
An operator sent 10 attachment messages, one at a time and later spaced 1.5s apart, to a visitor's
open widget connection. **Zero of the ten** arrived as a real-time push, even though:

- The database had all 10 messages, correctly sequenced (ground truth, verified by direct query).
- `Ago.Chat.Worker`'s `MessageAccepted` RabbitMQ queue showed real ack traffic (`ack: 9+`) - messages
  were being consumed successfully by someone.
- The `deliver-to-connections.{node}` queue *also* showed real ack traffic, meaning `ConnectionFanoutConsumer`
  did run and did publish node deliveries for at least some of those messages.
- Reloading the widget (triggering `VisitorHub.JoinAsync`'s resume-by-`lastKnownSequence` path, which
  reads from Postgres directly, never through the live-push path) caught up on all 10 messages
  correctly, rendered correctly, attachments and all.

That last point is what pinned the diagnosis down: the *data* path and the *resume* path are both
fine. Only the *live push* path silently drops messages, and only when more than one `Competing`
consumer type shares a topic. Reading `RabbitMqEventConsumer.cs` confirms why: `SubscribeAsync` takes
no consumer-identity parameter, so `UnreadCounterConsumer` and `ConnectionFanoutConsumer` - two
entirely independent consumer types, both legitimately needing *every* `MessageAccepted` event -
end up bound to the exact same queue (`"MessageAccepted"`, no suffix). RabbitMQ's normal
competing-consumers dispatch then round-robins each message to *one or the other*, never both. In
this session's live test the round-robin was not even close to 50/50 (0/10 landed on
`ConnectionFanoutConsumer`) - `BasicQos(prefetchCount: 50, global: false)` combined with one consumer
consistently acking faster is enough to starve the other for a burst of messages sent close together,
which is exactly the shape a real conversation's message traffic has.

**Blast radius**: currently, exactly one topic in this codebase has two independent `Competing`
consumers - `MessageAccepted` (`UnreadCounterConsumer` + `ConnectionFanoutConsumer`). That means, as
shipped, **real-time message delivery has been unreliable since `3-02`** (whenever the two consumers
first coexisted) - every previous session's own "live verification" of realtime delivery either got
lucky with the round-robin, tested with only one of the two consumers running, or (more likely,
given how consistently one-sided this session's own test was) never actually exercised true
cross-node/cross-consumer delivery under real message volume. `UnreadCounterConsumer` traffic wins
this race far more often in practice than a coin flip would predict.

## Scope

- Add a consumer-identity parameter to `IEventConsumer.SubscribeAsync` (`Ago.Platform.Abstractions`) -
  something like `string consumerGroup`, required for `Competing` mode (each logical consumer type
  supplies its own stable name; multiple *replicas* of the same consumer type pass the *same* name,
  which is what actually gives `Competing` its real meaning - many processes, one logical group).
  `Broadcast` mode does not need it - its own random-suffixed queue is already unique per subscription.
- `RabbitMqEventConsumer`: `queueName = $"{topic}.{consumerGroup}"` for `Competing`, not bare `topic`.
- `Ago.Platform.Messaging.Kafka`: audit the equivalent path - Kafka's own consumer-group semantics may
  already get this right natively (a consumer group id is already required by the Kafka client), in
  which case this item only needs to confirm that and note it, not change code there.
- Update every existing `Competing`-mode `SubscribeAsync` call site (`ago-chat`: `UnreadCounterConsumer`,
  `ConnectionFanoutConsumer`, `ConversationAssignmentFanoutConsumer`, `OperatorDisconnectGraceConsumer`,
  `SiteCacheInvalidationConsumer`, `AttachmentThumbnailConsumer`, and `Ago.Platform.Realtime`'s
  `NodeDeliveryConsumer`) to pass their own class name (or equivalent stable identifier) as the group.
- Version bump + `CHANGELOG.md` entry for `Ago.Platform.Abstractions`/`Ago.Platform.Messaging.RabbitMq`
  (breaking port change - `repositories.md`).

## Out of scope

- Any change to `Ago.Chat.Worker`'s own consumer *logic* - this is purely a queue-naming/topology fix.
- The N-queue consistent-hash topology `concurrency.md` describes for per-key ordering at scale -
  `RabbitMqEventConsumer`'s own doc comment already calls that a separate, later concern.
- Retroactively re-verifying every past backlog item's "live verification" claims that touched
  realtime delivery - not practical, and this item's own fix plus a real regression test is what
  actually matters going forward.

## Done when

- [x] A test reproduces the bug against a real broker (Testcontainers RabbitMQ, matching this
      project's own precedent): two distinct `Competing` consumer types subscribed to the same topic,
      N messages published, and the test asserts **both** consumer types received **all** N messages -
      failing against the current code, passing after the fix.
      `RabbitMqPublishConsumeTests.Competing_TwoDifferentConsumerTypes_BothReceiveEveryMessageIndependently` -
      confirmed failing before the fix (by construction: two `SubscribeAsync` calls with different
      names collapsed to the same bare-topic queue name pre-fix), passing after. The existing
      `Competing_TwoConsumers_EachMessageGoesToExactlyOne` test was renamed
      `..._TwoReplicasOfTheSameConsumer_...` and updated to pass the *same* `consumerName` to both
      subscriptions - it was accidentally proving the opposite scenario's own correct behaviour
      (replicas sharing a queue) under a name that suggested it covered this bug too.
- [x] `IEventConsumer.SubscribeAsync`'s new parameter is threaded through every real call site -
      9 in total, more than this item's own Scope list first named (`Ago.Platform.Caching.Redis`'s
      `CacheInvalidationConsumer` and 3 `Ago.Chat.Integration.Tests` call sites were found only by
      actually building with the new required parameter and fixing every resulting compile error, not
      by re-reading the Scope list). The parameter being *required* means the compiler itself is the
      "catches a future addition that forgets it" mechanism promised below - a distinctness mistake
      (two consumer types accidentally passed the same name) is not something an architecture test can
      catch without deeper semantic analysis, and stays a code-review discipline note, not a passing
      test pretending otherwise.
- [x] Manually re-verified against the local cluster: the exact scenario that found this (an operator
      sends several messages in quick succession; the visitor's already-open widget/harness connection
      receives every one live, no reload needed) - proven, not assumed. First attempt after the queue
      fix alone still failed differently: messages *arrived* (`RabbitMqPublishConsumeTests` already
      proved the queue-collision fix itself) but every field read `undefined` client-side - a second,
      independent bug this same verification pass surfaced, see below. After both fixes: 7 operator
      messages sent in a row, all 7 received live by the visitor, correctly populated, in order, zero
      reload.
- [x] `messaging.md` updated: the `Competing` mode description states the consumer-group requirement
      as shipped fact, referencing this item rather than only living in this backlog file.
      `adr/0006` also amended - the new parameter reads at first glance like the consumer-group
      *mechanism* that ADR explicitly kept out of the port; the amendment states why it isn't (identity
      vs. mechanism) rather than leaving that tension unresolved for a future reader.
- [x] `Ago.Platform.Abstractions` and `Ago.Platform.Messaging.RabbitMq`'s `CHANGELOG.md` entry added
      (one shared `ago-platform` `CHANGELOG.md`, `[0.11.0]`), version bumped per `repositories.md`'s
      SemVer rule - a breaking port signature change, minor-bumped per this project's own established
      pre-1.0 precedent (`0.9.0`'s `ICache` constraint took the same path).

## A second, independent bug found while proving this one - fixed in the same change

Fixing the queue collision let messages reach the browser for the first time under real conditions,
which immediately surfaced a second bug the first one had been masking: every field arrived
`undefined`. Root cause, confirmed by reading the code, not guessed: `Ago.Chat.Api`'s SignalR hub
protocol uses `camelCase` property names by default (no `AddJsonProtocol` override), which a hub
method sending a real POCO (`VisitorHub`/`OperatorHub`'s own local-echo `SendAsync(method, dto, ...)`)
gets for free. `ResolveMessageDeliveryTargetsHandler` and `ResolveConversationAssignmentTargetsHandler`
instead pre-serialize the DTO to a JSON *string* for the outbox/broker hop with a plain
`JsonSerializer.Serialize(dto)` (default options - PascalCase), and `SignalRConnectionDispatcher`
re-parses that string into a `JsonElement` before handing it to SignalR - a `JsonElement` re-emits its
own already-baked-in property names verbatim, never consulting the hub protocol's naming policy again.
Fixed with a shared `Ago.Chat.Contracts.WireJsonOptions` (`PropertyNamingPolicy = CamelCase`), used at
both call sites; a pre-existing test's own plain `Deserialize<MessageDto>` on the payload broke as a
direct, expected consequence and was updated to match, plus a new
`HandleAsync_PublishesThePayloadWithCamelCasePropertyNames` regression test. Not filed as a separate
backlog item - discovered, diagnosed, and fixed within the scope of proving *this* item's own live
verification, and fixing it here is what let that verification actually complete rather than stall on
a second, adjacent bug.

## Open questions

None - the bug, its root cause, and the fix shape are all confirmed by reading the actual source, not
inferred. The only real design choice (a `consumerName` string vs. deriving it automatically from the
handler's own type name via reflection) is an implementation detail, resolved as a required, explicit
parameter - fails loudly if forgotten, rather than silently deriving something that could collide
again in a different way.
