# ADR-0080: the email channel has no per-tenant credential, and threads by subaddress

- **Status**: Accepted
- **Date**: 2026-08-31
- **Stage**: 14

## Context

`14-09` adds email as AGO Inbox's sixth channel adapter. Every channel before it — MAX (`14-02`),
Telegram (`14-07`), VK (`14-08`), WhatsApp (`14-10`), Avito (`14-11`) — shares one shape, recorded in
`adr/0069`: a shop enters its own bot/community/account token once, AGO stores it as a
`ChannelCredential` row (site, kind, encrypted token, an optional provider-owned second identifier), and
an inbound webhook resolves its tenant either from a `{credentialId}` URL segment or, for WhatsApp, from
a repository lookup keyed by that stored identifier.

Email fits none of this. `10-05` already decided this deployment's own mail infrastructure: a single
self-hosted Postfix relay, shared by the whole deployment, with no third-party inbound-parse provider in
the picture at all (that item's own Out-of-scope section: "no IMAP, no webmail, no per-person accounts,
no mail service for humans"). There is no shop-supplied account to link, and inbound mail has no `To`
address that is provisioned per tenant the way a bot token or a phone number is — every site's mail would
have to funnel through the same relay regardless.

A second, unrelated force: every other channel replies to a chat id or a phone number and lets the
provider's own app handle conversation grouping. Email has no such provider-side grouping — a visitor's
mail client threads messages itself, from `In-Reply-To`/`References` headers this system must set
correctly on every reply, or every operator reply shows up as a new, disconnected message.

## Decision

**No `ChannelCredential` row for email, and no console connect/disconnect endpoint.** `Ago.Chat.Infrastructure.Email.EmailBotApiOptions`
is deployment-wide configuration (sending domain, SMTP relay host/port, one shared inbound webhook
secret), bound once from `Channels:Email` like every other channel's options, but never written to a
per-site table. Every site with a real `SiteId` becomes mailable the instant it exists — there is nothing
an operator could enter that this system does not already know.

**Tenant routing is subaddressing off one shared local part**: a real recipient address is
`support+{siteId:N}@{domain}`, and `EmailRecipientAddress.TryParseSiteId` extracts the `SiteId` directly
from the address, with no database lookup. `EmailWebhookEndpoints` still confirms the parsed id names a
real, existing site (`ISiteRepository.GetByIdAsync`) before doing anything with it — a parseable id is not
proof of existence, the same caution `WhatsAppWebhookEndpoints` already applies to an unrecognised
`phone_number_id`.

**A new, minimal Domain type, `EmailThreadState`, tracks just enough per-conversation history to build
correct threading headers**: the first inbound message's own `Message-ID` (`RootMessageId`), the most
recent one (`LastInboundMessageId`), and the subject line to echo back. It is written by
`Ago.Chat.Api`'s `EmailWebhookEndpoints`, after the shared, channel-neutral `ReceiveChannelMessageHandler`
has already resolved a `ConversationId` — not inside that handler, which must not gain a field only one
channel ever populates (`ChannelPortTests`' own "no provider timestamp" rule states the identical
principle for a different field).

**Outbound SMTP is hand-rolled over a raw `TcpClient`**, not a NuGet package (MailKit is the closest
comparison). This deployment's one real relay needs neither `AUTH` nor `STARTTLS`
(`10-05`'s own report: "no SASL, no TLS needed" on the cluster-internal hop), which removes most of what a
full SMTP library exists to handle; the remaining protocol surface (`EHLO`/`MAIL FROM`/`RCPT TO`/`DATA`,
reply-code parsing, dot-stuffing) is comparable in size to `WhatsAppApiClient`, the hand-rolled `HttpClient`
wrapper every other channel already uses for its own provider protocol.

**The inbound webhook's own JSON contract is this item's own invention**, not a confirmed third-party
shape, because no third-party inbound-parse provider exists in this deployment at all. It states plainly,
in `EmailInboundWebhookPayload`'s own remarks, what a currently-unbuilt Postfix pipe-transport script
(ago-deploy's own future work) would need to produce.

## Consequences

- Positive: a new site needs zero provisioning to receive email — no alias to add, no DNS record, no
  console step. The whole channel can be verified end to end against a real Postgres and a real Kestrel
  host without a live third-party account, the same "prove against the real handler chain" bar `14-08`/
  `14-10` already held themselves to.
- Positive: no new secret-management surface. `ChannelCredential`'s own encryption/decryption machinery
  is untouched; email introduces nothing for it to protect.
- Negative: email can only be turned on or off for the *whole deployment*, not per site — there is no
  per-tenant credential row to revoke if one shop's email needs to be disabled independently of the rest.
  A future need for that would require a real design change (most plausibly, a nullable per-site opt-out
  flag on `Site` itself, not a `ChannelCredential` row with nothing to store).
- Negative: the inbound wire contract has no confirmed real-world counterpart. The first real Postfix
  pipe-transport script written against it may need to change either itself or `EmailInboundWebhookPayload`
  — named honestly rather than presented as settled.
- Negative: the hand-rolled SMTP client has no `STARTTLS`/`AUTH` support. Pointing `SmtpHost` at a relay
  that requires either would fail in a way this client does not explain well (a generic connection or
  protocol error, not "this relay wanted STARTTLS").

## Alternatives considered

- **A dedicated per-site mailbox/alias, provisioned in Postfix's own alias map.** Rejected: needs a real
  write to the mail server's own configuration on every site creation, a coordination point this
  engineering-only item cannot drive (`10-05`'s own aliases are static, hand-edited).
- **A per-tenant subdomain** (`support@{site}.ago-chat.example`). Rejected: needs either a wildcard MX or a
  DNS write per site; `10-05`'s own zone has exactly one MX record today.
- **Reusing `ChannelCredential` with an empty/placeholder token**, purely to keep every channel's storage
  shape identical. Rejected: it would store a secret column for a channel with no secret, and would still
  need a console connect endpoint with nothing genuine for an operator to enter — storing a fact for the
  sake of a shared shape, not because the fact exists.
- **MailKit** for outbound SMTP. Rejected for the reason `CLAUDE.md` requires stating: it would replace
  hand-rolled protocol code comparable in size to what this codebase already hand-rolls for every other
  channel's own HTTP boundary, for a relay that needs none of the library's harder features (TLS
  negotiation, SASL mechanisms, connection pooling).
- **IMAP/POP mailbox polling**, the item's own scope-note alternative (b). Rejected: `10-05` already ruled
  out running a real mailbox service ("no IMAP... and none planned"), and polling would be the one
  channel in this stage not shaped like every other adapter's own push delivery.
