# ADR-0190: ЮKassa webhooks are verified by re-query and IP allowlist, not a signature

- **Status**: Accepted
- **Date**: 2026-09-29
- **Stage**: 13

## Context

`adr/0071` fixed how AGO Chat verifies ЮKassa's inbound payment notifications: it assumed ЮKassa
signs each notification with an HMAC-SHA256 digest in a `Webhook-Signature` header, keyed by a
`webhook_key` from the merchant dashboard, and verified that digest over the canonical string
`{method}|{URL}|{body}`. That ADR was explicit that the scheme was **asserted, not confirmed** — the
build had no live ЮKassa credentials and no network access to ЮKassa's documentation host, so both the
digest encoding and the canonical-URL construction were reasoned defaults awaiting a real test-mode
notification to confirm or correct (`YooKassaWebhookSignatureVerifier`'s own remarks, and `0071`'s
own Consequences, named the two unverified assumptions).

Checked against ЮKassa's official developer documentation (`developers/using-api/webhooks`,
2026-09-29), the assumption was wrong in a way no encoding tweak fixes: **ЮKassa does not sign its
console-configured HTTP notifications at all.** There is no `Webhook-Signature` header, no shared
`webhook_key`, and therefore no signing secret to obtain, hold, or rotate. Our code demanded a header
ЮKassa never sends and rejected (`401`) anything without it, so it would have rejected *every* real
notification — a payment would confirm at ЮKassa and the site would never leave the free tier.

ЮKassa's own documented verification is instead two things:

1. **Re-query the payment object from the Payments API by its id, and act on that authoritative
   `status`/`paid`** — never trust the status the notification body carries.
2. **An IP allowlist**: notifications originate only from ЮKassa's published networks —
   `185.71.76.0/27`, `185.71.77.0/27`, `77.75.153.0/25`, `77.75.156.11`, `77.75.156.35`,
   `77.75.154.128/25`, `2a02:5180::/32`.

## Decision

Replace the signature scheme entirely with re-query plus IP allowlist. This supersedes `adr/0071`'s
signature decision; the credential-shape and idempotency-ledger decisions in `0071` stand unchanged,
minus the one credential the signature required.

### Re-query is the guarantee, and it lives behind the payments-client port

`ProcessYooKassaWebhookHandler` takes only the payment id from the notification — and only as a lookup
key, never as a fact. It calls a new `IYooKassaPaymentsClient.GetPaymentAsync(paymentId)` (a
provider-neutral Application port; `Ago.Chat.Infrastructure.YooKassa.YooKassaPaymentsApiClient`
implements it as `GET /payments/{id}` with the same Shop ID + Secret Key Basic auth the create/charge
calls already use), and drives every decision from ЮKassa's authoritative reply: only
`status = succeeded` **and** `paid = true` grants; `canceled` fails the pending row; any other status
is ignored; the saved `payment_method_id` is read from the re-query, never from the body. A payment id
ЮKassa has no record of comes back `NotFound` and grants nothing.

The re-query belongs in the Application handler behind the payments-client port, not in
`IBillingWebhookApplier`. The applier is a persistence port whose one job is the single database
transaction (ledger, then subscription plus site); it must stay a pure database concern. The re-query
is an outbound third-party call and belongs behind `IYooKassaPaymentsClient`. The handler orchestrates
the two ports in order — fetch through A, persist the authoritative outcome through B — which is the
dependency rule applied literally: folding an HTTP call into the Postgres adapter would make a database
adapter depend on the payments client and mix network I/O into a transaction boundary.

The tie to "a payment we actually issued" needs no metadata round-trip: the applier resolves the one
`billing_subscriptions` (or `download_overage_charges`) row whose stored `YooKassaPaymentId` equals the
re-queried id — a value this deployment saved from ЮKassa's own authoritative create-payment reply at
checkout, never a value any caller supplies. A re-queried payment whose id matches no row of ours
resolves to `SubscriptionNotFound` and grants nothing. (Checkout attaches no ЮKassa `metadata` today,
and adding some would be redundant with this id match, which is at least as strong.)

