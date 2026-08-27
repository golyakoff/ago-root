# AGO Inbox: MAX channel adapter

- **Stage**: 14
- **Status**: built and merged 2026-08-27 (`adr/0069`) — two Done-when items still open, both needing a
  real MAX bot conversation: message-in reaching an operator, and an operator's reply reaching MAX back
- **Depends on**: `14-01-external-channel-identity-and-inbound-port.md`

## Goal

A real visitor can message a shop's AGO Chat operators through MAX (VK's own Russian-market messenger,
a free, open Bot API) and get a real operator reply back through the same channel — the first concrete
implementation of `14-01`'s port, and the proof it is shaped correctly. Chosen to be built first among
every channel this product plans to support, for the reason the product spec states plainly: no known
regulatory or legal friction, and a documented Bot API with no reliability question needing a spike
first, unlike Telegram/WhatsApp (`14-05`).

## Context to read first

`docs/architecture/resilience.md`'s "Outbound webhooks to a shop's CRM" row and the whole "How this is
proven" section — this item's own outbound calls to MAX's Bot API (sending a reply) are a boundary with
exactly the same shape (someone else's HTTP API, can be slow or down, must not be allowed to degrade
the rest of the system), so the same timeout/retry/circuit-breaker treatment applies, wrapped through
`14-01`'s own port rather than a bespoke mechanism for this one channel. `14-01`'s own Scope section —
this item is its first real caller, and any gap found in the port's own shape while building this
adapter belongs in a note on this item, not a silent workaround.

## Tenant routing and credential ownership — decided 2026-08-27, before any code

Neither this item nor `14-01` said **which tenant an inbound bot message belongs to**. `ChannelIdentity`
maps an external identity to a `Visitor`, and a `Visitor` belongs to a `Site` — but an inbound bot
message carries no site, so the mapping was ambiguous. Three shapes were weighed:

1. **One bot per tenant**, registered by the shop itself, its token handed to AGO.
2. **One platform-wide bot**, tenant selected by a deep-link start payload.
3. AGO registering bots on a tenant's behalf — not possible; MAX requires the owner.

**Decided: one bot per tenant (1).** It is the shape every comparable integration uses — a Telegram
alerting bot is registered by whoever wants the alerts, not by the tool. It makes routing trivial
(**token → site**, no ambiguity), it removes the unanswerable case in (2) — someone who finds the bot
by search with no payload and therefore has no site — and the shop's customers see the shop's own
brand rather than AGO's. (2) would also have made the bot's display name a positioning decision for
every tenant at once, which is not this item's to take.

### What (1) brings with it, and it is new to this repository

**AGO now stores a credential that belongs to somebody else.** A bot token is not AGO's secret; it is
the shop's, and it grants full control of that bot. The consequences are decisions, not details, and
each belongs in this item:

- **The leak scope is worse than most of what this system holds.** A leaked tenant token is not
  "access to data" — it is the ability to message that shop's customers *as the shop*.
- **A column is not storage.** It needs encryption at rest, and the encryption key is then itself a
  rotatable secret — a row in `17-03`'s inventory, which is being built in parallel. Say which key,
  and how it rotates, rather than deferring it to whoever writes the migration.
- **Revocation and erasure.** Tenant offboarding and `16-02`'s erasure must remove it, not leave it in
  a table for safety's sake.
- **The console never shows it back.** Entered once, replaceable, never readable — the ordinary
  treatment of a third-party API key.

This is an ADR's worth of decision — *how AGO holds a credential belonging to a tenant* — and it is
the first time the question arises. Write it as one.

### The inbound half of the question, to be answered against MAX's real documentation

With one bot per tenant, a webhook arrives at AGO and must be attributed. **How do we establish that
an inbound webhook genuinely came from MAX, and belongs to that specific tenant?** A per-tenant path
must be either unguessable or authenticated; otherwise anyone can inject "visitor messages" into
another shop's conversation. `6-03` signs *outbound* webhooks — this is the mirror problem, and the
answer must come from what MAX actually provides (a signature, a bot id in the payload, something
else), confirmed against the documentation rather than assumed.

### Confirmed against MAX's own documentation, 2026-08-27

- Base URL **`https://platform-api2.max.ru`**; the token travels in the `Authorization` **header**,
  not a query parameter. **30 rps.**
- **Webhook and long polling both exist and are mutually exclusive** — one or the other, never both.
  MAX's documentation calls long polling suitable for development only ("limited by speed and event
  retention") and webhook the production mechanism. So this item's own "state which MAX's actual API
  requires and place it there accordingly" resolves to **both**: a polling `BackgroundService` in
  `Worker` for the local loop, a webhook receiver for the deployed one. Say so rather than picking one
  and leaving the other loop broken.
- **Webhooks require public HTTPS with a certificate from a trusted CA.** Since 2026-05-25 plain HTTP
  and self-signed certificates are refused. The demo already satisfies this.
- A bot is created by messaging **`@MasterBot`** inside MAX (`/newbot`). The API documentation
  describes no separate developer console.

