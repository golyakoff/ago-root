# AGO Inbox: email channel adapter

- **Stage**: 14
- **Status**: ready
- **Depends on**: `14-01-external-channel-identity-and-inbound-port.md`

## Goal

A visitor can email a shop's support address and have that thread become an ordinary AGO Chat
conversation, with operator replies delivered back as real emails to the visitor's own inbox — the
fourth concrete channel adapter, and the one closing the plainest table-stakes gap this product still
has.

## Why this, and why now

`ago-business/docs/decisions/0009-razryv-po-fucham-s-jivo-chto-stroim-chto-net.md` names email
explicitly as "table stakes, does not distinguish from the competitor, just closes a hole" — deliberately
lower business priority than VK (`14-08`), which the same decision argues is qualitatively more
important for the actual target customer. Scoped and filed now so it is ready when its turn in the
queue comes, not because it is urgent.

## Context to read first

`14-01`'s port and `ChannelIdentity` concept — an email address is the external identity here, the same
category `ExternalChannelAddress` already models for a phone number or a chat id. `14-02`'s/`14-07`'s
own adapters for the resilience-pipeline wrapping pattern to reuse unchanged.

## Scope

- A `ChannelKind.Email` value and a concrete `IInboundChannelAdapter` implementation.
- **Inbound mechanism needs a real decision, not an assumption**: email delivery to this system means
  either (a) an inbound-email-parsing webhook from a transactional email provider (e.g. the same
  provider `10-05`'s transactional email work already integrates, if that reuse is available by the
  time this is picked up — check `10-05`'s own status first) or (b) a real IMAP/POP mailbox this system
  polls. (a) is the shape every other adapter in this stage already uses (push, not poll) and should be
  preferred unless a concrete reason rules it out.
- Outbound: replies sent as real email, carrying enough threading headers (`In-Reply-To`/`References`)
  that a visitor's own mail client threads the conversation correctly — a real, easy-to-get-wrong detail
  worth naming explicitly rather than discovering after the fact.
- Tenant routing: unlike MAX/Telegram/VK (one bot/community per tenant), an inbound email's tenant is
  resolved from **which address it was sent to** — each site presumably needs its own dedicated
  support address or a subaddress scheme (`support+{siteId}@...` or a real per-tenant subdomain) —
  decide and record explicitly, the same discipline `14-02`'s own routing section holds itself to.

## Out of scope

- Rich HTML email rendering beyond what the existing message body already handles — a visitor's email
  becomes plain text in the conversation, matching every other channel's own text-only shape.
- Email marketing/broadcast sending. This is support-thread email only.

## Done when

- [ ] A real email sent to a shop's support address reaches an operator through the same console queue
      a widget conversation already does.
- [ ] A console reply reaches the visitor as a real, correctly-threaded email — verified live.
- [ ] Tenant routing (which address maps to which site) is decided and recorded.

## Open questions

Which inbound mechanism (webhook vs. mailbox poll) and which tenant-routing scheme (dedicated address
vs. subaddress) are this item's own calls to make and record, not guessed at here.
