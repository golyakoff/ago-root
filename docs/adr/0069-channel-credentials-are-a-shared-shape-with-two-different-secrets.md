# ADR-0069: channel credentials are a shared shape, with two different secrets held two different ways

- **Status**: Accepted
- **Date**: 2026-08-27
- **Stage**: 14

## Context

`14-02` (AGO Inbox: MAX channel adapter) decided, ahead of any code, that a MAX bot is registered by the
shop itself and its token handed to AGO — one bot per tenant, chosen because it makes routing trivial
(token → site) and because it is the shape every comparable integration uses. That decision brings a
consequence `14-01` never had to consider: **AGO now stores a credential that belongs to somebody else.**
A bot token is not AGO's secret; it is the shop's, and it grants full control of that bot. A leaked
tenant token is not "access to data" — it is the ability to message that shop's customers *as the shop*.
That is a worse leak than most of what this system holds, and it is the first time the question "how
does AGO hold a credential belonging to a tenant" has come up. This ADR is that decision, for MAX first
and for every future channel credential (`14-03`'s SMS aggregator key, `14-05`'s candidates) by
construction.

Four things had to be decided, all named in `14-02`'s own backlog note before this ADR was written:

1. **A column is not storage.** The token needs encryption at rest, and the encryption key is then
   itself a rotatable secret that belongs in `17-03`'s inventory — naming which key, and how it rotates,
   rather than deferring it to whoever writes the migration.
2. **Revocation and erasure.** Tenant offboarding and `16-02`'s erasure must be able to remove the
   credential, not leave it in a table "for safety's sake."
3. **The console never shows it back.** Entered once, replaceable, never readable — the ordinary
   treatment of a third-party API key, and a deliberately different treatment from `6-03`'s webhook
   secret, which the tenant *does* see once (that secret is AGO's own value, generated for the tenant's
   benefit; a bot token is the shop's own secret, and AGO has no business redisplaying it).
4. **The inbound half of the same question**: with one bot per tenant, an inbound webhook must be
   attributable to a specific tenant, genuinely — a per-tenant path alone is not enough unless it is also
   authenticated, or anyone who learns or guesses one shop's URL could inject "visitor messages" into
   that shop's conversations.

MAX's own documentation and one third-party integration write-up (relaya.ru's own account of building
against this exact API, since the official documentation does not spell out the verification step in as
much detail) settle (4) directly: `POST /subscriptions` accepts a `secret` alongside the callback `url`,
and MAX echoes that same value back on every webhook delivery as the `X-Max-Bot-Api-Secret` header. This
is the mirror of `6-03`'s outbound `X-Ago-Signature` scheme, for the inbound direction — AGO generates
the secret, hands it to MAX once, and verifies every subsequent delivery against it.

## Decision

### One domain type, not one per channel — `ChannelCredential`, not `MaxBotCredential`

The obvious name for this item's own work is wrong, and an existing arch test proves it before a line of
implementation code was written: `Ago.Chat.Architecture.Tests.ChannelPortTests.NoProviderVocabulary_AppearsAboveInfrastructure`
(`14-01`) refuses any type in `Ago.Chat.Domain`/`Application`/`Contracts` whose name starts with a
provider's own name. That rule exists so a reviewer never has to ask "is this MAX-specific concept
leaking above Infrastructure" — and a MAX-only credential type is exactly the leak it is built to catch.

It is also the right name on its own merits, independent of the test. `14-03`'s SMS aggregator key needs
the identical shape — a secret the shop holds, handed to AGO, encrypted at rest, revocable, never shown
back. `ChannelIdentity` (`14-01`) already established the precedent: one aggregate keyed by `(SiteId,
ChannelKind)`, not a MAX-shaped or SMS-shaped table duplicated per channel. `ChannelCredential` is that
same precedent applied to the credential side of the same problem, and it means `14-03` inherits this
ADR's storage and revocation shape for free rather than re-deriving it.

### Two secrets live on one row, and they are protected two different ways — deliberately, not by oversight

`ChannelCredential` carries:

- `TokenCiphertext` — the shop's own bot token, **AES-256-GCM, reversible.**
- `WebhookSecretHash` — the value AGO generated and handed to MAX at registration, **SHA-256, one-way.**

The asymmetry is the point, and it follows from asking one question about each secret: *does this system
ever need to reproduce the plaintext, or only ever verify a candidate against it?*

The bot token must be reproduced on every future outbound call — MAX's `Authorization` header needs the
real token, not a proof that AGO once knew it. A hash cannot support that, the identical reasoning
`WebhookEndpoint.SecretCiphertext` (`6-03`) already applies to its own reversible column.

