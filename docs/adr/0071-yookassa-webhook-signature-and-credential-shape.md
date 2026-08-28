# ADR-0071: ЮKassa webhook signature scheme and credential shape

- **Status**: Accepted
- **Date**: 2026-08-28
- **Stage**: 13

## Context

`13-02` builds the first real payment path in AGO Chat: an operator chooses a seat count, is
redirected to ЮKassa's own hosted checkout, and — once ЮKassa's webhook confirms the payment, never
the redirect alone (`roadmap.md`'s explicit wording) — the site's `tier`/`seat_limit` update to match
what was purchased. Two things need to be fixed now, concretely, the same two questions `adr/0024`
settled for AGO Chat's own *outbound* webhooks: the exact signature scheme, and the shape of the
credentials involved.

**Note on this ADR's number.** The backlog item that scoped this work
(`13-02-yookassa-subscription-checkout-and-webhook.md`) names it `adr/0025`. That number was already
claimed by `adr/0025-otlp-direct-to-jaeger-no-collector.md` before this item was implemented — the
backlog's own number went stale between planning and build. This ADR takes the next free number instead
(`0071`, the highest existing ADR at the time of writing being `0070`). Separately noticed while
checking: `adr/0068` and `adr/0069` are referenced by already-shipped `13-07`/`14-02` code comments
(composite operator uniqueness; "one bot per tenant per channel") but no file exists at either path in
`docs/adr/` — a pre-existing gap this ADR did not create and does not fix.

## Decision

### Signature scheme: fixed by ЮKassa, not chosen from alternatives

ЮKassa's own `Webhook-Signature` header carries an HMAC-SHA256 digest over the canonical string
`{HTTP method}|{URL}|{request body}`, keyed by a `webhook_key` obtained from the merchant dashboard's
notification settings. Unlike `adr/0024`, which chose a signature scheme from real alternatives
(timestamped HMAC vs. a bare body signature, symmetric vs. asymmetric), this item has exactly one
scheme to implement correctly — ЮKassa's own, not a novel design. Implemented in
`Ago.Chat.Infrastructure.YooKassa.YooKassaWebhookSignatureVerifier`: hex-decode the presented
signature, recompute the same HMAC-SHA256 over the canonical string, compare in constant time
(`CryptographicOperations.FixedTimeEquals`) — the same "compare a computed digest in constant time"
discipline `ChannelCredential.MatchesWebhookSecret` already established for MAX's inbound secret-header
check, applied here to a computed digest instead of a stored value.

**What is asserted here, not confirmed.** This environment has no live ЮKassa Shop ID/Secret
Key/Webhook Key and no network access to ЮKassa's own API documentation host, so two specific details
of the encoding are this item's own reasoned default rather than a confirmed fact:

- **Hex encoding of the digest.** ЮKassa's documentation states the header carries an HMAC-SHA256
  digest but does not (in any source available to this build) state hex vs. base64. Hex is the default
  here because it is this codebase's own existing convention for an HMAC digest (`adr/0024`'s
  `v1=<hex>`) and the more common of the two for this class of provider API.
- **The exact canonical URL.** `httpContext.Request.GetEncodedUrl()` (scheme + host + path + query, as
  ASP.NET Core reconstructs it after `ForwardedHeadersMiddleware` runs) is what this implementation
  signs against. Whether ЮKassa's own signature is computed over the full URL including query string,
  a relative path only, or with/without a trailing slash is unconfirmed.

Both are the first two things a real ЮKassa test-mode notification would either confirm or correct —
see this item's own report for the honest statement of what remains unverified.

### Credential shape, and why it is *not* `adr/0024`'s ciphertext-column shape

