# Realtime transport

## Transport

SignalR over WebSockets, with long-polling as the fallback the widget must tolerate (corporate
proxies exist). Two hubs on `Ago.Chat.Api`:

- `/hubs/visitor` - authenticated by a signed visitor token (JWT), scoped to one site. Issued by
  `POST /api/v1/visitor-sessions` on first contact - the real mechanism, not a stub (`1-06`).
- `/hubs/operator` - authenticated by the operator's JWT, scoped to one site, carrying its
  `adr/0016` role claims. Issued today by `POST /dev/operator-session`, a Development-only stub
  (`1-06`) that trades an operator id for a token with no password - OIDC replaces it outright at
  Stage 5, not by evolving it (`architecture/authorization.md`). Both schemes validate against the
  same signing key with different audiences (`Visitor` / `Operator`), so a token minted for one hub
  is rejected by the other.

A hub method is transport, not logic: it maps arguments to a command, dispatches it, maps the result
back. Anything else in a hub is a layering violation (`clean-architecture.md`).

## Connection registry

Any replica may accept any connection (`edge.md` - no sticky sessions). To deliver an event to a
person, a node must know who is connected where:

```
conn:{connection_id}          -> node_id, site_id, principal        TTL, refreshed by heartbeat
presence:visitor:{visitor_id} -> set of connection_ids
presence:operator:{op_id}     -> set of connection_ids, status
node:{node_id}:conns          -> set, used for bulk cleanup on node death
```

Rules that keep this from rotting:

- Every key has a TTL and is refreshed by a heartbeat. A crashed node's entries expire on their own;
  cleanup is a fast path, not the correctness mechanism.
- On graceful shutdown a node deletes its own entries.
- Registry contents are **advice**, not truth. Delivery to a stale entry fails harmlessly; the client
  reconnects and re-registers. Any logic that would corrupt data because the registry was stale is a
  bug in that logic.

## Fan-out path

1. Consumer in `Ago.Chat.Worker` handles `MessageAccepted`.
2. It resolves recipients (participants of the conversation) and looks up their connections.
3. It groups by `node_id` and publishes a `DeliverToConnections` command-event per node.
4. Each `Api` node consumes only its own queue/partition and pushes to local connections.

Why this instead of the standard **Redis backplane**: the backplane broadcasts every message to
every node, which is fine at three nodes and wasteful at thirty, and it puts the delivery path in a
component we have already declared lossy. Routing by registry means each message crosses the network
once per *involved* node. The cost is complexity and one extra hop, which is exactly the trade-off
recorded in `adr/0007` and measured in Stage 7.

## Client protocol

- Client sends `{ clientMessageId, conversationId, body, attachmentId? }`. `clientMessageId` is a
  client-generated uuid used for **echo suppression and retry deduplication** - a retried send after
  a flaky reconnect must not create a second message. The server maps it to the persisted id in the ack.
- Server assigns `sequence`; clients order by it and never by arrival time or client clock.
- On reconnect the client sends its last known `sequence` per open conversation and receives the
  delta. This makes reconnect cheap and makes "did we lose a message" answerable.
- Server may send `reconnect(after: jitteredDelay)` before shutting down; clients obey it.

## Presence and typing

High-frequency, low-value events. Rules:

- Never persisted, never outboxed, never a reason to write to PostgreSQL.
- Typing indicators are throttled client-side (one event per ~2 s while typing) and coalesced
  server-side. An unthrottled typing indicator is a self-inflicted load test.
- Presence is derived from the registry plus an explicit operator status, with a grace period so a
  page reload does not read as "went offline" and release their conversations.

## Failure behaviour

| Failure | Effect |
|---|---|
| One `Api` replica dies | Its clients reconnect elsewhere; registry entries expire; no data loss |
| Redis unavailable | New connections still accepted; cross-node delivery degrades; messages are still persisted and will be delivered on reconnect |
| Broker unavailable | Sends fail fast with a retryable error; outbox rows accumulate and drain when it returns |
| Postgres unavailable | Sends are rejected (never acked). This is the one dependency without a graceful degradation, by design |
