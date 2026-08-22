# Realtime transport

## Transport

SignalR over WebSockets, with long-polling as the fallback the widget must tolerate (corporate
proxies exist). Two hubs on `Ago.Chat.Api`:

- `/hubs/visitor` - authenticated by a signed visitor token (JWT), scoped to one site. Issued by
  `POST /api/v1/visitor-sessions` on first contact - the real mechanism, not a stub (`1-06`).
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
  Not shipped yet - `SendMessageAsync` today takes only `(conversationId, body)`; `clientMessageId`
  is still a design intent, not wired up (nothing in Stage 1-3 needed retry dedup badly enough to
  force it, and forcing it in for `3-03` would have been solving a problem `3-03` was not asked to
  solve).
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
