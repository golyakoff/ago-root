# AGO Inbox: SMS channel adapter

- **Stage**: 14
- **Status**: ready — scoped so the real vendor choice (Open questions, below, shared with `20-05`'s
  own identical open question) does not block the port wiring or a documented fake adapter; only the
  real-gateway adapter is deferred
- **Depends on**: `14-01-external-channel-identity-and-inbound-port.md`

## Goal

A visitor can hold a real, bidirectional conversation with an AGO Chat operator over plain SMS — no
app, no account, just a phone number — the second concrete channel adapter after MAX (`14-02`), and the
one that makes the "AGO Chat reaches a visitor with no smartphone or messenger account at all" case
real. This item builds the port implementation and inbound/outbound wiring against a documented fake
gateway; the real SMS-gateway vendor integration is named as a deferred follow-up, matching `20-05`'s
own identical scoping choice for the same underlying reason (`CLAUDE.md`'s rule against inventing a
vendor/price).

## Context to read first

`docs/backlog/20-05-sms-confirmation-delivery.md` in full — read its Scope and Out-of-scope sections
closely: that item's `ISmsSender` is outbound-only, fixed-template, platform-shaped
(`Ago.Platform.Abstractions`); this item's channel adapter is bidirectional, arbitrary-conversation,
product-shaped (implements `14-01`'s `IInboundChannelAdapter`, `Ago.Chat.Application.Abstractions`).
State explicitly, once both items are implemented, whether they end up sharing one underlying gateway
account/HTTP client (plausible — the same vendor can serve both use cases) while keeping the two
*ports* distinct, or whether they stay on genuinely separate vendors — this is a real integration
decision for whichever session builds the second of the two, not resolved by either item alone.
`docs/architecture/resilience.md`'s boundary table — the same outbound-HTTP-provider treatment `14-02`
already applied to MAX's Bot API applies here to whichever SMS gateway is eventually chosen.

## Scope

- `SmsChannelAdapter` (`Ago.Chat.Infrastructure.Sms` or wherever `20-05`'s own eventual real adapter
  ends up living, if the two items' implementations turn out to share one project — decide and state
  once both exist) implementing `14-01`'s `IInboundChannelAdapter`: inbound (the gateway's own webhook
  for a received SMS) and outbound (send a reply) sides.
- A documented fake gateway adapter, the same role `20-05`'s own fake `ISmsSender` plays, proving the
  whole inbound-to-`SendVisitorMessage`-to-outbound-reply path end to end without a real gateway
  credential.
- The inbound webhook endpoint lives in `Ago.Chat.Api` (request-shaped, matching `adr/0013`'s own
  reasoning, and matching `13-02`'s own precedent for "an inbound third-party webhook is an ordinary
  `Ago.Chat.Api` endpoint, not routed through `Ago.Chat.Webhooks`, because the isolation that host exists
  for is about *our own* slow outbound calls, not an inbound call where the caller manages their own
  latency").

## Out of scope

- The real SMS-gateway vendor integration — a follow-up item once the vendor question is answered
  (shared with `20-05`'s identical open question; answering it once should unblock both items' real
  adapters, not be researched twice).
- MAX, Telegram, WhatsApp — `14-02`/`14-05`.
- Any merge of this adapter with `20-05`'s own `ISmsSender` implementation into one shared vendor client
  — named above as a real future decision, not made here.

## Done when

- [ ] `Ago.Chat.Integration.Tests`: a fake-gateway inbound SMS reaches an operator through the console
      queue exactly like a MAX or widget message does; an operator reply is handed to the fake gateway
      with the right destination number and body.
- [ ] A redelivered inbound webhook (the gateway's own at-least-once retry, if its API has one — state
      whether it does once confirmed) does not create a duplicate message, matching `messaging.md`'s
      "handlers must be safe to run twice" discipline applied to an HTTP-triggered inbound path the same
      way `13-02`'s own webhook receiver already does it for a different provider.
- [ ] `docs/architecture/resilience.md`/`data-model.md` gain whatever notes this item's real
      implementation surfaces.

## Open questions

**Which real SMS gateway to integrate, and its real per-message price** — identical open question to
`20-05`'s own, deliberately not answered twice. Whichever item's own follow-up does the real vendor
research first should record it in one ADR both this item and `20-05`'s own real-adapter follow-up can
cite, not two independent ADRs reaching potentially different answers for the same underlying
capability.
