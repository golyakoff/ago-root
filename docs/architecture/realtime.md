# Realtime transport

## Transport

SignalR over WebSockets, with long-polling as the fallback the widget must tolerate (corporate
proxies exist). Two hubs on `Ago.Chat.Api`:

- `/hubs/visitor` - authenticated by a signed visitor token (JWT), scoped to one site. Issued by
  `POST /api/v1/visitor-sessions` on first contact - the real mechanism, not a stub (`1-06`) - and
  **renewed for the same `VisitorId`** by `POST /api/v1/visitor-sessions/renew` (`17-07`,
  `adr/0048`), which is what lets the token's lifetime be short without a returning visitor losing
  their conversation.

  The renewal has one consequence that belongs here rather than in an auth document, because it is a
  property of the *connection*: **a client's access-token factory is called on every negotiate, the
  first connect and every automatic-reconnect attempt alike, so it must read the current token
  rather than close over one.** A connection established days ago and dropped renegotiates with
  whatever that factory returns at that moment; a captured token means the reconnect presents a
  credential renewal has already replaced, and the client sits in "reconnecting" forever against a
  server that is right to reject it. Both clients in this project reached that shape independently -
  `ago-console` in `5-16` (an OIDC renewal used to rebuild the whole connection), `ago-widget` in
  `17-07` (the capture was harmless only while the visitor token never rotated).
- `/hubs/operator` - authenticated by the operator's JWT, scoped to one site. **Shipped in `5-05`**:
  a real Keycloak-issued OIDC token, validated directly against Keycloak's own JWKS (`adr/0022`) -
  `POST /dev/operator-session`, the Development-only stub that traded an operator id for a token with
  no password (`1-06`), is removed outright, not evolved. Keycloak's token proves identity; it carries
  no `OperatorId`/`SiteId`/`adr/0016` role information of its own (Keycloak has never heard of those
  concepts) - `OperatorIdentityClaimsTransformation` resolves the validated token's `sub` against the
  `operators` table and adds those claims after the fact, and role/permission resolution
  (`PermissionChecker`) is unaffected, still a separate per-request lookup. The Visitor scheme is
  unchanged: still a token `Ago.Chat.Api` signs itself, still validated against the local signing key,
  since visitors were never behind the stub this item replaced - the two schemes' distinct audiences
  are what still keeps a token minted for one hub from being accepted by the other.

A hub method is transport, not logic: it maps arguments to a command, dispatches it, maps the result
back. Anything else in a hub is a layering violation (`clean-architecture.md`).

## Connection registry

