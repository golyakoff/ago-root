# Targeted fan-out: deliver across nodes without a backplane

- **Stage**: 3
- **Status**: done
- **Depends on**: `3-01-connection-registry.md`

## Goal

A message accepted on one `Api` node reaches a recipient connected to a *different* node, routed
through the registry and the broker - never a Redis backplane broadcasting to every node
(`adr/0007`). This replaces `VisitorHub`/`OperatorHub`'s current same-process-only delivery, which
today only works because both hubs happen to live in the same `Ago.Chat.Api` instance and there is
exactly one replica.

## Context to read first

`docs/architecture/realtime.md`'s Fan-out path section (the four-step mechanism), `messaging.md`
(event contracts, `Broadcast` vs `Competing` subscription modes - this needs `Competing`, since
exactly one node should get the batch of connections it owns, not every node), `adr/0007`. Also
read `Ago.Chat.Api/Hubs/VisitorHub.cs`'s `BroadcastAsync` - its own comment already documents the
gap this slice closes ("SignalR hubs are isolated from each other").

## Scope

- The recipient-resolution → node-grouping → per-node publish → per-node consume → local-push
  mechanism is **generic** (no domain concept - "given a set of connection ids grouped by node,
  deliver this payload to each node's own local connections"), so it lives in
  `Ago.Platform.Realtime`, not `Ago.Chat.*` (`clean-architecture.md`'s qualifying rule: a second
  product would plausibly use this unchanged). The **product-specific** half - "who are the
  participants of this conversation, and what payload do they get" - stays in
  `Ago.Chat.Application`/`Ago.Chat.Worker`.
- `Ago.Chat.Worker` (or a new consumer alongside `UnreadCounterConsumer`): on `MessageAccepted`,
  resolves the conversation's participants, looks up their connections in the registry (`3-01`),
  groups by `node_id`, publishes one `DeliverToConnections`-shaped event per node via the
  platform's generic publish helper.
- Each `Ago.Chat.Api` node runs a consumer (its own node's queue - `Competing` mode scoped to that
  node, via the existing `RetryPolicy`/queue-naming machinery) that receives only its own
  connections' deliveries and pushes to them locally (`Clients.Client(connectionId)`, not
  `Clients.Group` - the group-based approach is exactly what does not survive across nodes).
- Replace `VisitorHub.BroadcastAsync`'s direct `Clients.Group` + cross-hub `IHubContext<OperatorHub>`
  call with a call into this new path. The sender's own connection still gets an immediate local
  ack/echo without waiting on the broker round trip (a same-node fast path is a legitimate
  optimisation, but it must not become a second, divergent delivery mechanism - one path, taken
  fastest when sender and recipient share a node).
- A stale registry entry causing a failed delivery must be harmless (`realtime.md`) - prove this,
  not just claim it.

## Out of scope

- The `CacheInvalidated` broadcast-to-every-node pattern (`messaging.md`'s Topics table) - different
  subscription mode, different purpose, not needed until `3-04`.
- Presence/typing fan-out - `realtime.md` names these as never-persisted, throttled separately;
  no roadmap deliverable asks for them yet.
- Multi-replica `Worker` behaviour beyond what `2-04`/`2-05` already proved (outbox dispatch and
  consumption are already safe under multiple `Worker` replicas) - this slice only adds a new
  consumer following that same established shape.

## Done when

- [x] `Ago.Chat.Concurrency.Tests`: two `Ago.Chat.Api` processes (or two DI-composed instances in
      one test process, matching how `PartitionMaintenanceJobTests` runs two job instances) - a
      visitor connection registered on "node A", an operator connection registered on "node B", a
      message sent through node A's hub is received by the operator connection attached to node B.
      This is the concrete proof behind Stage 3's "three Api replicas serve one conversation
      correctly." Placed in `Ago.Chat.Integration.Tests` (`ConnectionFanoutEndToEndTests`), not
      `Concurrency.Tests`: it drives one deterministic message through the real chain once, never
      under stress/race repetition, so `testing.md`'s own level distinction puts it there - the
      equivalent platform-level proof lives in `Ago.Platform.Integration.Tests.NodeFanoutTests`.
- [x] A delivery to a connection whose registry entry has expired does not throw or block the
      publish path - confirms the "advice, not truth" failure mode is real (proven at `3-01`, still
      holds unchanged here since `NodeFanoutPublisher` calls the same `GetConnectionsAsync`).
- [x] `Ago.Platform.Architecture.Tests`: the generic fan-out primitive in `Ago.Platform.Realtime`
      references no `Ago.Chat.*` type.
- [x] `docs/architecture/realtime.md`'s Fan-out path section gets the same "shipped" treatment as
      `3-01`.

## Open questions

None - the mechanism is fully specified in `realtime.md`; this slice implements it.

## Note for a future session

`VisitorHub`/`OperatorHub` no longer use SignalR `Groups` at all - the group-join calls and
`GroupName` helper were dead code once delivery moved to the registry+broker path, and were removed
rather than left in place. `Ago.Chat.Api`'s `Program.cs` runs two new hosted-service-adjacent
consumers (`NodeDeliveryConsumer`) and one new fan-out consumer in `Ago.Chat.Worker`
(`ConnectionFanoutConsumer`) - both need `Redis:ConnectionString` and RabbitMQ configured to start
cleanly, same as `3-01`'s `ConnectionHeartbeat` already required.
