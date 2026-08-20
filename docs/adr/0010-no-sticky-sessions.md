# ADR-0010: No sticky sessions at the edge

- **Status**: Accepted
- **Date**: 2026-08-20
- **Stage**: 3

## Context

Long-lived WebSockets make session affinity the reflex answer: pin a client to a node and keep its
state there. That choice then propagates into deploys, scaling and failure handling.

## Decision

Any connection may land on any Api replica. Nodes hold no client state that cannot be rebuilt on
reconnect; ownership lives in the registry (ADR-0007). Balancing uses `least_conn`, because
round-robin spreads connection *events* evenly while leaving connection *counts* skewed after any
partial outage. Clients reconnect with exponential backoff plus jitter and resume from their last
known `sequence`.

## Consequences

- Rolling deploys and scale-downs cost a reconnect and nothing else - there is no affinity to lose.
- A dead node is a non-event: its registry entries expire, clients land elsewhere.
- Cost: cross-node delivery pays a broker hop, and every client must implement resume-from-sequence
  correctly. Both are load-tested in Stage 7, including a reconnect-storm scenario.

## Alternatives considered

- **Sticky sessions (cookie or IP hash)** - keeps delivery local when both parties happen to share a
  node, and turns every deploy into a state-migration problem.
- **Sticky sessions plus a backplane** - the common production compromise; it inherits the deploy
  problem without removing the broadcast cost.
