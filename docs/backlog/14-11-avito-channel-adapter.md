# AGO Inbox: Avito channel adapter

- **Stage**: 14
- **Status**: done (`ago-chat#130`, merged 2026-08-30)
- **Depends on**: `14-01-external-channel-identity-and-inbound-port.md` — reuses the port and
  `ChannelIdentity` concept unchanged, the same way `14-02`/`14-07`/`14-08`/`14-10` already do

## Goal

A visitor messages a shop's AGO Chat operators through Avito's own messaging system (a buyer messaging
a seller about a listing), and gets a real operator reply back through the same channel.

## Why this, and why now

`ago-business/docs/decisions/0009` named Avito as an open question — "not decided here, depends on
whether the target customer actually trades through Avito, not quantitatively checked." `0010`
overrides that with a direct decision to build, without waiting on the quantitative check `0009` asked
for. **This item does not re-litigate that call** — it is scoped as ready to build on the strength of
`0010`'s decision, the same way `14-08` (VK) was scoped ready on a qualitative argument rather than a
measured one.

## Context to read first

`14-08`'s own "Confirmed against VK's own documentation" section — the template this item's own
investigation should follow: find Avito's actual current API shape from Avito's own published
documentation (their Messenger API, distinct from their listing/ads API — verify this item targets the
right one before assuming), state plainly which source was actually used. `14-02`'s "Tenant routing and
credential ownership" section — Avito's own answer to "which tenant does an inbound message belong to"
needs deciding fresh; Avito's own shape is likely per-account (one Avito seller account per tenant,
matching VK's per-community and MAX's per-bot precedent) but confirm rather than assume.

## What is different about Avito, worth naming before scoping the rest

Avito's own messaging system is **listing-scoped** — a conversation on Avito is tied to a specific
listing (`объявление`) a buyer is messaging about, not just to the seller account generally. This is a
real shape difference from every channel adapter this project has built so far (MAX/Telegram/VK/
WhatsApp are all account-to-account, with no third "which listing" dimension). Decide explicitly
whether `ChannelIdentity` needs to carry that listing reference or whether it can be safely dropped
(the visitor is still identified by their Avito account either way, and AGO Chat has no concept of a
"listing" and should not grow one — the same "Chat stays a closed vocabulary" discipline `adr/0065`
already established for a different reason) before writing the inbound parser.

## Scope

- A `ChannelKind.Avito` value and a concrete `IInboundChannelAdapter` implementation for Avito's own
  Messenger API webhook or polling shape (confirm which Avito actually offers before assuming
  webhook-only, the same "do not assume the last channel's shape transfers" caution `14-08`'s own file
  gives for MAX-to-VK).
- Outbound reply delivery via Avito's own Messenger API, wrapped in the same resilience pipeline every
  other channel adapter already uses.
- Tenant routing and credential ownership, decided explicitly before code.
- Console-facing connect/disconnect endpoints, matching the existing four channels' own shape.
- The listing-scope question above, decided and recorded before the inbound parser is written.

## Out of scope

- Avito's own listing/ads management API — posting, editing, or pricing a listing. Only direct
  buyer-seller messages, the same channel-only boundary every adapter in this stage already holds.
- Avito Pro/business-tier features beyond messaging (analytics dashboards, promoted listings) — this
  item is a messaging channel, not an Avito account-management integration.

## Done when

- [ ] A real message sent to a real Avito seller account's messages reaches an operator through the
      same console queue a widget conversation already does.
- [ ] A console reply reaches the same Avito conversation back.
- [ ] Tenant routing, credential ownership, and the listing-scope question above are decided and
      recorded, the same way `14-02`'s own backlog file records its equivalent decisions.
- [ ] Live verification against a real Avito seller account and a real message — if no such account
      exists in the environment this item is built in, say so plainly rather than claiming it, the same
      honest gap `14-08`'s own file names for VK.

## Open questions

None new — Avito's own API shape (webhook vs. poll, and the exact listing-scope answer) is this item's
own investigation to close before writing code, the same discipline every channel adapter in this stage
already follows.
