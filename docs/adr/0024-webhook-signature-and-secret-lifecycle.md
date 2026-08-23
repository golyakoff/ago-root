# ADR-0024: Webhook signature scheme and secret lifecycle

- **Status**: Accepted
- **Date**: 2026-08-23
- **Stage**: 6

## Context

`6-03` ships the registration API and delivery-history backend for tenant webhook endpoints — the
data a future `6-05` dispatcher (`adr/0013`) will read from and write to. Two things need to be fixed
now, concretely, rather than left as the "HMAC-signed" assumption `authorization.md`'s "Webhook/API
integrations" row already states as fact: the exact signature scheme, and how the shared secret is
generated, shown, and stored.

`repositories.md`'s "everything is public" rule matters here more than anywhere else in this project:
a webhook secret is the first genuinely sensitive, non-public value this system stores server-side
(unlike a site's public key or an operator id, both fine to appear in a fixture). How it is protected
at rest and in every response after the first has to be stated, not assumed.

## Decision

**Signature scheme**: HMAC-SHA256 over the raw request body concatenated with a timestamp, in the
Stripe/GitHub-style header `X-Ago-Signature: t=<unix>,v1=<hex>`. A well-understood default, not a
novel design — the timestamp is what makes a captured request-and-signature pair unreplayable after a
short window (the receiver rejects anything outside its own tolerance, e.g. 5 minutes), which a bare
body signature cannot do on its own.

**Secret generation**: 256 bits from a CSPRNG (`RandomNumberGenerator`), base64url-encoded and
prefixed `whsec_` for a recognizable, copy-pasteable value (`IWebhookSecretGenerator`,
`Ago.Chat.Infrastructure.Postgres.WebhookSecretGenerator`). Shown exactly once, in
`POST /api/v1/sites/{siteId}/webhooks`'s response body, and never again by any subsequent read
(`GET` never includes it — `WebhookEndpointDto` has no field that could carry one).

**Secret storage: reversible encryption (AES-256-GCM), not a one-way hash.** This is a deliberate
correction of the "hash it like a password" framing: a password is only ever *verified* by the party
that stores it (compare an incoming attempt against the stored hash, never reproduce the original). A
webhook secret is the opposite — *this system* is the signer of every future delivery, not the
verifier of an incoming one. `6-05`'s dispatcher must reproduce the exact secret bytes on every
outbound call to compute a valid HMAC-SHA256 signature; a one-way hash cannot support that, full stop.
Storing only a hash would make delivery cryptographically impossible from the very data model this
item ships.

So the column is `secret_ciphertext` (`bytea`), not `secret_hash` — named for what it actually holds,
a deliberate departure from this backlog item's own literal schema note, made explicit here rather
than silently labeling a ciphertext column "hash". `IWebhookSecretCipher` (Application port) is
implemented by `WebhookSecretCipher`: AES-256-GCM (authenticated — a tampered ciphertext throws rather
than decrypting to garbage that would silently sign with the wrong key), key from
`Webhooks:SecretEncryptionKey` (base64, 32 bytes), sourced the same `infra-credentials`
(`docker/.env`, gitignored) way `Auth:SigningKey` already is. Deliberately **no random-per-process
fallback** the way the JWT signing key has: a lost JWT key only invalidates outstanding tokens
(visible, recoverable); a lost encryption key would make every already-registered webhook secret
permanently unrecoverable (silent, unrecoverable). `ChatModule` binds it with `.Validate(...)
.ValidateOnStart()` so a missing/malformed key fails host startup, not the first registration attempt.

256 bits of CSPRNG entropy is also what settles a secondary question the backlog raised but did not
force an answer to: whether the protection at rest needs to be *slow* (Argon2/bcrypt/PBKDF2-shaped, to
resist brute force against a low-entropy human-chosen value). It does not — that reasoning defends a
*password*, something a human picked from a small effective space. This secret is never chosen by a
human; brute-forcing 2^256 is infeasible regardless of how fast or slow the cipher protecting it is.
AES-256-GCM (BCL, no new package) is the right primitive for "reversible, authenticated, keyed by
something we already control" — not because speed doesn't matter, but because entropy already won
this fight before the cipher gets involved.

## Consequences

- `6-05`'s dispatcher has a real key to sign with (`IWebhookSecretCipher.Decrypt`, its first caller —
  this item declares but never calls it, since nothing it ships reads a secret back).
- A new operational secret exists that did not before: `Webhooks:SecretEncryptionKey` must be
  provisioned and backed up as carefully as any other production credential — losing it is a permanent,
  silent loss of every registered webhook's ability to be verified by its receiver, not a recoverable
  event like a rotated JWT key.
- The schema deliberately does not match this backlog item's own literal column name
  (`secret_hash` → `secret_ciphertext`); anyone reading the migration sees what is actually stored.
- SSRF protection at registration time is real but partial by design: it catches every IP-literal and
  `localhost` case synchronously, with no live network call, but cannot catch a DNS hostname that only
  resolves to a private address at request time (a TOCTOU gap no registration-time check can close).
  `6-05`'s dispatcher must re-validate the resolved address immediately before connecting — this ADR
  flags that obligation for that item's planning session rather than leaving it to be rediscovered.

## Alternatives considered

- **Hash the secret (SHA-256/Argon2/bcrypt), as the backlog's own default suggestion framed it** —
  rejected: cryptographically incompatible with the HMAC dispatcher this data model exists to feed.
  A hash only works when the party storing it never needs to reproduce the original, which is exactly
  backwards from what a webhook signer needs.
- **Plaintext storage** — the obviously worse alternative, named for completeness: any read access to
  the database (a backup, a support query, a future bug) would leak every tenant's signing key at once.
- **Asymmetric signing (e.g. Ed25519) instead of HMAC** — would remove the need to store a
  reproducible secret at all (the tenant verifies with a public key). Rejected: heavier for the
  receiving side to implement correctly than the well-known Stripe/GitHub HMAC convention this ADR
  already commits to, and this project's own instruction was to "state it and move on rather than
  surveying alternatives at length" for the signature scheme itself.
