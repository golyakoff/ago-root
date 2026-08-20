# Resilience

Resilience patterns belong on the boundaries with things that can fail independently of us. Applying
them inside our own process is cargo cult; omitting them at a third-party HTTP endpoint is negligence.

## Where each boundary is, and what protects it

| Boundary | Failure mode | Patterns applied |
|---|---|---|
| PostgreSQL | Unavailable, pool exhausted, slow query | Timeout, bounded pool, retry only on transient errors, **no** circuit breaker (there is no fallback — we reject writes, `realtime.md`) |
| RabbitMQ / Kafka | Broker down, publish timeout, consumer backlog | Timeout, retry with jittered backoff, publisher confirms, outbox accumulates while it is down |
| Redis | Down, slow, evicting | Short timeout, circuit breaker, **fallback to cache miss** — never surface an error (`adr/0009`) |
| S3 / MinIO | Down, slow presign, slow HEAD | Timeout, retry, circuit breaker on the presign path; uploads themselves never touch our process |
| Outbound webhooks to a shop's CRM | Slow (30s hangs), 5xx, disappeared endpoint, one tenant dragging everyone down | Timeout, retry with backoff, **circuit breaker per endpoint**, **bulkhead**, DLQ, per-tenant concurrency cap |
| Inbound traffic | Overload, abusive tenant | Rate limiting per tenant, bounded channels, load shedding, `429` with `Retry-After` |

## The webhook dispatcher: why it is a separate deployable

Outbound webhooks are the only place in this system where we call something we do not control and
cannot fix. A CRM that answers in 30 seconds will, if dispatched from the Worker, occupy threads,
connections and memory belonging to the message pipeline — one slow third party degrading unrelated
work. That is the textbook case for a **bulkhead**, and the honest form of it here is process
isolation: `Ago.Chat.Webhooks` scales, fails and restarts on its own.

This is also the deliberate limit of our splitting. Three deployables exist because they have three
different failure and load profiles (`adr/0013`), not because splitting is fashionable.

Inside the dispatcher:

- **Per-endpoint circuit breaker.** Consecutive failures open the breaker for that endpoint only.
  While open, deliveries for it are parked, not retried in a hot loop. Half-open probes with a single
  request decide recovery.
- **Per-tenant concurrency cap**, so one shop's dead endpoint cannot consume the whole worker pool.
- **Timeouts at every layer**: connect, response headers, total. A missing total timeout is how "we
  have retries" becomes "we have a queue of hung requests".
- **Retry with exponential backoff and jitter**, bounded attempts, then dead-letter with the full
  request/response context.
- **Idempotency for the receiver**: every delivery carries a stable `MessageId` and a signature, so a
  retried delivery is safe on their side too.
- **Delivery attempts are recorded** and visible to the tenant. A webhook system without a delivery
  log is unsupportable.

## Patterns we deliberately do not use

- **Retrying non-idempotent operations blindly.** Retry is safe here because delivery carries an
  idempotency key; without one, retry is a duplication mechanism.
- **Circuit breakers on PostgreSQL.** There is no degraded mode for the source of truth — failing
  fast and honestly is better than pretending.
- **A service mesh.** It would provide retries and breakers at the network layer, and hide the exact
  mechanisms this project exists to demonstrate. Worth naming in the README as the production
  alternative.
- **Fallback content.** There is nothing sensible to return in place of a real message.

## How this is proven

Not by asserting the library is configured. Stage 7 tests each one: a fake CRM that hangs, one that
5xxs, one that disappears; Redis stopped mid-load; the broker stopped and restarted. The assertion is
always about the *rest of the system* staying within its latency targets while the dependency is
broken — that is what a bulkhead means, and it is measurable.
