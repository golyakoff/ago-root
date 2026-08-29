# AGO Inbox: VK (ВКонтакте) channel adapter

- **Stage**: 14
- **Status**: ready
- **Depends on**: `14-01-external-channel-identity-and-inbound-port.md` — reuses the port and
  `ChannelIdentity` concept unchanged, the same way `14-02` (MAX) and `14-07` (Telegram) already do

## Goal

A visitor can message a shop's AGO Chat operators through a VK community's own messages (Сообщения
сообщества), and get a real operator reply back through the same channel — the third concrete channel
adapter after MAX (`14-02`) and Telegram (`14-07`).

## Why this, and why now

`ago-business/docs/decisions/0009-razryv-po-fucham-s-jivo-chto-stroim-chto-net.md` names VK as a real,
qualitatively weighty gap against the nearest direct competitor (Jivo), specifically for the target
customer this project already committed to (`0002`: a small Russian online shop) — Russian social
commerce runs heavily through VK, arguably more than through Telegram for this exact segment, though
that is a qualitative argument in the business decision, not a number measured here. This item exists
because the business side named it, not because an engineering session picked it independently — read
`0009` before touching scope here if the business reasoning needs revisiting.

## Context to read first

`14-02`'s own backlog file and its "Tenant routing and credential ownership" section — the identical
question (which tenant does an inbound message belong to, one-bot-per-tenant vs platform-wide-bot vs
AGO-registers-on-tenant's-behalf) needs answering again for VK's own API shape, which may differ from
MAX's (VK's Callback API for community messages uses a community access token plus a confirmation
string, not quite the same bot-registration flow — verify against VK's own current documentation before
assuming MAX's answer transfers unchanged). `docs/architecture/resilience.md`'s outbound-webhook
treatment, reused unchanged through `14-01`'s port, exactly as `14-02`/`14-07` already do.

## Scope

- A `ChannelKind.Vk` value (or equivalent — confirm the current `ChannelKind` enum's exact shape before
  assuming a bare addition is enough) and a concrete `IInboundChannelAdapter` implementation for VK's
  Callback API.
- Inbound: VK's Callback API delivers events via an HTTP callback to a URL a community admin configures
  — this is push, not poll, a different shape from MAX's/Telegram's own inbound mechanism; the exact
  webhook verification/confirmation handshake VK requires needs its own spike before assuming the
  existing `IInboundChannelAdapter` shape fits without change.
- Outbound: reply delivery via VK's own Messages API, wrapped in the same resilience pipeline every
  other channel already uses.
- Tenant routing and credential ownership, decided explicitly before code, the same way `14-02` did.
- Console-facing connect/disconnect endpoints, matching `TelegramChannelEndpoints.cs`'s/
  `MaxChannelEndpoints.cs`'s own shape.

## Out of scope

- VK Ads/marketing API, VK Donut, or anything beyond a community's own direct messages.
- Group posts/comments — only direct messages to the community, the same channel shape every other
  adapter in this stage covers.

## Done when

- [ ] A real message sent to a real VK community's messages reaches an operator through the same
      console queue a widget conversation already does.
- [ ] A console reply reaches the same VK conversation back — verified live against a real VK community
      and a real account, the same bar `14-02`/`14-07` already held themselves to.
- [ ] Tenant routing and credential ownership are decided and recorded, the same way `14-02`'s own
      backlog file records its equivalent decision.

## Open questions

None yet — the webhook-vs-poll shape difference from MAX/Telegram is the first thing to resolve, and
belongs in this item's own report once investigated, not guessed at here.
