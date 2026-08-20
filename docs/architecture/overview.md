# Architecture overview

## Components

```
   visitor page                 operator console
  [ widget.js ]                 [    SPA      ]
        |                              |
        |  WebSocket (SignalR) + REST  |          file bytes go straight to storage,
        +--------------+---------------+          never through the API  ---------+
                       |                                                          |
                 [ ingress-nginx ]  TLS, coarse rate limits, least_conn,          |
                       |           no sticky sessions (edge.md)                   |
                       v                                                          |
        +--------------------------------+                                        |
        |  Chat.Api (N replicas)         |  holds connections, handles commands,   |
        |  Minimal API + SignalR hubs    |  serves read queries, signs upload URLs |
        +----+--------------+------------+                                        |
             |              |                                                     |
   outbox write        publish / subscribe                                        |
             |              |                                                     |
             v              v                                                     v
   +----------------+  +--------------+                              +--------------------+
   |   PostgreSQL   |  |   RabbitMQ   |                              | S3 / MinIO         |
   | source of truth|  |  (-> Kafka)  |                              | attachments        |
   +----------------+  +------+-------+                              +--------------------+
             ^                |                                                     ^
             |                v                                                     |
   +---------+-----------------------------+                                        |
   |  Chat.Worker (N replicas)             |  outbox dispatcher, persistence,       |
   |  background consumers                 |  assignment engine, thumbnails, -------+
   +---------------------------------------+  orphan cleanup
                       |
                  +----+-----+
                  |  Redis   |  cache + rate limits + connection registry + presence
                  +----------+
```

## Two hosts, one solution

`Ago.Chat.Api` and `Ago.Chat.Worker` are separate processes that share the same Application and Domain
assemblies. This is a **modular monolith with split runtimes**, not microservices - see
`adr/0003-modular-monolith-two-hosts.md`. It buys independent scaling of "holding connections" and
"doing work" without distributed-transaction pain.

The two hosts never call each other synchronously. The broker is the only path between them, which
is what makes either one independently restartable.

## Request paths

**Visitor sends a message** (the hot path - optimise this one):

1. `Api` receives it over the hub, validates it, assigns a server-side `sequence` within the conversation.
2. One transaction: insert into `messages` + insert into `outbox`. The ack goes to the sender only
   after that transaction commits.
3. `Worker`'s outbox dispatcher publishes `MessageAccepted`, keyed by `conversation_id`.
4. The fan-out consumer resolves which `Api` nodes hold the recipients (Redis registry) and delivers.

**Visitor sends a file:**

1. `Api` checks quotas and rate limits, records a `pending` attachment, returns a presigned PUT URL.
2. Browser uploads directly to storage; `Api` verifies the object before marking it `ready`.
3. The message referencing it then travels the normal hot path above. Details: `file-storage.md`.

**Operator assignment** (the contended path):

1. A conversation with no operator sits in state `waiting`.
2. The assignment engine in `Worker` claims candidates with `SELECT ... FOR UPDATE SKIP LOCKED`,
   respects per-operator capacity, and writes the assignment with optimistic concurrency.
3. `ConversationAssigned` is published; both parties are notified through the same fan-out path.

## What is authoritative where

| Data | Owner | Notes |
|---|---|---|
| Conversations, messages, assignments, attachment metadata | PostgreSQL | The only source of truth |
| Attachment bytes | S3 / MinIO | Immutable once `ready`; metadata still lives in Postgres |
| Cached site config, operator profiles, hot read pages | Redis | Copies. A flush costs latency, never correctness |
| Which node holds connection X | Redis | Rebuildable, TTL'd, lossy by design |
| Presence / typing | Redis | Ephemeral, never persisted |
| Delivery of events between nodes | Broker | At-least-once, never a store |

Redis losing everything must degrade the system (reconnects, cache misses, stale presence) and never
corrupt it. That constraint is what keeps the whole design honest.
