# Architecture overview

## Components

```
   visitor page          operator console          operator phone
  [ widget.js ]          [     SPA      ]          [ Android app ]
        |                       |                         |
        |         WebSocket (SignalR) + REST              |   both operator clients
        +-----------+-----------+-------------------------+   share one surface
                    |
              [ NGINX Gateway ]  TLS, coarse rate limits, least_conn,
                    |            no sticky sessions (edge.md)
                    v                                          file bytes go straight to
        +--------------------------------+                     storage, never through the
        |  Chat.Api (N replicas)         |  holds conns,       API - it only signs the
        |  Minimal API + SignalR hubs    |  handles commands,  upload URL --------------+
        +----+--------------+------------+  serves reads,                               |
             |              |               signs upload URLs                           |
   outbox write        publish / subscribe                                             v
             |              |                                              +--------------------+
             v              v                                              | S3 / MinIO         |
   +----------------+  +--------------+                                    | attachments        |
   |   PostgreSQL   |  |   RabbitMQ   |                                    +--------------------+
   | source of truth|  |  (-> Kafka)  |                                              ^
   +----------------+  +------+-------+                                               |
             ^                |                                            thumbnails |
             |                v                                                        |
   +---------+-----------------------------+                                           |
   |  Chat.Worker (N replicas)             |  outbox dispatcher, persistence, --------+
   |  background consumers                 |  assignment engine, thumbnails,
   |                                       |  operator-push fan-out (below), orphan cleanup
   +---------------------------------------+
                       |
                  +----+-----+
                  |  Redis   |  cache + rate limits + connection registry + presence
                  +----------+


   Operator push (adr/0178-0181): when a visitor is waiting, Chat.Worker fans a derived,
   data-only notification out to each of the operator's registered devices. The transport is
   chosen per device, the server never suppresses on presence, and the client - not the
   server - decides whether to make a sound:

        +---------------+  push (no message body)     +----------------------+
        |  Chat.Worker  | --------------------------> |  FCM      (primary)  |
        |  push fan-out |  per device, keyed by       |  RuStore  (fallback) | --> [ Android app ]
        +---------------+  operator_devices.provider  +----------------------+
```

## Three hosts, one solution

`Ago.Chat.Api`, `Ago.Chat.Worker` and `Ago.Chat.Webhooks` are separate processes that share the same
Application and Domain assemblies. This is a **modular monolith with split runtimes**, not
microservices - see `adr/0003-platform-product-split-and-two-hosts.md` (the original Api/Worker split)
and `adr/0013-deployables-and-webhook-bulkhead.md` (the third host, added as a bulkhead against a slow
third party). It buys independent scaling of "holding connections", "doing work" and "calling someone
else's unreliable system" without distributed-transaction pain.

No two hosts ever call each other synchronously. The broker is the only path between them, which is
what makes each one independently restartable. The diagram above shows only `Api` and `Worker` - the
hot path that exists from Stage 1; `Webhooks` arrives in Stage 6 (`resilience.md`).

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

**Operator push** (the native Android client, `adr/0178`-`0181`):

1. The app registers a device against the operator's own account (`operator_devices`, keyed by
   installation, provider chosen per device: FCM primary, RuStore fallback).
2. On `ConversationAssignedToOperator` and on a visitor `MessageAccepted`, a `Worker` consumer fans a
   derived, data-only push out to that operator's devices - the same rule the console's in-tab alerts
   apply, now off the socket.
3. The server never suppresses on presence; the client decides whether to be loud. No message body ever
   leaves the server. Details: `realtime.md`.

## What is authoritative where

| Data | Owner | Notes |
|---|---|---|
| Conversations, messages, assignments, attachment metadata | PostgreSQL | The only source of truth |
| Operator push devices (`operator_devices`, per-device provider) | PostgreSQL | Registration is an idempotent upsert keyed by installation |
| Attachment bytes | S3 / MinIO | Immutable once `ready`; metadata still lives in Postgres |
| Cached site config, operator profiles, hot read pages | Redis | Copies. A flush costs latency, never correctness |
| Which node holds connection X | Redis | Rebuildable, TTL'd, lossy by design |
| Presence / typing | Redis | Ephemeral, never persisted |
| Delivery of events between nodes | Broker | At-least-once, never a store |

Redis losing everything must degrade the system (reconnects, cache misses, stale presence) and never
corrupt it. That constraint is what keeps the whole design honest.
