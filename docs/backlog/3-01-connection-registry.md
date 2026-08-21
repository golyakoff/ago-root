# Connection registry: who is connected where

- **Stage**: 3
- **Status**: done
- **Depends on**: nothing - foundational for the rest of Stage 3

## Goal

Any `Ago.Chat.Api` replica can answer "which node(s) hold this visitor/operator's connections right
now" via Redis, with TTL + heartbeat refresh so a crashed node's entries expire on their own
(`realtime.md`, `adr/0007`, `adr/0009`). Nothing reads this registry to make a write-side decision -
it is advice, never truth.

## Context to read first

`docs/architecture/realtime.md` (Connection registry, Failure behaviour sections),
`docs/architecture/caching.md` (the three Redis roles - this is role 1, not role 2), `adr/0007`,
`adr/0009`, `adr/0010`, `docs/conventions/naming-and-structure.md` (`Ago.Platform.Realtime`'s
described contents: "connection registry, node routing, hub base types").

## Scope

- `IConnectionRegistry` port in `Ago.Platform.Abstractions` (no domain concept - "register this
  connection id under this node/principal, look up connections for a principal, remove on
  disconnect" - the qualifying rule in `clean-architecture.md` is satisfied: nothing here names
  chat, visitors, or operators).
- `Ago.Platform.Realtime` (new project): Redis-backed implementation. Keys exactly as
  `realtime.md` specifies: `conn:{connection_id}`, `presence:visitor:{visitor_id}`,
  `presence:operator:{op_id}`, `node:{node_id}:conns`. Every key TTL'd; a heartbeat
  (`BackgroundService`, `PeriodicTimer`, matching `concurrency.md`'s rules) refreshes them from
  each `Api` node for its own live connections.
- The Redis connection itself (`IConnectionMultiplexer`, one per process, registered as a
  singleton) is set up here since this is the first Stage 3 slice to need it - `3-04` (caching)
  reuses the same registration rather than opening a second connection.
- Wire-up in `Ago.Chat.Module`/`Ago.Chat.Api`: `VisitorHub`/`OperatorHub` register a connection on
  `OnConnectedAsync`, deregister on `OnDisconnectedAsync`, and the heartbeat keeps live ones
  refreshed. This slice does **not** yet change how delivery happens (that's `3-02`) - it only
  makes "who is where" a queryable fact.
- Node identity: each `Api` pod needs a stable `node_id` for its own lifetime (pod name via
  `HOSTNAME` env var, already set by Kubernetes - no new mechanism needed).

## Out of scope

- Using the registry for delivery - `3-02`.
- Presence *derived state* shown to operators (online/away with a grace period) - `realtime.md`
  mentions it but no roadmap deliverable names a UI or API for it yet; revisit when Stage 5's
  console needs it.
- Rate limiting and caching - `3-04`, `3-05`, even though they share the Redis connection.

## Done when

- [x] `Ago.Chat.Concurrency.Tests` or `Integration.Tests`: two connections from the same visitor
      (simulating a reconnect before the old one times out) both appear in the registry; the old
      one's entry expires on its own once its TTL lapses without a heartbeat (no manual cleanup
      needed) - proves the "advice, not truth, cleanup is a fast path not the correctness
      mechanism" claim in `realtime.md`, not just asserts it. (`HubConnectionRegistrationTests` in
      `Ago.Chat.Integration.Tests`, real Redis via Testcontainers; the equivalent proof also lives
      at the platform level in `Ago.Platform.Integration.Tests.ConnectionRegistryTests`.)
- [x] A node's entries are removed immediately on graceful shutdown (`realtime.md`: "On graceful
      shutdown a node deletes its own entries"). `IConnectionRegistry.RemoveNodeAsync` implements
      and tests this; wiring it to a real shutdown hook is `3-06`'s job (noted in `realtime.md`).
- [x] `Ago.Platform.Architecture.Tests`: `Ago.Platform.Realtime` does not reference any
      `Ago.Chat.*` type - the platform-never-knows-a-product rule, same as every other platform
      project.
- [x] `docs/architecture/realtime.md` gets a "Shipped" note the same way `data-model.md` tracks
      shipped vs. forward-looking sections, if anything here diverges from what it currently says.
      (It did: the schema had no shipped `status`/`site_id` fields, and the failure-mode swallowing
      wasn't documented - both corrected rather than left to drift.)

## Open questions

None - the key schema and TTL/heartbeat rule are already fully specified in `realtime.md`.