**Shipped in `3-01`**: any replica may accept any connection (`edge.md` - no sticky sessions). To
deliver an event to a person, a node must know who is connected where. `IConnectionRegistry`
(`Ago.Platform.Abstractions`) is deliberately domain-free - it knows connections, nodes and an
opaque `PrincipalKey`, never a visitor or an operator (`clean-architecture.md`'s qualifying rule);
`Ago.Chat.Application.Realtime.PrincipalKeys` is the one place chat maps its own identities onto
that key (`visitor:{id}` / `operator:{id}`), reused by `VisitorHub`/`OperatorHub` today and by the
fan-out consumer `3-02` adds. `Ago.Platform.Realtime`'s `RedisConnectionRegistry` implements it
exactly on the schema below, with a `ConnectionHeartbeat` (`PeriodicTimer`, default 10s) refreshing
every connection an `Ago.Chat.Api` node's `LocalConnectionTracker` still holds - `RegisterAsync` is
the refresh, not a separate operation, so there is nothing to keep in sync between the two:

```
conn:{connection_id}          -> node_id, principal                 TTL, refreshed by heartbeat
presence:visitor:{visitor_id} -> set of connection_ids
presence:operator:{op_id}     -> set of connection_ids
node:{node_id}:conns          -> set, used for bulk cleanup on node death
```

(`status` on the operator presence set and `site_id` on the connection entry are not part of the
shipped shape - nothing built so far needs either; add them when a real caller does, rather than
guessing at the second one now.)

**Shipped in `5-07`**: the first caller that reads presence *for* an operator, not just tracks an
operator's own. Building the console's queue view found two real gaps, both closed with the smallest
addition that used what already existed rather than new infrastructure:

- **Presence had no operator-facing query.** `IConnectionRegistry.GetConnectionsAsync` (this file's
  own port) had tracked visitor connections since `3-01`, but nothing had ever called it on an
  operator's behalf - `OperatorPresencePublisher` only *publishes* the operator's own presence loss,
  one-directional, to the visitor. `GetVisitorPresenceHandler` (`Ago.Chat.Application`) is the
  addition: loads the conversation, checks `conversation:read`, confirms the caller is the assigned
  operator, then answers from the same registry query the fan-out path already trusts. Exposed as
  `OperatorHub.GetVisitorPresenceAsync(conversationId) -> bool` - a snapshot the console re-polls
  (every 10s), not a push, matching the registry's own "advice, not truth" contract: a stale answer
  is a harmless wrong-looking dot in the UI, not worth a new push mechanism to avoid.
- **Nothing let an operator learn "what's waiting, what's mine" except a live push.** `4-02`'s
  assignment engine notifies a *connected* operator of a new assignment over the hub
  (`"ConversationAssigned"`), but an operator who was offline when it happened, or who just opened
  the console, had no way to ask. `GetOperatorQueueHandler` answers it from
  `IConversationRepository.GetWaitingForSiteAsync` (new) and `GetAssignedToOperatorAsync` (`4-04`'s
  existing method, reused) - exposed as `GET /api/v1/conversations/queue`
  (`Ago.Chat.Api.Conversations.ConversationsEndpoints`), a plain authenticated REST read rather than a
  hub method, since it is an ordinary query, not connection-scoped or high-frequency (api-design.md).
  The "waiting" half only refreshes on the console's own poll and on load - nothing broadcasts "a new
  conversation started waiting" to every operator of a site (only the operator it eventually gets
  assigned to ever hears about it), and since the waiting list is read-only situational awareness in
  `docs/vision.md`'s automatic-assignment model, not something an operator acts on directly, a short
  poll was judged a reasonable, stated limit rather than a reason to build a new fan-out broadcast this
  item was never scoped to need.

Rules that keep this from rotting:

- Every key has a TTL and is refreshed by a heartbeat. A crashed node's entries expire on their own;
  cleanup is a fast path, not the correctness mechanism.
- On graceful shutdown a node deletes its own entries. `IConnectionRegistry.RemoveNodeAsync` does
  this; wiring it to an actual shutdown hook is `3-06`'s job, not `3-01`'s - today nothing calls it
  yet, so a killed `Api` pod relies entirely on TTL expiry, which is the documented, acceptable
  fallback either way.
