# Vision

## Platform and products

**AGO Platform** is the reusable substrate: hosting, realtime transport, messaging, persistence,
caching, object storage, observability. **AGO Chat** is the first product built on it. **AGO
Calendar** — a booking/scheduling system a shop uses to let customers reserve an appointment with one
of its workers — is the planned second product (`roadmap.md` Stage 20). Unlike a purely illustrative
"second product" would be, it is a real product decision, not chosen for the sake of the proof: a
shop that already runs AGO Chat plausibly also wants online booking, and the two products share
nothing except the platform underneath and, for a given shop, the same login. It still carries the
architectural role the platform's design has always needed a second product to test: every platform
decision must be defensible without knowing anything about chat, and a reviewer can ask whether the
platform could host a second, structurally different product unchanged - the answer has to be yes,
in code, not just in this paragraph.

AGO Calendar's shape, briefly: a **Tenant** configures **Calendars**, **Workers** (the bookable
resource - e.g. a barber), **Services**, and each worker's recurring **working hours**; an
**Operator** - created by the tenant, and *not* the same entity as AGO Chat's own Operator even
though the two roles look similar (`adr/0027` argues this in full) - works the day-to-day booking
queue: confirming or rejecting pending bookings and building up a **Customer** lead card over time,
keyed by phone number rather than an account. A booking looks instantly confirmed to the customer but
is not, internally, until an operator confirms it or a deadline passes unactioned - the same
atomic-claim discipline `concurrency.md` already uses for operator capacity, applied to a calendar
slot instead of a conversation.

### "AGO Chat" names two things, and the difference matters when selling

Recorded 2026-08-26, after the author — this system's own architect — had to stop and work out whether
one of his product combinations removed AGO Chat or not. If the person who designed it has to check,
the vocabulary is doing damage.

- **The conversation substrate**: conversations, operators, messages, channel identities, the
  assignment queue. It is present in **every** combination that has been described, without exception.
- **The website-widget channel**: one entry point among several, and optional. `14-01` is what made it
  one among several rather than the only one.

A shop can buy "AGO Inbox and AGO Calendar, no AGO Chat" — meaning no widget on their site, customers
reaching them through Telegram instead. **Architecturally nothing has been removed**: the conversation
machinery is doing the work, one channel is simply not deployed. Said without this distinction, a
statement about the price list reads as a statement about the architecture, and the two lead to very
different conclusions about where things belong.

This is a naming and packaging observation, not an architectural one. It is deliberately **not** an
argument for renaming `Ago.Chat.*`, whose contents are coherent, nor for a new deployable — the
boundary review tested both and rejected them (`reviews/2026-08-26-platform-boundary.md`). It is an
argument for saying which of the two is meant, in the places customers and reviewers read.

**AGO Inbox** - expanding AGO Chat's own incoming channels beyond the embedded widget (SMS, MAX,
Telegram, WhatsApp), plus a tenant-toggleable offline auto-reply and unattended booking through those
channels (`roadmap.md` Stage 14) - is **not a third product**. `adr/0027` makes the direct argument:
its channel-routing target is an incoming message that must reach an existing AGO Chat `Operator`,
the same entity `SendVisitorMessage`/assignment/the console already work with today, not a new one.
It is AGO Chat's own channel surface growing, staying inside `Ago.Chat.*`, the same way file
attachments (Stage 5) grew the product without becoming a separate one.

The platform/product split is not decoration. It is the thing that turns "a chat app" into "a
platform with products on it", and it is what a reviewer will probe: ask whether the platform could
host a second, unrelated product unchanged, and the answer has to be yes, in code.

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

Voice/video calls, malware scanning of uploads, CRM integrations, mobile apps, i18n of the widget.
Each would add breadth where the project needs depth.

Two items originally listed here no longer belong: **billing** is now Stage 13 (a self-service
product needs a way to get paid), and **bots/LLM auto-replies** are now AGO Inbox's own
tenant-toggleable, off-by-default offline auto-reply (Stage 14) - both became real roadmap work
rather than staying deliberately out of scope, and this list is corrected rather than left to
contradict the roadmap it sits next to.

**The auto-reply half of that correction shipped in `14-04`**, and shipped narrower than the sentence
above might suggest, so the boundary is worth stating exactly. What exists is the **scripted** variant:
a per-site toggle (off by default), a default reply, and up to twenty keyword rules, fired only when
nobody at that site is online and nothing has picked the conversation up (`adr/0066`). The
**LLM-backed** variant is not built and is not out of scope either - it is named future work, blocked
on a real, cited per-message provider cost rather than on appetite, because `CLAUDE.md` forbids
inventing one. So "bots/LLM auto-replies" is now three things, not two: one shipped, one deliberately
deferred with a stated trigger, and nothing here that is permanently excluded.

File attachments **are** in scope (`architecture/file-storage.md`): they are the one "feature" here
that forces a genuinely different scaling shape from everything else in the system.

## Definition of "done" for the whole project

- Runs on a local Kubernetes cluster with a documented one-command setup.
- Survives an instance being killed mid-conversation without losing an acknowledged message.
- Has a load-test report with real p95/throughput numbers against stated targets.
- Swaps RabbitMQ → Kafka and PostgreSQL → MySQL by configuration, with no change in
  `Domain` or `Application`, proven by a green test run against both.