The webhook secret is the opposite case, and treating it identically to the token would be over-broad.
AGO generated it, handed it to MAX exactly once at registration, and from then on only ever *verifies* a
value MAX sends back — the same shape a login password is in, which is why `ExternalMessageId.ToClientMessageId`
already established that a bare `SHA256` call is fine to make directly in Domain (pure, deterministic, no
I/O — not a port-worthy resource under `CLAUDE.md` rule 2). Encrypting it reversibly would work, but it
would mean a second thing the encryption key protects for no operational reason: nothing in this system
ever needs that value back in plaintext once the `POST /subscriptions` call that used it has returned.
Narrowing what a key protects is worth doing whenever it costs nothing, and here it costs nothing.
`ChannelCredential.MatchesWebhookSecret` does the comparison in constant time
(`CryptographicOperations.FixedTimeEquals`), the same defence `Ago.Chat.FakeCrm.WebhookSignatureVerifier.Verify`'s
own remarks already apply for the outbound mirror of this exact check.

### The encryption key: `Channels:CredentialEncryptionKey`, and its rotation cost is stated honestly

A new base64-encoded 32-byte AES-256 key, bound the same way `Webhooks:SecretEncryptionKey`/
`Auth:SigningKey` already are (`infra-credentials`, `docker/.env`, gitignored, never committed). It is a
**distinct key from `Webhooks:SecretEncryptionKey`**, not a reuse — see Alternatives below for why reuse
was rejected.

**Its rotation class, stated for `17-03`'s inventory rather than left implicit**: **Breaking**, today.
Rotating this key without a migration tool makes every already-registered channel token permanently
unrecoverable — the identical shape `secrets.md`'s own open finding already records for
`Webhooks:SecretEncryptionKey`, and this ADR does not pretend the situation is better here just because
the key is new. A **Draining** rotation (`adr/0067`'s own template: decrypt-with-old, re-encrypt-with-new,
in one pass, then retire the old key) is the honest future for this key, exactly as `secrets.md` names it
as the fix that key's own open finding still needs. Building that migration tool is not this item's
scope — `secrets.md`'s own finding says the identical thing needs solving for the webhook secret key
first, and doing it once, generically, for both keys, is real future work this ADR names rather than
solves.

### The console never reads a channel credential back, in either sense

No use case this item ships calls `IChannelCredentialCipher.Decrypt` from a read path — the only caller is
the outbound send inside `Ago.Chat.Infrastructure.MaxBot.MaxChannelAdapter`, resolving which token to
present to MAX for one outbound call. `RegisterChannelCredentialHandler`'s own result carries the
generated webhook secret transiently (so the MAX-aware endpoint in `Ago.Chat.Api` can complete the
`POST /subscriptions` call that needs it), and *that* value is never persisted in reversible form at
all — only its hash is stored, so there is nothing to accidentally expose even if a future handler tried.

### Revocation is real; moderation is not a state this system holds

MAX's business-flow registration submits a bot for moderation (observed directly registering this
project's own demo bot, 2026-08-27 — "sent for moderation, up to a day" — a gate the public API
documentation does not mention). AGO's own states stay exactly two: **not connected** and **connected**.
The token does not exist until the bot has passed moderation, so there is no "awaiting moderation" state
for AGO to hold; the review happens entirely upstream, between the shop and MAX. **Revocation is
different, and it is real**: a shop can delete its bot or reset its token after connecting, and the
credential AGO holds simply stops working on the next outbound call. `ChannelCredential.Revoke()` flips
`Active` to `false` — never a hard delete, so the row's own history stays queryable — and a revoked
credential is the concrete reason `MaxChannelAdapter.SendAsync` can return
`ChannelSendOutcome.Refused("No active MAX bot is connected for this site...")`: the tenant-visible
answer this item's backlog note asked for, arriving as an ordinary terminal outcome rather than a special
case.

### One bot per tenant per channel, enforced where it actually matters

`ChannelCredentialConfiguration`'s unique index is on `(site_id, kind)`, **filtered to `active`** —
`ux_channel_credentials_site_kind_active` — not a plain unique index on the pair. A plain index would
mean a revoked credential permanently blocks registering its replacement, which defeats
"revoke-and-recreate," the exact shape `WebhookEndpoint` (`6-03`) already established for its own
endpoints. The Application-layer check (`RegisterChannelCredentialHandler` refuses a second active
credential before ever calling `ChannelCredential.Register`) is the primary mechanism; the partial index
is the storage-level backstop, the same "index is the backstop, not the primary mechanism" division
`adr/0019` draws for `messages`.