This item needs three ЮKassa values: a Shop ID + Secret Key (used by `Ago.Chat.Api` to *call*
ЮKassa's API and create a checkout-session payment) and a Webhook Key (used to *verify* inbound
notifications). All three are **our own fixed application credentials** — one value per deployment,
never a value stored per-tenant that a dispatcher must later reproduce for many different receivers.
`adr/0024`'s reversible-AES-encryption decision was driven specifically by "the dispatcher must
reproduce this exact secret for many different tenants' endpoints" (`6-05`'s webhook dispatcher,
signing one outbound delivery per tenant webhook with that tenant's own secret) — that reasoning does
not apply here at all, because there is exactly one ЮKassa account this whole deployment ever talks
to, the same way `Auth:Keycloak:Authority` is one fixed value, not a per-tenant one.

Bound as `Billing:YooKassa:ShopId`/`SecretKey`/`WebhookKey`
(`Ago.Chat.Infrastructure.YooKassa.YooKassaOptions`) and `Billing:PricePerSeatRub`/
`Billing:CheckoutReturnUrl` (`Ago.Chat.Application.UseCases.CreateCheckoutSession.BillingOptions`),
read directly from the same `infra-credentials`/`docker/.env` mechanism `Auth:Keycloak:Authority`
already uses — **never written to Postgres, no cipher, no new column.** A reader of both this ADR and
`adr/0024` should see the reasoning, not just conclude "HMAC verification always means a ciphertext
column" from `adr/0024` alone: the deciding fact is *who must reproduce the secret and for how many
receivers*, not whether HMAC is involved.

`.Validate().ValidateOnStart()` on every one of these options classes, matching `adr/0024`'s
`Webhooks:SecretEncryptionKey` precedent: a missing/malformed credential fails host startup, never the
first real checkout attempt.

`Billing:PricePerSeatRub` ships **no default value in code** — deliberately stricter than this
codebase's usual "hardcode a sane unmeasured default" precedent (contrast
`RegisterSiteRateLimitOptions`'s own defaults, explicitly caveated as unmeasured). `CLAUDE.md`: "do not
invent numbers... measure or stay silent" applies with more force to a figure that charges a real card
than to a rate-limit bucket size a wrong guess merely inconveniences a caller with.

### Pricing mechanism: flat per-seat rate, no invented bands

Total charge = `seats_requested × PricePerSeatRub`. No per-band discount pricing (a cheaper effective
rate at Growth volumes) — nothing in the business context given to whoever planned this stage names
one, and a flat linear rate is the simplest mechanism consistent with "priced by operator-seat count."
The given tier bands overlap at the boundary as literally stated ("Starter (2-10 seats), Growth
(10-100 seats)"); this item reads that as **Starter = 2-9, Growth = 10-100** (non-overlapping), the
natural non-overlapping reading of a loosely-worded band list (`Ago.Chat.Domain.SubscriptionTierBands`).

### Idempotency ledger: HTTP-triggered, not the broker's `inbox` table

`messaging.md`'s "every consumer records `message_id` in the `inbox` table inside the same
transaction as its work" is the exact discipline this webhook handler needs — realized here as a plain
transactional insert-and-catch-unique-violation (`Ago.Chat.Infrastructure.Postgres.BillingWebhookApplier`),
not a broker consumer, because ЮKassa calls `Ago.Chat.Api` directly over HTTP; there is no RabbitMQ hop
for an inbound third-party webhook, and no `EventEnvelope.MessageId` to key on.

The platform's generic `inbox` table (`Ago.Platform.Abstractions.IInboxChecker`) is keyed by
`(message_id, consumer)` — one row per logical *consumer type*. `6-05`'s own outbound ledger adapted
that to `(message_id, endpoint_id)` because many endpoints can receive one event. This item's inbound
case is the mirror image again: exactly one "sender" (ЮKassa itself), so the natural composite key is
**`(yookassa_payment_id, event_type)`** — which *event* fired for a given payment
(`payment.succeeded`, `payment.waiting_for_capture`, `payment.canceled` can all arrive for the same
payment id), not which endpoint received it. A new table, `billing_webhook_events`, holds this ledger —
its own unique index on `(yookassa_payment_id, event_type)` is both the idempotency check and, as a
side effect, an audit trail of every event this deployment has seen, the identical dual-purpose shape
`WebhookDelivery`'s own `(endpoint_id, message_id)` index already established for the outbound case.

### Webhook receiver lives in `Ago.Chat.Api`, not `Ago.Chat.Webhooks`

`adr/0013`'s three-host split exists to isolate *our own* slow outbound calls to a shop's tenants from
the rest of the system ("expected to be slow and failing; must not affect the others"). This is the
opposite shape: an *inbound* request where ЮKassa is the one with latency to manage on its own side,
and this system's only obligation is to ack fast and never block — exactly what an ordinary
`Ago.Chat.Api` endpoint already does for every other inbound request. `14-02`'s MAX webhook receiver
already established this same placement decision for the identical reason (`MaxWebhookEndpoints`'s own
remarks); this item is the second instance of that pattern, not a new one.

### One transaction: verify, ledger, terminal state, site

`Ago.Chat.Api`'s endpoint verifies the signature and rejects (`401`, no ledger entry, `sites` never
touched) before `BillingWebhookApplier` is ever called. Inside `BillingWebhookApplier.ApplyAsync`, one
Postgres transaction: insert the ledger row (a unique-violation means a duplicate — roll back, return
`Duplicate`, still ack `200`); on a new `payment.succeeded`, mark the pending `BillingSubscription`
row `Succeeded`, store `payment_method_id`, and — inside the same transaction — call
`Site.ActivateSubscription`, staging the resulting `SiteSettingsChanged` outbox row on the same
`DbContext` before committing. A `payment.canceled` marks the row `Failed` and touches nothing on
`Site` — `sites.tier`/`seat_limit` were never written by the checkout-session-creation call in the
first place, so "leave them alone" requires no special-casing.