**There is a moderation gate, and the API documentation does not mention it.** Observed directly on
2026-08-27, registering this project's own demo bot through MAX's business flow: submitting the bot
returns *"sent for moderation, the check takes up to 1 day, we will send a notification"*. An earlier
draft of this section said there was no documented gate, which was true of the documentation and false
of the product. **Trust the observation.**

**But moderation is not a state AGO can ever hold** (author, 2026-08-27). The token is issued only
once the bot has passed; a bot still in review has no token to hand over. So AGO's own states are
*not connected* and *connected*, and the review happens entirely upstream, between the shop and MAX,
before AGO is involved at all. A first draft of this section modelled *awaiting moderation / active /
rejected* — that was wrong, and it is worth recording why: the delay is real and visible to the shop,
which made it look like something to model, but nothing on our side can observe it.

What it does change:

- **Onboarding cannot be same-hour, and the copy must say so.** The shop leaves, waits up to a day,
  and comes back with a token. `10-03`'s signup flow must not present the channel as a switch —
  connecting MAX is an errand, not a toggle.
- **Whatever this item builds must be testable before any token exists**, which is a further argument
  for the local long-polling loop being a first-class path rather than a convenience.

**Revocation, however, is a real state and a different one.** A shop can delete its bot or reset its
token after connecting, and the credential AGO holds stops working. That surfaces as a rejected call
at use time, not as a status to poll, and it needs a tenant-visible answer — the channel stops
working and the shop is told which credential to replace, rather than messages silently failing.

Also worth recording: the registration reached this project through MAX's **business** flow, which
asks for a phone number and a website, not only the `@MasterBot` `/newbot` exchange the documentation
describes. Whether those are two paths to the same thing is unknown and was not established.

**Note on placement:** `Ago.Chat.Webhooks` is `adr/0013`'s bulkhead for *outbound* third-party
latency — "expected to be slow and failing; must not affect the others". An inbound bot webhook has a
different failure profile and is not automatically its home. Decide, and say why.

## Scope

- `MaxChannelAdapter` (`Ago.Chat.Infrastructure.MaxBot`, one project per external technology matching
  `naming-and-structure.md`'s existing "one project per external technology" rule): implements
  `IInboundChannelAdapter` for MAX's Bot API — inbound message receipt (MAX's own webhook or long-poll
  mechanism, whichever its API actually offers; state which once confirmed against MAX's real
  documentation, not assumed) and outbound reply sending, both wrapped in `Ago.Platform.Resilience`'s
  existing policies via the same `ResiliencePipeline` shape `Ago.Platform.Storage.S3` already
  establishes for a real external HTTP dependency.
- A bot registered with MAX for local/dev testing — credentials sourced from `infra-credentials`/
  `docker/.env`, never committed (`repositories.md`'s "no secrets, ever," unchanged).
- The webhook endpoint (if MAX's API is webhook-shaped) or the polling `BackgroundService` (if long-poll)
  lives in `Ago.Chat.Api`/`Worker` respectively, following whichever of the two matches
  `adr/0013`'s own failure-profile reasoning — a webhook receiver is request-shaped (`Api`), a poller is
  restart-tolerant background work (`Worker`); state which MAX's actual API requires and place it there
  accordingly, not by default.

## Out of scope

- SMS, Telegram, WhatsApp — `14-03`/`14-05`.
- Offline auto-reply's own interaction with this channel — `14-03`'s own scope covers making auto-reply
  channel-agnostic; this item only has to prove a real operator reply reaches MAX correctly.
- Unattended booking through MAX — `21-01`, blocked, genuinely unsolved UX question.

## Done when

- [ ] A real message sent from a real MAX account reaches an operator in the console, through the same
      queue a widget conversation already uses (`14-01`'s own mapping into `SendVisitorMessage`) —
      verified live against a real MAX bot, not a fake adapter.
- [ ] A real operator reply from the console is delivered back to the same MAX conversation — verified
      live, both directions proven, matching this repository's own "verified means actually run"
      standard (`k8s-local.md`'s own phrase, applied here).
- [x] `Ago.Chat.Integration.Tests` (or a MAX-specific fixture matching `AttachmentFixture`/`MinioFixture`'s
      own precedent for a real-external-dependency test harness): MAX's outbound API stopped/unreachable
      degrades gracefully (the circuit breaker opens, the rest of the system's message pipeline is
      unaffected) — proven with a real container-failure-style test, not asserted. Shipped as
      `Ago.Chat.FakeMax`/`.Tests` (a real separate process, `Ago.Chat.FakeCrm`'s own technique) and
      `MaxChannelAdapterResilienceTests`, which stops that process mid-test.
- [x] `docs/architecture/resilience.md` gains MAX's Bot API as a named row (or note) in the boundary
      table, and `docs/architecture/data-model.md`/`messaging.md` get whatever schema/event notes this
      adapter's real implementation surfaces. (No new integration event: outbound delivery goes through
      the existing `ChannelMessageDeliveryConsumer`/outbox path, nothing for `messaging.md` to add.)

## Open questions

None — MAX is named in the product spec as the deliberately lowest-friction channel to build first
specifically because it has no open legal/reliability question the way Telegram/WhatsApp do; anything
this item finds genuinely uncertain about MAX's own API belongs as a note on this item once discovered,
not a pre-emptive open question here.
