# ADR-0007: Connection registry instead of a SignalR backplane

- **Status**: Accepted
- **Date**: 2026-08-20
- **Stage**: 3

## Context

With N Api replicas and no sticky sessions, the node holding a visitor is usually not the node
holding their operator. Something must route messages across nodes. The standard answer is the Redis
backplane, which broadcasts every message to every node.

## Decision

Each node registers its connections in Redis (`conn:*`, `presence:*`, `node:*`, all TTL'd and
heartbeat-refreshed). Delivery resolves recipients to owning nodes and sends a targeted
`DeliverToConnections` event through the broker to those nodes only. Registry data is advice: a stale
entry causes a harmless failed delivery and a client reconnect, never data loss.

## Consequences

- Delivery cost scales with the number of *involved* nodes, not with cluster size.
- Presence and connection ownership become queryable facts, which the ops dashboard uses.
- Cost: more moving parts than a backplane, plus one broker hop in the latency budget (`nfr.md`).
  Both are measured in Stage 7 rather than assumed.
- Cost: TTLs, heartbeats and node-death cleanup must be correctness-irrelevant by design, or this
  becomes a distributed-state bug farm.

## Alternatives considered

- **Redis backplane** - three lines of configuration and the right choice for most teams. It
  broadcasts everything everywhere and hides the exact mechanism this project exists to show.
- **Sticky sessions plus per-node state** - moves the problem into the load balancer and makes
  rolling deploys hostile (ADR-0010).