## Consequences

- Ago.Chat's config surface gains four new required keys (`Billing:YooKassa:ShopId`/`SecretKey`/
  `WebhookKey`, `Billing:PricePerSeatRub`) and one required non-secret one
  (`Billing:CheckoutReturnUrl`) — every serving host that loads `ChatModule` refuses to start without
  all five.
- `13-03`'s recurring-charge job has a real `payment_method_id` to charge against
  (`BillingSubscription.PaymentMethodId`, this item's first and only writer) — this item declares the
  column but never uses it for a second charge.
- The exact byte encoding of ЮKassa's signature header and the exact canonical-URL construction are
  unverified against a real notification — the first thing a real Shop ID/Webhook Key would either
  confirm or require a one-line correction to (`YooKassaWebhookSignatureVerifier`'s own remarks name
  precisely which two assumptions).
- `data-model.md` gains `billing_subscriptions` and `billing_webhook_events`; `messaging.md` gains a
  note that this is the first inbound, HTTP-triggered (not broker-consumed) idempotency ledger in the
  codebase.

## Alternatives considered

- **A per-tenant reversible ciphertext column for the webhook key, mirroring `adr/0024` literally** —
  rejected: there is no per-tenant anything here. One ЮKassa account, one Shop ID, one Secret Key, one
  Webhook Key, for the whole deployment. A ciphertext column would be protecting a value that is
  already ordinary deployment configuration, the same category `Auth:Keycloak:Authority` is in.
- **Reusing the platform's generic `inbox` table, keyed by `(message_id, consumer)`** — rejected: there
  is no `EventEnvelope.MessageId` on an inbound third-party webhook (ЮKassa's own `payment.id` plus
  `event` type is the only natural key available), and "consumer" has no meaning for an HTTP endpoint
  that is not a broker subscriber.
- **Placing the webhook receiver in `Ago.Chat.Webhooks`** — rejected for the reason stated above
  (`adr/0013`'s bulkhead protects *outbound* latency to tenants; this is an inbound, request-shaped
  call with bounded local work, the same category `14-02`'s MAX receiver already established).
- **Per-band discount pricing** — named and rejected above as a deliberate simplification, not a
  silently dropped feature: nothing in the given business context names a discount curve, and inventing
  one would be exactly the kind of unmeasured figure `CLAUDE.md` forbids presenting as decided.
