# Vision

## Platform and products

**AGO Platform** is the reusable substrate: hosting, realtime transport, messaging, persistence,
caching, object storage, observability. **AGO Chat** is the first product built on it. **AGO Ads**
(contextual advertising delivered through the same embedded script and the same ingest path) is the
planned second product, and exists in this document mainly as a design constraint: every platform
decision must be defensible without knowing anything about chat.

The split is not decoration. It is the thing that turns "a chat app" into "a platform with a
product on it", and it is what a reviewer will probe: ask whether the platform could host the second
product unchanged, and the answer has to be yes, in code.

## The product

A shop embeds one script tag:

```html
<script src="https://cdn.agochat.dev/widget.js" data-site="shop_7f3a" async></script>
```

A chat launcher appears in the corner. A visitor asks a question; an operator answers from a
console; the conversation survives page reloads and reconnects. That is the whole product.

## Why this project exists

It is a CV piece. Every feature below is chosen because it forces a real engineering problem,
not because a support chat "should" have it.

| Feature | Engineering problem it forces |
|---|---|
| Many small messages, always-on connections | Connection state, backpressure, memory per connection |
| Messages must arrive in order, within a conversation | Ordering under parallel consumers, partition keys |
| A message must never be lost after it is acknowledged | Transactional outbox, at-least-once, idempotency |
| Conversations are assigned to free operators | Contended shared state, race conditions, distributed locking vs `SKIP LOCKED` |
| History is browsable | Cursor pagination, index design, table partitioning |
| It must run on more than one node | Connection registry, cross-node fan-out, no sticky sessions in the data path |
| Widget runs on a stranger's page | Style isolation, bundle size, CORS, per-site rate limits |
| Both sides send files and screenshots | Presigned direct-to-S3 uploads, orphan cleanup, quotas, never streaming bytes through the API |
| The same site config is read on every handshake | Cache-aside, stampede protection, event-driven invalidation, TTL jitter |
| Traffic must spread across replicas | Ingress balancing of long-lived WebSockets, drain-on-deploy, reconnect with jittered backoff |

## Actors

- **Visitor** — anonymous, identified by a signed cookie/localStorage token scoped to one site.
  No registration. May return days later and see their history.
- **Operator** — authenticated agent of one site, handles up to N concurrent conversations.
- **Site** — the tenant. Every piece of data is scoped by `site_id`; this is a multi-tenant system
  from day one because retrofitting tenancy is the classic portfolio-project failure.

## Core scenarios

1. Visitor opens a page → widget connects → sees history or a greeting.
2. Visitor sends a message → it is persisted, then delivered to the assigned operator, in order.
3. No operator assigned → conversation enters the waiting queue → assignment engine picks a free
   operator respecting their capacity → both sides are notified.
4. Operator replies → visitor receives it in real time, or gets it on next connect if offline.
5. Either side disconnects → presence updates → conversation is released back to the queue after a
   timeout if the operator does not return.

## Explicitly out of scope

Voice/video calls, malware scanning of uploads, bots/LLM auto-replies, billing, CRM integrations,
mobile apps, i18n of the widget. Each would add breadth where the project needs depth.

File attachments **are** in scope (`architecture/file-storage.md`): they are the one "feature" here
that forces a genuinely different scaling shape from everything else in the system.

## Definition of "done" for the whole project

- Runs on a local Kubernetes cluster with a documented one-command setup.
- Survives an instance being killed mid-conversation without losing an acknowledged message.
- Has a load-test report with real p95/throughput numbers against stated targets.
- Swaps RabbitMQ → Kafka and PostgreSQL → MySQL by configuration, with no change in
  `Domain` or `Application`, proven by a green test run against both.
