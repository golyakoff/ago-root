# Webhook endpoints: self-service registration, signed secrets, tenant-visible delivery history

- **Stage**: 6
- **Status**: done
- **Depends on**: nothing new architecturally (`adr/0016`'s RBAC already exists) - `6-05`'s dispatcher
  is the consumer of what this item ships, not a prerequisite for it

## Goal

A tenant's operator can register a webhook endpoint via a real API, get back a secret shown exactly
once, and later see the delivery history for it - the actual backend a future self-service console
screen would call, built now with no UI in front of it yet. Chosen deliberately: this project is
headed toward real commercial use (not portfolio-only), and the registration API *is* the reusable
part - a later UI is thin frontend work on top of what this item ships, while a seed-script shortcut
here would be thrown away entirely once self-service actually matters.

## Context to read first

`adr/0013`'s Decision (`Ago.Chat.Webhooks` deployable, per-endpoint breaker/bulkhead) and
`architecture/resilience.md`'s webhook boundary row - this item does not build the dispatcher
(`6-05`'s job), only what a dispatcher will read from and write delivery records to.
`architecture/authorization.md`'s "Webhook/API integrations" row - "deliveries to a tenant's endpoint
are HMAC-signed... so *they* can verify *us*" is already assumed as fact there; this item's own ADR
makes that concrete (algorithm, header names, secret lifecycle) rather than deciding from nothing.
`adr/0016` for the RBAC shape a new permission slots into. `api-design.md`'s RFC 7807 error
convention and keyset-pagination rule (delivery history is a list, `AttachmentEndpoints`-style
`Result<T>`-to-`ToProblem` mapping already established). `repositories.md`'s "everything is public"
rule - a webhook secret is the first genuinely sensitive, non-public value this project stores
server-side (unlike a site's public key or an operator id); state explicitly how it is protected at
rest and in every response after the first.

## Scope

- **ADR**: HMAC-SHA256 over the raw request body plus a timestamp (Stripe/GitHub-style
  `X-Ago-Signature: t=<unix>,v1=<hex>`, timestamp included specifically to make a captured
  request-and-signature pair unreplayable after a short window) - a well-understood default, not a
  novel design; state it and move on rather than surveying alternatives at length. Secret generation
  (cryptographically random, shown once on create, never returned by any subsequent read) and at-rest
  storage (hashed the way a password would be, or encrypted - state which and why; hashing means we
  can never re-display it either, matching "shown once" exactly, so hashing is the tighter default).
- **Data model**: `webhook_endpoints` (`id` uuid v7, `site_id`, `url`, `secret_hash`, `active`,
  `created_at`) and `webhook_deliveries` (`id`, `endpoint_id`, `event_type`, `payload` jsonb,
  `attempt`, `status` (`pending|delivered|failed|dead_lettered`), `response_status?`,
  `response_snippet?` (bounded length - never store an unbounded response body), `created_at`,
  `delivered_at?`) - additive migration, `db-migration` skill, `site_id`-scoped like everything else
  (`data-model.md`).
- **Registration API**: `POST /api/v1/sites/{siteId}/webhooks` (create, returns the secret once),
  `GET /api/v1/sites/{siteId}/webhooks` (list, secret never included), `DELETE .../{webhookId}`
  (revoke) - operator-authenticated, gated by a new `webhook:manage` permission (`adr/0016`'s pattern,
  same shape `6-02`'s `conversation:close` question resolves).
- **Delivery history API**: `GET /api/v1/sites/{siteId}/webhooks/{webhookId}/deliveries` - keyset
  paginated (`api-design.md`), gated by `webhook:manage` too (reading delivery history is not more
  sensitive than managing the endpoint that produces it).
- URL validation: `https://` only (an HMAC-signed payload over plain HTTP defeats its own purpose),
  reject a URL pointing at a private/loopback address (SSRF: a malicious tenant registering
  `http://169.254.169.254/...` or `http://localhost:5432` must not make this system's own dispatcher
  probe its own internal network) - a real security requirement, not a nice-to-have, since this
  system's IP is what makes the outbound request.

## Out of scope

- Actually sending anything to a registered endpoint - `6-05`. This item's own tests write
  `webhook_deliveries` rows directly (repository-level), the same way `GetAttachmentDownloadUrlHandlerTests`
  never needed a real upload to test the download side.
- Editing an existing endpoint's URL - revoke-and-recreate only, for now; matches how a real secret
  rotation should work anyway (you get a new secret with a new endpoint, not a silent URL swap under
  an old one).
- A UI for any of this - explicitly deferred per the Goal above, not forgotten.

## Done when

- [x] `adr/0024` written and accepted: signature scheme, secret lifecycle, hashing-vs-encrypting
      decision, stated with reasoning.
- [x] `Stage6AddWebhookEndpointsAndDeliveries` migration, additive and reversible, verified against a
      real Postgres from scratch (`db-migration` skill's own bar).
- [x] Full CRUD-minus-update path unit- and integration-tested: create returns a secret exactly once
      and a subsequent `GET` never includes it; delete actually stops future deliveries (`6-05` will
      prove the *delivery* side of that, this item proves the *data* side - `active` flips to false
      and stays queryable for its own delivery history).
- [x] SSRF rejection proven: a loopback/private-range URL is rejected at registration time, not
      merely "would fail later" - a unit test against the validator, not a live network probe.
- [x] `RequireOperatorIdentity`/`webhook:manage` enforced - an operator without the permission gets a
      clean 403, matching every other RBAC-gated route's own proof shape.

Shipped in `6-03`: this file's own scope text (above) recommended hashing the secret as "the tighter
default" - `adr/0024` overrides that. The dispatcher (`6-05`) must reproduce the exact secret to sign
outbound deliveries, which a one-way hash structurally cannot support; the secret is stored as
AES-256-GCM ciphertext (column `secret_ciphertext`, not `secret_hash`) instead. See `adr/0024` for the
full reasoning.

## Open questions

None left unresolved by this file - the signature scheme and secret-storage approach are this item's
own ADR to write, not a blocking question for the author; both have a clear, defensible default
(HMAC-SHA256, hash-not-encrypt) consistent with how the rest of this project treats similar decisions
(argon2-shaped reasoning, even though there is no password here to hash).
