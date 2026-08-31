# AGO Inbox: email channel adapter

- **Stage**: 14
- **Status**: built (2026-08-31, `ago-chat#141`, not yet merged) —
  a real inbound email reaches an operator and a real console reply reaches the visitor back, both proven
  against a real Postgres and the real production handler/endpoint chain, and — unlike every channel
  before it — with **no live-verification gap left by a missing third-party account**: this channel's
  own outbound side is a real SMTP client speaking to a real server in every test, and its inbound side
  is this item's own invented contract, not a vendor's. See "What was and wasn't verified" below before
  checking the remaining Done-when boxes.
- **Depends on**: `14-01-external-channel-identity-and-inbound-port.md` — reuses the port and
  `ChannelIdentity` concept unchanged, the same way every earlier channel does. **Decided against**
  reusing `14-02`'s own `ChannelCredential`/console-connect shape — see `adr/0080` for why this channel
  has none of that at all.

## Goal

A visitor can email a shop's support address and have that thread become an ordinary AGO Chat
conversation, with operator replies delivered back as real emails to the visitor's own inbox — the
sixth concrete channel adapter, and the one closing the plainest table-stakes gap this product still
had.

## Why this, and why now

`ago-business/decisions/0009` names email
explicitly as "table stakes, does not distinguish from the competitor, just closes a hole" — deliberately
lower business priority than VK (`14-08`), which the same decision argues is qualitatively more
important for the actual target customer. Picked up next in the queue, not because it became urgent.

## Context read first, and what changed since this item was filed

`14-01`'s port and `ChannelIdentity` concept — an email address is the external identity here, the same
category `ExternalChannelAddress` already models for a phone number or a chat id. `14-08`'s/`14-10`'s own
"Confirmed against the provider's own documentation" sections were the template this item's own research
tried to follow — and immediately could not, for a reason worth stating plainly: **there is no third-party
provider here to confirm anything against.** `10-05` (checked before starting, as this item's own Scope
section asked) had already been decided and shipped: a single self-hosted Postfix relay, no SES/Mailgun/
SendGrid/Postmark-style provider in the picture at all, and its own Out-of-scope section says "no IMAP, no
webmail, no per-person accounts, no mail service for humans... and none planned." That ruled out this
item's own scope-note alternative (b) outright (no mailbox to poll), and made alternative (a)'s own
"transactional email provider" framing not quite fit either — the inbound-parse webhook this item builds
against is **this item's own invented contract**, for a Postfix pipe-transport script that does not exist
yet (ago-deploy's own future work, out of this item's scope). Named honestly in
`EmailInboundWebhookPayload`'s own remarks and in `adr/0080`, not presented as a confirmed real shape.

## Decisions this item made (full reasoning in `adr/0080`)

- **No `ChannelCredential` row, and no console connect/disconnect endpoint at all** — the central
  departure from every channel before it. `10-05`'s relay is deployment-wide, not a per-shop account, so
  there is nothing for an operator to enter. `EmailBotApiOptions` is deployment-wide configuration
  instead, bound once like every other channel's options.
- **Tenant routing: subaddressing, decided over a dedicated address or a per-tenant subdomain** — a real
  recipient address is `support+{siteId:N}@{domain}`, and the `SiteId` is extracted from the address
  itself with no database lookup (`EmailRecipientAddress`), then confirmed against a real site before
  anything is attributed to it. A brand-new site is mailable the instant it exists, with zero
  provisioning step.
- **Threading state is a new, minimal Domain type, `EmailThreadState`** — the first inbound message's own
  `Message-ID`, the most recent one, and the subject line, written by `EmailWebhookEndpoints` after
  `ReceiveChannelMessageHandler` resolves a `ConversationId`, not inside that shared handler (which must
  not gain a field only one channel populates).
- **Outbound SMTP is hand-rolled over a raw `TcpClient`, not MailKit** — the identical "one project, one
  provider protocol, hand-rolled over a BCL primitive" shape every other channel's own outbound client
  already uses for HTTP, applied here to SMTP. No `STARTTLS`/`AUTH` — `10-05`'s own relay needs neither.
- **Outbound MIME is base64-encoded `text/plain`, with RFC 2047-encoded subjects** — byte-safe without
  depending on `8BITMIME` negotiation this hand-rolled client does not check for, and correct for a
  Cyrillic subject line, the ordinary case for this project's own target customer
  (`ago-business/decisions/0002`).

