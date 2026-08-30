# AGO Inbox: WhatsApp Business channel adapter

- **Stage**: 14
- **Status**: ready
- **Depends on**: `14-01-external-channel-identity-and-inbound-port.md` — reuses the port and
  `ChannelIdentity` concept unchanged, the same way `14-02` (MAX), `14-07` (Telegram) and `14-08` (VK)
  already do

## Goal

A visitor messages a shop's AGO Chat operators through WhatsApp, and gets a real operator reply back
through the same channel — the fourth concrete external channel adapter.

## Why this, and why now

`ago-business/docs/decisions/0009` names WhatsApp as Level 1 (basic trust as a chat tool) — the single
channel it calls out by name as the one Jivo has and AGO does not, for the target customer (`0002`: a
small Russian online shop) specifically. `ago-business/docs/decisions/0010` removes the one thing that
was blocking it: `14-05`'s own WhatsApp legal-review box, still genuinely unfinished, is no longer a
prerequisite for starting the engineering work — the author accepted that risk explicitly, in `0010`,
not silently here. **Read `14-05`'s own file before assuming "legal is fine now" — it is not; the
decision is to build anyway, and that decision belongs to `0010`, not to this item pretending the
question was answered.**

## Context to read first

`14-08`'s own backlog file ("Confirmed against VK's own documentation" section) — the template this
item's own investigation should follow: find WhatsApp's actual current API shape from Meta's own
published documentation (or the most authoritative source reachable from this environment), not from a
third party's summary, and say plainly which source was actually used if the official one is
unreachable. `14-02`'s "Tenant routing and credential ownership" section — the same question needs
answering again for WhatsApp's own credential shape, which is real API-provider-specific detail, not
assumed to be identical to MAX/Telegram/VK's own answer. `docs/architecture/resilience.md`'s
outbound-webhook treatment, reused unchanged through `14-01`'s port, exactly as every other adapter
already does.

## What is already known, stated so this item does not have to re-derive it

WhatsApp's Business Platform (Meta's own Cloud API, the one `14-05`'s legal-review section names) is
webhook-based for inbound messages, similar in shape to VK's Callback API — verify the exact
confirmation handshake and payload shape from Meta's own current documentation rather than assuming
VK's shape transfers, the same caution `14-08`'s own file gives about MAX's shape not transferring to
VK unchanged. Meta's own API generally requires message **templates**, pre-approved by Meta, for any
message sent outside a 24-hour customer-service window opened by the visitor's own inbound message —
this is a real constraint on the *outbound* side this item's adapter has to respect (a reply inside the
24-hour window is free-form; a reply after it must be a template), unlike every channel this project
has built so far, none of which had a time-boxed free-form window. State whether the target customer's
own use case (answering a visitor who just messaged) ever needs to send outside that window before
building template support — it may not, and building unused template machinery would be exactly the
premature generalization `CLAUDE.md` warns against.

## Scope

- A `ChannelKind.WhatsApp` value and a concrete `IInboundChannelAdapter` implementation for the Cloud
  API's webhook shape.
- Outbound reply delivery via the Cloud API's own send-message endpoint, wrapped in the same resilience
  pipeline every other channel adapter already uses, respecting the 24-hour free-form window found
  above (or naming, if the target use case never needs it, why template support is out of scope for
  this item specifically).
- Tenant routing and credential ownership, decided explicitly before code — same discipline `14-02`/
  `14-07`/`14-08` each already followed for their own channel's actual constraints.
- Console-facing connect/disconnect endpoints, matching `TelegramChannelEndpoints.cs`'s/
  `VkChannelEndpoints.cs`'s own shape.

## Out of scope

- Anything beyond a business account's own direct customer messages — WhatsApp catalogs, WhatsApp Pay,
  or any commerce-platform feature Meta's own API exposes beyond messaging.
- Message templates, if the investigation above finds the target use case never needs an outside-window
  send — named as a real, explicit scope cut, not a silent omission.
- A resolved legal position. `0010` accepted the risk of proceeding without one; this item does not
  retroactively manufacture legal clearance by existing.

## Done when

- [ ] A real message sent to a real WhatsApp Business number reaches an operator through the same
      console queue a widget conversation already does.
- [ ] A console reply reaches the same WhatsApp conversation back, honoring the 24-hour free-form
      window constraint (or the item records why that constraint does not apply to this build).
- [ ] Tenant routing and credential ownership are decided and recorded, the same way `14-02`'s own
      backlog file records its equivalent decision.
- [ ] Live verification against a real WhatsApp Business account and a real message — if no such
      account exists in the environment this item is built in, say so plainly (the same honest gap
      `14-08`'s own file names for VK) rather than claiming it.

## Open questions

Whether template-message support is in scope depends on the investigation this item's own "What is
already known" section calls for — resolve before writing the outbound send path, not after.