- A registry call that fails (Redis unreachable, timed out) is swallowed and logged, never thrown
  into a hub method - the same "advice, not truth" contract extended from staleness to errors
  (`adr/0009`, this table's own "Redis unavailable" row below).
- Registry contents are **advice**, not truth. Delivery to a stale entry fails harmlessly; the client
  reconnects and re-registers. Any logic that would corrupt data because the registry was stale is a
  bug in that logic.

## Fan-out path

**Shipped in `3-02`**: the mechanism is split exactly at the product/platform seam
(`clean-architecture.md`'s qualifying rule) - resolving *who* and deciding *what payload* is
product-specific; routing *where* is generic.

1. `ConnectionFanoutConsumer` (`Ago.Chat.Worker`) handles `MessageAccepted` (`Competing`, same as
   `UnreadCounterConsumer` - exactly one `Worker` replica per message) and calls
   `ResolveMessageDeliveryTargetsHandler` (`Ago.Chat.Application`).
2. That handler resolves the conversation's participants (visitor always, operator once assigned)
   into `Ago.Platform.Abstractions`' opaque `PrincipalKey`s and fetches the message content, then
   calls `INodeFanoutPublisher.PublishAsync` - the one call that hands off to the generic half.
3. `NodeFanoutPublisher` (`Ago.Platform.Realtime`) resolves each principal's connections via
   `IConnectionRegistry`, groups by `NodeId`, and publishes one `NodeDelivery` per node to that
   node's own topic (`deliver-to-connections.{node_id}`, `NodeTopics`) - `Competing` mode, not
   `Broadcast`: exactly one process ever subscribes to a given node's own topic, and `Competing`'s
   stable queue name avoids leaking a fresh retry queue on every restart the way `Broadcast`'s
   random-suffixed queue would (`NodeDeliveryConsumer`'s own comment has the detail). Publishes
   directly via `IEventPublisher`, bypassing the outbox - `adr/0020` is why that is sound here and
   not a violation of `adr/0005`.
4. Each `Api` node's own `NodeDeliveryConsumer` consumes only its own topic and calls
   `ILocalConnectionDispatcher.DispatchAsync` per connection - implemented by
   `Ago.Chat.Api`'s `SignalRConnectionDispatcher`, the one place that knows a connection id belongs
   to `VisitorHub` or `OperatorHub` (via `LocalConnectionTracker`, the same map `3-01`'s
   `HubConnectionRegistration` populates on connect).

**Shipped in `7-08`**: the path above is instrumented end to end, after an incident where "did the
server even try to deliver that message to the operator's connection?" took an hour to answer because
nothing in the running system could. Delivery behaviour is unchanged - every delivery is still
acknowledged regardless of per-connection outcome, and a stale registry entry is still a harmless
no-op - but the difference between reaching everybody and reaching nobody is now visible:

- **Step 3 writes to the span that already brackets it** (`7-01`'s `"{topic} process"` span, not a new
  child): `ago.fanout.recipients`, `ago.fanout.connections` (three open tabs is three, not one) and
  `ago.fanout.nodes`. `INodeFanoutPublisher.PublishAsync` also *returns* those per-recipient counts as
  a `FanoutResult`.
- **Step 2 turns that into `ago.chat.delivery.recipients`**, one point per recipient per fan-out,
  tagged `method`, `recipient_kind` (`visitor`/`operator`) and `presence` (`connected`/`absent`). The
  dimensioning is the decision, not the counter: a visitor with no connection is ordinary, an operator
  with none is not, and a raw "delivered to zero" count could not tell them apart (`adr/0044`).
- **Step 4 turns the per-connection outcome into `ago.platform.realtime.dispatches`**, tagged `node`
  and `outcome` (`delivered` / `connection_not_local` / `failed`). `ILocalConnectionDispatcher` now
  returns a `DispatchOutcome` so that number comes from the code that actually decides it, rather than
  from a proxy for the same fact next to the call - `7-07`'s lesson applied before shipping instead of
  after. `ConnectionDrainCoordinator` uses the same port and deliberately does not feed this counter.

No alert reads any of it yet; `15-03` decides that with real data. The one thing this must not be read
as saying is that `connection_not_local` is a fault - it is this file's own "advice, not truth"
contract working exactly as designed, and only its *rate* is interesting.

The sender's own connection gets an immediate local echo (`Clients.Caller`) without waiting on this
whole round trip - a latency optimisation, not a second delivery mechanism (`VisitorHub`'s
`EchoToCallerAsync`). It also receives the real fan-out delivery again once that completes; nothing
excludes it, and messaging.md's client-side dedupe-by-message-id already covers the duplicate the
same way it covers a redelivered broker message.

Why this instead of the standard **Redis backplane**: the backplane broadcasts every message to
every node, which is fine at three nodes and wasteful at thirty, and it puts the delivery path in a
component we have already declared lossy. Routing by registry means each message crosses the network
once per *involved* node. The cost is complexity and one extra hop, which is exactly the trade-off
recorded in `adr/0007` and measured in Stage 7.

## Client protocol

- Client sends `{ clientMessageId, conversationId, body, attachmentId? }`. `clientMessageId` is a
  client-generated uuid used for **echo suppression and retry deduplication** - a retried send after
  a flaky reconnect must not create a second message. The server maps it to the persisted id in the ack.
  **Shipped in `5-07`**: `SendMessageAsync(conversationId, body, attachmentId?, clientMessageId?)` on
  both hubs - `clientMessageId` appended *last*, after `attachmentId`, not inserted between the
  existing parameters, so every caller built before this shipped (`dev-harness.html`, `ago-widget`'s
  `VisitorConnection`) keeps binding correctly with it simply omitted (SignalR's client binder matches
  by argument count and position, not by name - inserting it earlier would have silently reinterpreted
  an existing 3-argument call's `attachmentId` as a `clientMessageId`). The actual dedup mechanism
  lives in `Conversation.AddMessage` (`Ago.Chat.Domain`): a repeated `clientMessageId` returns the
  *original* `Message` unchanged, the same no-op-on-repeat shape `AssignTo` already established -
  checked against the aggregate's own already-loaded `Messages` (free, and catches a same-batch
  duplicate a database index alone cannot), backed by a partition-widened unique index
  (`(conversation_id, client_message_id, created_at)`, mirroring `adr/0019`'s reasoning for the
  neighbouring `sequence` index) as the storage-level backstop for two processes racing the same
  retry concurrently. Proven live: two `SendMessageAsync` invocations with the same `clientMessageId`
  returned the identical `sequence` both times, and exactly one row landed in `messages`. `ago-widget`
  itself was not updated to send one - a real, low-cost follow-up, not done here since `5-07`'s own
  scope is the console.
  - **Found live in `5-07`**: `MessageDto` was missing a `conversationId` field entirely. The fan-out
    delivery path (`ConnectionFanoutConsumer` -> `NodeFanoutPublisher` -> `SignalRConnectionDispatcher`)
    delivers straight to a connection with no SignalR group involved, so a `"MessageReceived"` push for
    *any* conversation an operator is assigned to lands on their one connection - harmless for the
    widget (a visitor only ever has one conversation) but genuinely ambiguous for an operator handling
    several at once, who would have no way to tell which open thread a push belonged to. Added as an
    additive field (a DTO's wire shape has no positional constraint the way a hub method's arguments do).
- Server assigns `sequence`; clients order by it and never by arrival time or client clock.
- **Shipped in `3-03`**: on reconnect the client sends its last known `sequence` per open
  conversation and receives exactly the delta - `VisitorHub.JoinAsync`/`OperatorHub`'s
  `JoinConversationAsync` both take an optional `lastKnownSequence`, and when it is present (and the
  conversation is not one this same call just created - nothing to have missed there)
  `GetConversationHistoryHandler.HandleDeltaAsVisitorAsync`/`HandleDeltaAsOperatorAsync` answer with
  every message strictly after it, oldest first, via `IConversationReadStore.GetDeltaAsync` - the
  same access checks as the ordinary history page, a different cursor direction on the same read
  store, not a new handler class. Unbounded rather than keyset-paginated the way the "load older
  messages" direction is: the gap this closes is bounded by how long *one* client was disconnected,
  not by the conversation's whole history. Client-side backoff is exponential with full jitter
  (`edge.md`'s rolling-deploy scenario is exactly why - without jitter a mass reconnect becomes a
  self-inflicted thundering herd), proven by hand against `Ago.Chat.Api/wwwroot/dev-harness.html`:
  a dropped connection logs its jittered retry delays, reconnects, and resumes with exactly the
  message sent while it was down - no gap, no duplicate, no full replay of the whole conversation.
- Server may send `reconnect(after: jitteredDelay)` before shutting down; clients obey it. Stubbed in
  `3-03` (`VisitorHub.ReconnectAsync`/`OperatorHub.ReconnectAsync` push the wire message; the harness
  already listens for it) - `3-06` (graceful shutdown) is the real caller, since nothing runs the
  drain sequence yet that would need to call it.
  **Doc correction, `5-07`**: there is no `ReconnectAsync` hub *method* on either hub, and never was -
  the real mechanism is `Ago.Platform.Realtime.ConnectionDrainCoordinator` (a generic platform
  `BackgroundService.StopAsync` override, not product code), which on graceful shutdown pushes a
  `"Reconnect"` event with `{ after }` to every locally-tracked connection via the same
  `ILocalConnectionDispatcher` fan-out delivery uses. A client listens for the *event*
  (`connection.on("Reconnect", ...)`), it never calls a method named that.
  **Shipped in `11-06`**: `ago-console` is the first client that does anything with the event beyond
  receiving it. It is the console's only *honest* source for a "degraded" connection indicator - the
  connection is up and still usable, and the server has said it is about to go away - which is why the
  workspace shows a distinct "Server restarting" state for it and shows nothing at all for the other
  degradations in this file's failure table: a client whose cross-node delivery is degraded because
  Redis is unavailable sees a perfectly healthy WebSocket and simply receives a message later, so an
  indicator claiming otherwise would be inventing a state the system does not report.

**Shipped in `5-07`**: `OperatorHub.JoinConversationAsync` calling into `AssignConversationHandler`
unconditionally on every join (its own doc comment: making `Conversation.AssignTo`'s same-operator
no-op load-bearing) means any operator holding `conversation:assign` who calls it against a
still-`Waiting` conversation *does* directly claim it - the same primitive `4-02`'s automatic engine
uses, reachable by a client the engine never authorized. `docs/vision.md`'s assignment model is
automatic-only (no manual claim), so
this is a latent capability the product was never meant to expose, not a feature - `ago-console`
(this item) avoids it structurally by construction: the queue view's "Waiting" list is read-only and
non-navigable, only "Assigned to me" rows link anywhere, so the console itself never calls
`JoinConversationAsync` against a conversation still `Waiting`. Worth a future guard
(`AssignConversationHandler` rejecting a claim attempt against a conversation the caller was not
already assigned unless the caller genuinely has a supervisor-style override) if `5-08`'s admin view
ever lets an operator browse conversations outside their own queue - out of scope here since nothing
in `5-07` needed it.

## Presence and typing

High-frequency, low-value events. Rules:

- Never persisted, never outboxed, never a reason to write to PostgreSQL.
- Typing indicators are throttled client-side (one event per ~2 s while typing) and coalesced
  server-side. An unthrottled typing indicator is a self-inflicted load test.
- Presence is derived from the registry plus an explicit operator status, with a grace period so a
  page reload does not read as "went offline" and release their conversations.

  **Shipped in `4-04`**: the first thing that actually *reads* presence for a real write decision,
  not just tracks it (`adr/0007`'s "advice, not truth" caveat now has a real consequence to be
  honest about). Two triggers publish the same `OperatorPresenceLost` signal: `OperatorHub`'s
  query-at-disconnect fast path (`HubConnectionRegistration.OnDisconnectedAsync` now returns
  whether the principal has zero connections left anywhere, not just on this node) and
  `OperatorDisconnectSweepJob`'s periodic backstop (`Ago.Chat.Worker`, catches a disconnect that
  never fired the fast path at all - a hard client-side process kill, or `Ago.Chat.Api` itself
  dying mid-publish). `OperatorDisconnectGraceConsumer` waits the grace period, then checks presence
  **exactly once more** before releasing anything - that single final check is the entire
  "cancel a pending release on reconnect" mechanism, no per-operator timer state to track or cancel.

  The honesty consequence: a stale-but-not-yet-expired registry entry biases toward "assume still
  connected," never toward releasing early. Getting this wrong the other way - releasing a
  still-connected operator's conversations - is the more damaging mistake (a visitor mid-conversation
  loses their operator for no reason), so every read in this path leans conservative on purpose. The
  registry's own TTL is still the ultimate backstop if a node crashes without ever deregistering -
  this just adds a second, deliberate leaning-conservative layer on top for the common "graceful
  disconnect, no reconnect" case that TTL alone would only catch late.

## Failure behaviour

| Failure | Effect |
|---|---|
| One `Api` replica dies | Its clients reconnect elsewhere; registry entries expire; no data loss |
| Redis unavailable | New connections still accepted; cross-node delivery degrades; messages are still persisted and will be delivered on reconnect |
| Broker unavailable | Sends fail fast with a retryable error; outbox rows accumulate and drain when it returns |
| Postgres unavailable | Sends are rejected (never acked). This is the one dependency without a graceful degradation, by design |