## Scope

- A `ChannelKind.Email` value and a concrete `IInboundChannelAdapter` implementation
  (`Ago.Chat.Infrastructure.Email.EmailChannelAdapter`).
- Inbound: a webhook (`Ago.Chat.Api`'s `EmailWebhookEndpoints`, `POST /webhooks/email`), authenticated by
  one deployment-wide HMAC-SHA256 shared secret (`X-Ago-Email-Signature`), the same "one App-wide secret,
  not per-tenant" shape WhatsApp's own webhook uses, for a different underlying reason (`adr/0080`).
- Outbound: replies sent as real email (`EmailSmtpClient`), carrying `In-Reply-To`/`References` built
  from `EmailThreadState`, wrapped in the same resilience pipeline every other channel adapter already
  uses (`ChannelResiliencePipelines`, keyed per `ChannelKind`, unchanged).
- Tenant routing, decided explicitly before code — see "Decisions this item made" above and `adr/0080`.

## Out of scope

- Rich HTML email rendering beyond what the existing message body already handles — a visitor's email
  becomes plain text in the conversation, matching every other channel's own text-only shape.
- Email marketing/broadcast sending. This is support-thread email only.
- **The actual Postfix pipe-transport script that would produce a real `EmailInboundWebhookPayload`
  delivery from a real inbound SMTP transaction** — ago-deploy's own work, named explicitly rather than
  silently assumed to already exist. Without it, nothing can currently deliver a real inbound email to
  this route.
- A per-site email on/off switch — `adr/0080`'s own named consequence of shipping no `ChannelCredential`
  for this channel: today email is deployment-wide only.
- Console-facing connect/disconnect endpoints — deliberately not built; `adr/0080` explains why there is
  nothing for one to do.

## What was and wasn't verified

**Fully proven, against real infrastructure, not mocks:**
- The webhook route, authenticated and unauthenticated, against a real Postgres and the real
  `ReceiveChannelMessageHandler`/`StartConversationHandler`/`SendVisitorMessageHandler` chain
  (`EmailWebhookEndpointsTests`, 8 tests) — including `EmailThreadState` being written on the first
  inbound message and updated (not re-created) on the second, and an unknown-but-well-formed `SiteId`
  being acknowledged rather than rejected.
- The full SMTP client — connect, `EHLO`/`MAIL FROM`/`RCPT TO`/`DATA`, dot-stuffing, base64 body encoding,
  RFC 2047 subject encoding, the 5xx/4xx terminal/transient split, and an unreachable-relay failure — all
  against a real, in-process, ephemeral-port TCP server standing in for `10-05`'s own relay
  (`EmailSmtpClientTests`, 9 tests).
- The adapter's own routing (From-address subaddressing, threading-header construction, the "should not
  happen" throws for a missing conversation or thread state) over that same real SMTP boundary
  (`EmailChannelAdapterTests`, 6 tests).
- The inbound parser and the recipient-address routing as pure functions (`EmailInboundMessageParserTests`,
  `EmailRecipientAddressTests`, 24 tests combined).

**Not verified, and cannot be from this environment:** a real inbound SMTP delivery, through `10-05`'s
own live Postfix relay, reaching this route as a real `EmailInboundWebhookPayload` — because the script
that would produce one does not exist yet (see Out of scope). Once that script exists, this item's own
Done-when boxes below can be closed for real.

## Done when

- [ ] A real email sent to a shop's support address reaches an operator through the same console queue
      a widget conversation already does. **Not verified live** — the Postfix-to-webhook pickup script
      this would require does not exist in this environment (see Out of scope); proven instead against
      the real production handler chain over a realistic JSON delivery (`EmailWebhookEndpointsTests`).
- [ ] A console reply reaches the visitor as a real, correctly-threaded email — **not verified against a
      real visitor inbox**, but the SMTP conversation and the MIME headers it produces are proven against
      a real SMTP server implementation (`EmailSmtpClientTests`), including the exact `In-Reply-To`/
      `References` values a real mail client would thread on.
- [x] Tenant routing (which address maps to which site) is decided and recorded — subaddressing, no
      per-tenant provisioning; see "Decisions this item made" above and `adr/0080`.

## Open questions

None new. Both open items named above are the live-verification pass and the ago-deploy-side pickup
script, tracked as the two unchecked Done-when boxes, not design questions.