### IP allowlist is defense-in-depth, not the guarantee

`Ago.Chat.Api`'s webhook endpoint rejects (`403`) any request whose source IP is outside ЮKassa's
published networks, before the body is read (`YooKassaWebhookSourceGuard`). The real client IP is the
one `Program.cs`'s already-configured `UseForwardedHeaders` resolved from the NGINX Gateway's
right-most trusted `X-Forwarded-For` hop (`CompositionRoot`'s `ForwardedHeadersOptions`, trusting the
cluster's own Gateway network) — the same resolved client IP every per-IP rate-limit bucket in this
host already trusts. The allowlist raises the bar (an attacker must also spoof a source IP inside
ЮKassa's ranges past the gateway) but is explicitly not the guarantee: a forger reaching the endpoint
from an allowlisted IP still cannot make ЮKassa's own API report a payment as succeeded that is not.
If IP resolution were ever unreliable behind the proxy, the re-query still holds the line.

### The signature machinery is removed

`IYooKassaWebhookSignatureVerifier` and `YooKassaWebhookSignatureVerifier` are deleted, the
`Webhook-Signature` check and canonical-URL reconstruction leave the endpoint, and `WebhookKey` leaves
`YooKassaOptions` and its `.Validate().ValidateOnStart()` in `ChatModule`. `ShopId`/`SecretKey`/
`BaseUrl` remain — the create/charge calls and now the re-query all use them.

## Consequences

- There is no webhook signing secret to hold or rotate — one fewer credential on every serving host,
  and the removed `Billing:YooKassa:WebhookKey` startup requirement (which `0071` had made mandatory)
  no longer blocks host startup. Deploy manifests that still set `Billing__YooKassa__WebhookKey` bind
  to nothing and are harmless, but should be cleaned up.
- Every webhook now costs one extra outbound ЮKassa API call (the re-query) before it applies. This is
  a low-frequency, human-payment-driven path, and the call runs unwrapped by resilience machinery for
  the same reason the checkout create call is (one inbound request that must ack fast; a transient
  failure surfaces as `5xx` and ЮKassa's own webhook retry re-drives the whole notification).
- A transient re-query failure (401/403/429/5xx, network fault) throws rather than being read as "no
  such payment", so a misconfigured credential or an outage surfaces and is retried, never silently
  drops a real grant. Only a genuine `404` is treated as "not ours, ignore".
- The IP allowlist depends on `X-Forwarded-For` being resolved correctly at the edge; a future edge
  change that altered the trusted-hop configuration would silently weaken this hardening layer (not the
  guarantee). The published ЮKassa ranges are hard-coded and would need a code change if ЮKassa
  published new ones.
- `0071`'s two unverified assumptions (digest encoding, canonical URL) are now moot — there is no
  signature to encode. What still awaits a real ЮKassa test-mode account is confirmation of the
  Payments API's exact `GET /payments/{id}` response fields (`status`, `paid`, `payment_method.id`),
  which this ADR builds on from the publicly documented shape.

## Alternatives considered

- **Fix the signature encoding (hex vs base64, URL construction) instead** — impossible: there is no
  signature to fix. ЮKassa does not sign console-configured notifications, so no encoding change makes
  the old scheme accept a real notification.
- **Trust the notification body's `status`/`event` after the IP check** — rejected: the IP allowlist is
  spoofable in principle and is hardening, not proof. Only ЮKassa's own API answer for a given payment
  id is authoritative, which is exactly why the documented mechanism is re-query.
- **Attach a `siteId`/subscription id as ЮKassa `metadata` at checkout and verify it on the webhook** —
  rejected as redundant: the payment id already ties the re-queried payment to the one row we created
  it for, and that id came from ЮKassa's authoritative create reply, so a metadata cross-check adds a
  round-trip without adding a stronger tie.
- **Put the re-query inside `BillingWebhookApplier`** — rejected: it would make a persistence adapter
  depend on the payments client and put an outbound HTTP call inside a database transaction boundary.
  The handler orchestrating two ports keeps each port to one concern.
