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
| Outbound channel provider APIs (MAX, SMS, later Telegram/WhatsApp) | Provider outage, slow or hanging send, terminal refusal of one recipient | Timeout, retry with backoff, **circuit breaker per channel**, **bulkhead per channel** — see the note below |
| Inbound traffic | Overload, abusive tenant | Rate limiting per tenant, bounded channels, load shedding, `429` with `Retry-After` |

### Channel providers: same patterns, a different key (`14-01`, `adr/0055`)

The row above uses no new concept — it is `Ago.Platform.Resilience`'s existing four patterns applied to
one more boundary, wired once in `Ago.Chat.Module.Channels.ChannelResiliencePipelines` and applied by
composition (`ResilientInboundChannelAdapter` decorates any `IInboundChannelAdapter`), so a concrete
adapter is written as if the provider always answers and never references Polly. Two things about it
are worth stating, because both differ from the webhook dispatcher directly above:

- **Keyed per channel, not per tenant.** A webhook endpoint is chosen by each tenant, so one shop's
  dead CRM is one shop's problem and per-site keys match the blast radius. A channel provider is chosen
  by *us* and shared by every tenant on it: per-tenant keys would give N breakers all observing one
  outage, each needing its own `MinimumThroughput` before reacting — slower to open and no better
  isolated. An SMS aggregator's outage must not stop MAX replies; that is what the per-channel key buys.
- **The port distinguishes terminal from transient, and the distinction is what makes retry safe.** A
  provider refusing one recipient (unknown number, blocked chat) comes back as a *return value*, so it
  is never retried — retrying it would never help. A timeout, 5xx or dropped connection is *thrown*,
  because throwing is what the pipeline acts on. Retry is safe because the outbound message carries the
  system's own `MessageId` as an idempotency key for the receiver — the same rule this page already
  states for webhooks, and the reason "retrying non-idempotent operations blindly" stays on the
  do-not-use list below.

The mechanism is proven against a stub provider that hangs, throws and refuses
(`ResilientInboundChannelAdapterTests`), including that the breaker opens for one channel and leaves
another untouched. `14-02` is the first item to run it against a real HTTP boundary rather than a stub
(`Ago.Chat.FakeMax`, a real separate process, mirroring `Ago.Chat.FakeCrm`'s own technique) — the
breaker opens on real connection-refused errors when the process is stopped, and a different channel's
pipeline is provably unaffected (`MaxChannelAdapterResilienceTests`). The terminal/transient split for
MAX specifically (400/401/403/404 terminal, everything else transient) is a reasoned default, not yet
confirmed against real provider error responses — `14-02`'s own note on this, pending a live-verified
message exchange. The thresholds otherwise remain starting points modelled on the dispatcher's, not
measured numbers.

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