### Inbound authentication: MAX's own webhook secret, not the URL alone

The webhook route is `/webhooks/max/{credentialId}` — a per-credential path, but the path is *routing*,
not the authentication. Authentication is `ChannelCredential.MatchesWebhookSecret` against the
`X-Max-Bot-Api-Secret` header MAX echoes back, confirmed against MAX's own subscription mechanism. Even
a guessed or leaked credential id gains nothing without the secret, which AGO never shows to anyone —
not the console, not the shop, not a log line — after generating it.

## Consequences

- **A second encryption key exists, alongside `Webhooks:SecretEncryptionKey`**, and `secrets.md` should
  gain a row for it (`Channels:CredentialEncryptionKey`, class **Breaking**, protects
  `channel_credentials.token_ciphertext`) — this ADR names the row rather than adding it, since editing
  `secrets.md` is not this item's own change to make unreviewed.
- **A shop's bot token is never visible to AGO's own operators once entered**, including inside the
  console's own API responses — a stronger guarantee than `WebhookEndpoint`'s own secret gets (that one
  is shown once, deliberately, because it is AGO's value for the tenant's use).
- **`ChannelCredential` is `14-03`'s (and `14-05`'s) credential storage too, decided now rather than
  re-argued per channel.** The unique index, the two-secrets-two-treatments split, and the revoke-only
  lifecycle all carry forward with no new ADR needed unless a future channel's credential shape genuinely
  differs (e.g., an SMS aggregator key that itself needs periodic rotation on a schedule AGO controls,
  which nothing here anticipates).
- **The encryption key's rotation is Breaking until a shared re-encryption tool exists.** This is an
  honest limitation, not a gap silently introduced by this item — it is the identical, already-recorded
  limitation `secrets.md` carries for `Webhooks:SecretEncryptionKey`, now true of a second key for the
  same underlying reason (no migration tool exists for either).
- **Revocation has no tenant-facing notification mechanism yet.** A revoked credential surfaces as a
  failed send the next time an operator replies, logged and returned as `Refused` — nothing pushes an
  alert to the shop that their channel stopped working. Worth naming as a real gap, not solved here.

## Alternatives considered

- **Reuse `Webhooks:SecretEncryptionKey` for the channel token too.** Rejected: two secrets with
  different rotation triggers (a webhook secret rotates when a tenant re-registers a CRM endpoint; a
  channel credential key rotates on AGO's own schedule or in response to a leak of *that* key
  specifically) should not share a blast radius. A leak investigation for one should never have to
  consider re-encrypting the other's entire population for no reason connected to what actually leaked.
- **Encrypt the webhook secret reversibly too, for symmetry with the token.** Rejected: nothing in this
  system ever needs it back in plaintext after registration, so a reversible cipher would widen what the
  encryption key protects for a value that is safer as a hash. Symmetry between two columns is not a
  reason to give both the stronger-sounding treatment when only one needs it.
- **Hash the bot token, verify-only, the way a password is checked.** Rejected outright: AGO is not
  verifying a token presented back to it, it is *presenting* the token to MAX on every outbound call. A
  hash cannot be un-hashed to produce the value MAX's `Authorization` header needs.
- **Name the domain type `MaxBotCredential`, matching the backlog item's own literal wording.** Rejected:
  fails `ChannelPortTests.NoProviderVocabulary_AppearsAboveInfrastructure` (`14-01`) outright, and even
  setting the test aside, it would mean re-deriving this entire ADR's storage shape from scratch for
  `14-03`'s SMS credential rather than inheriting it.
- **A per-tenant unguessable webhook path with no separate secret**, relying on obscurity alone (the
  shape Telegram bot integrations commonly use when a platform offers no signing secret). Rejected once
  it became clear MAX's own `POST /subscriptions` *does* offer one: obscurity-only is the fallback for a
  platform that gives you nothing better, not the first choice when a real secret is available.
- **Model an "awaiting moderation" state.** An early draft of `14-02`'s own backlog note did exactly
  this, and the author reversed it on 2026-08-27 once it was clear nothing on AGO's side can ever observe
  that state — the token simply does not exist yet. Kept here as a recorded reversal because the
  temptation to model a delay that is real and visible-to-the-shop, but invisible to AGO, is exactly the
  kind of decision worth writing down as *considered and rejected*, not merely absent.
