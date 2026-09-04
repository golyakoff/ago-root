# an outbound channel message records whether it left, and the tenant can find out

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing
- **Decision**: `docs/design/decisions.md` §9, including its 2026-09-04 amendment

## Goal

When an operator's reply leaves this system over a channel, the answer the provider gave — accepted,
rejected, failed — is recorded, and a tenant whose customer says they got nothing can find out
whether we sent it, without reading a log or asking support (`flows.md` 4.5).

What breaks without it, in §9's words: an SMS bounces — wrong number, blocklist, no credit at the
gateway — the operator sees their reply in the thread, the conversation looks answered, and the
customer got nothing. Nobody finds out, because a customer who was not answered does not complain,
they leave.

## The fact is already in hand and is thrown away

`DeliverChannelMessageHandler` calls the adapter's send, receives a `ChannelSendOutcome`, converts it
to `DeliverChannelMessageOutcome` and returns it to `ChannelMessageDeliveryConsumer`, which uses it
only to decide whether to ack the broker. Nothing is written. That is the whole gap.

## Its justification changed and the decision survived — build it on the right one

§9's amendment, and it matters because the wrong justification would pull the wrong scope in. This
was originally argued from reminders — *"we are about to send 'confirm you are coming'"*. **That
argument does not hold.** The mechanism attaches to `DeliverChannelMessageHandler`, which relays an
**operator's reply** into a linked channel; a reminder is a system-initiated send whose only port,
`IPhoneVerificationSender`, deliberately throws instead of returning an outcome, and there is no
channel to send it on (`14-03` is *won't build*; `UnconfiguredPhoneVerificationSender` is what is
registered).

The recording stands on its own value, which is enough. **Do not extend it to system-initiated
sends** on the strength of the superseded argument.

## The stated limit, which goes on the screen and not only in this file

§9: this answers `flows.md` 4.5 for **channel** conversations and **not** for widget ones, which are
the majority. Better a partial answer where we hold the fact than an invented one everywhere. The
widget half is possible and deliberately not built — presence already exists (polled every 10s), and
resume-by-sequence is what recovered all ten lost messages when realtime was broken in `5-10`. A
receipt would need a new protocol message plus a write per message on the hottest, freshly
repartitioned table, for a case that is rare and self-healing.

## Context to read first

- `docs/design/decisions.md` §9 in full
- `docs/design/flows.md` 2.2 and 4.5; `docs/design/ui-inventory.md` §3.3 ("No per-message delivery
  state" — the console shows a timestamp and nothing else) and §9.3 (the widget's per-bubble status
  line, which is a *send* status, not a delivery one)
- `docs/backlog/6-03-webhook-registration-and-delivery-history.md`,
  `Ago.Chat.Application/Abstractions/IWebhookDeliveryRepository.cs`, `WebhookDeliveryPage.cs` and
  `Ago.Chat.Worker/WebhookDeliveryPruneJob.cs` — the precedent §9 names, down to the prune job
- `docs/architecture/messaging.md` — at-least-once, and why a redelivery must not write a second row
- `docs/architecture/resilience.md` — `OutboundChannelMessage.MessageId` as the provider's own
  idempotency key
- `docs/architecture/data-model.md` — `messages` is partitioned by tenant hash (`adr/0087`); this
  table is not and does not need to be

## Scope

- A `channel_deliveries` table: site, conversation, message id, channel kind, outcome, provider
  detail, attempted at — and either the address or a reference to the `ChannelIdentity` row.
  **Decide and say which**: one of those choices puts a phone number in a second table and the other
  makes the record depend on a row that can be unlinked.
- `DeliverChannelMessageHandler` writes the row. `ChannelMessageDeliveryConsumer` keeps deciding ack
  versus retry exactly as it does — the record is not the retry mechanism.
- **Idempotent.** A redelivered `MessageAccepted` re-sends with the same
  `OutboundChannelMessage.MessageId`; the record collapses on that key rather than growing a row per
  redelivery.
- The read: per conversation and per message, gated the same way conversation reads are.
- `ago-console`: the conversation thread shows a delivery state on operator messages **in channel
  conversations only**, worded for a non-engineer. `flows.md` 4.5: *"must not be made to interpret a
  delivery status that means something only to an engineer."*
- The screen says which conversations this covers and which it does not, so a tenant does not read
  the absence of a state on a widget conversation as a failure.
- Retention: its own window and its own prune job. `personal-data.md` gains the row.

## Out of scope

- **Widget delivery receipts.** §9 rules them out with reasons; a "small extra" here would be the
  per-message write on the hottest table that the decision declined.
- Read receipts. §9: a third thing again, with privacy weight the visitor may not want.
- **Delivery outcomes for system-initiated sends** — phone-verification codes today, reminders if a
  channel ever exists. Those go through `IPhoneVerificationSender`, a different port that
  deliberately throws rather than returning an outcome, and §9's amendment removes the argument that
  used to drag them in.
- Retrying a failed delivery automatically. A recorded failure is information; deciding what to do
  about it is not this item.

## Done when

- [ ] A refused send writes a row saying refused, with the provider's own detail, and the operator's
      thread shows it.
- [ ] A delivered send writes a row saying delivered.
- [ ] A redelivered broker message does not write a second row.
- [ ] A conversation with no linked channel writes nothing at all — the no-linked-channel outcome is
      not a delivery failure and must not be reported as one.
- [ ] A widget conversation shows no delivery state, and the screen says why.
- [ ] Another tenant's delivery records cannot be read.
- [ ] The prune job removes rows past the window; a test proves it.
- [ ] `data-model.md`, `messaging.md` and `personal-data.md` carry the table.

## Open questions

None.
