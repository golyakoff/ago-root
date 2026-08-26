# AGO Inbox: external channel identity and the inbound channel port

- **Stage**: 14
- **Status**: done (2026-08-26) — see Decisions below and `adr/0055`
- **Depends on**: nothing new architecturally — `ago-chat` only, extends `Ago.Chat.Domain`/
  `Application`/`Infrastructure.Postgres` in place, no new repository (`adr/0027`: AGO Inbox is not a
  third product)

## Goal

AGO Chat's domain gains a real concept it has never needed until now: which external identifier (a
Telegram chat id, a MAX user id, a phone number for SMS) corresponds to which `Visitor`/`Conversation`.
A new port, `IInboundChannelAdapter` (or the equivalent name once implemented), gives every concrete
channel (`14-02`'s MAX adapter, `14-03`'s SMS adapter, and whichever of `14-05`'s candidates eventually
ship) one shape to implement, wrapped in `Ago.Platform.Resilience`'s existing timeout/retry/breaker/
bulkhead mechanism for its own outbound API calls (sending a reply back through the channel). This item
builds the concept and the port; it ships no working channel by itself.

## Context to read first

`docs/architecture/clean-architecture.md`'s Domain rules — a `ChannelIdentity` (or similarly named)
value object/entity belongs in `Ago.Chat.Domain`, since it is a fact about a conversation's own
identity, not infrastructure; the mapping from a channel-specific raw identifier to this concept is
where the actual design work is. `docs/architecture/resilience.md`'s "Where each boundary is" table —
an outbound call to any of these channel providers is exactly the kind of "boundary with something that
can fail independently of us" this doc already has a place for; this item's job is stating explicitly
which existing pattern (timeout, retry, circuit breaker per provider, bulkhead) applies to a channel
provider's own API, not inventing a new resilience concept. `docs/adr/0006-broker-abstraction.md`'s own
"largest common denominator that does not lie" reasoning — the same discipline applies to
`IInboundChannelAdapter`: the port must not leak MAX's or Telegram's own API shape above the
Infrastructure boundary, the same way `IEventPublisher` does not leak RabbitMQ exchanges. `docs/
architecture/vision.md`'s Actors table — `Visitor` today is identified by "a signed cookie/localStorage
token scoped to one site"; this item is the first time a `Visitor` can also be identified by an external
channel's own id, and the response should state explicitly how the two identity mechanisms coexist
(most likely: a `Visitor` row gains an optional set of linked `ChannelIdentity` rows, one per channel it
has ever been reached through, rather than replacing the existing token-based identity).

## Scope

- Domain: a new `ChannelIdentity` concept (`ChannelKind` enum — `Max`, `Sms`, `Telegram`, `WhatsApp` —
  plus the channel-specific raw identifier), associated with a `Visitor`/`Conversation` the same way
  `Site` already scopes every other piece of data. State explicitly, in the response, whether this is
  its own aggregate/table or a value object embedded on `Visitor` — the deciding factor is whether a
  `Visitor` can hold more than one simultaneously (plausible: the same person messaging via both MAX and
  SMS) and whether history needs to survive a channel being unlinked, both of which argue for its own
  table with a foreign key to `Visitor`, not an embedded value object.
- `IInboundChannelAdapter` (`Ago.Chat.Application.Abstractions` — product-specific, since it is shaped
  around `Visitor`/`Conversation`, unlike the generic technical ports in `Ago.Platform.Abstractions`):
  a shape for receiving an inbound message (however each channel actually delivers it — webhook,
  long-poll, whatever the concrete adapter's own provider requires, hidden below this port) and for
  sending an outbound reply back through the same channel, wrapped in `Ago.Platform.Resilience`'s
  existing policies (this item wires the wrapping mechanism; `14-02`/`14-03` are the first real callers
  that prove it against a real provider).
- A generic `ChannelMessageReceivedHandler` (or equivalent) that maps an inbound channel message to
  AGO Chat's own `SendVisitorMessage` use case — resolving or creating the `Visitor`/`Conversation` via
  the `ChannelIdentity` lookup, then reusing the exact same pipeline (`4-05`'s `ChannelMessagePipeline`,
  ordering, batching) every widget-originated message already goes through. This is the concrete
  argument for "AGO Inbox is not a third product": a channel message becomes an ordinary AGO Chat
  message the moment it is mapped, with no parallel pipeline.
- Migration: the new `ChannelIdentity` table/columns, additive and reversible (`data-model.md`'s
  migration rules, unchanged).

## Out of scope

- Any concrete channel adapter — `14-02` (MAX), `14-03` (SMS), `14-05` (Telegram/WhatsApp, blocked).
- Outbound-only sending without a matching inbound path (e.g. a notification-only channel) — nothing in
  the product spec asks for one; this port is shaped for genuine two-way conversation.
- Reusing this port for AGO Calendar's own `ISmsSender` (`20-05`) — that port is outbound-only, fixed-
  template, platform-shaped (`Ago.Platform.Abstractions`); this item's port is bidirectional, arbitrary-
  conversation, product-shaped (`Ago.Chat.Application.Abstractions`). State this contrast explicitly
  once both exist, so a later session does not conflate the two or try to force one to implement the
  other.

## Done when

- [x] `Ago.Chat.Domain.Tests`: a `Visitor` can be resolved from a `ChannelIdentity`, and a repeated
      message from the same external identifier resolves to the same `Visitor`/`Conversation`, not a
      new one each time.
      *Split across two levels, deliberately: `ChannelIdentityTests` covers the aggregate (a link binds
      the visitor it was given; one visitor may hold several identities), and the resolution behaviour
      itself is `Ago.Chat.Application.Tests.ReceiveChannelMessageHandlerTests` —
      `SecondMessageFromTheSameAddress_ResolvesToTheSameVisitorAndConversation` — because "resolves to
      the same conversation" is a statement about the use case, not about the entity. Domain alone
      could not have proved it.*
- [x] `Ago.Chat.Architecture.Tests`: `IInboundChannelAdapter` lives in `Application.Abstractions`, no
      channel-specific type (a MAX API DTO, a Telegram `Update`) appears above the Infrastructure
      boundary. *`ChannelPortTests`, five rules — placement, no provider vocabulary above
      Infrastructure, `ChannelKind` stays a plain enum (the one deliberate exception), the inbound
      command carries no provider timestamp, and Application never references the resilience machinery
      that wraps its ports.*
- [x] A fake channel adapter (test-only, logs instead of calling a real provider) proves the mapping end
      to end: a fake inbound message reaches `SendVisitorMessage`'s own pipeline and is persisted/
      delivered exactly like a widget message would be.
      *`ReceiveChannelMessageHandlerTests` drives the real `StartConversationHandler` and
      `SendVisitorMessageHandler` over a pipeline fake that actually applies the write, so the message
      lands on the real `Conversation` aggregate with a real sequence.
      **Not** proven end to end through the real `ChannelMessagePipeline`, `MessageBatchWriter`, outbox
      and RabbitMQ — there is no host route or consumer to drive one from yet, and inventing one would
      have been `14-02`'s work done badly. `FakeInboundChannelAdapter` covers the outbound half.*
- [x] `docs/architecture/data-model.md` gains the new table/columns; `docs/architecture/resilience.md`
      gains a row (or a note under the existing table) naming "outbound channel provider APIs" as a
      boundary this mechanism now covers. *Both, plus a `personal-data.md` row that this change made
      necessary: `channel_identities.external_address` is a phone number for SMS, which is the first
      structured direct identifier in AGO Chat's own database.*

## Decisions this item made (full reasoning in `adr/0055`)

- **`ChannelIdentity` is its own aggregate and table**, not a value object on `Visitor` — one person can
  hold several at once, and the link is worth keeping after it is unlinked.
- **A widget visitor and an external-channel sender are two `Visitor` rows**, and nothing merges them by
  inference. Many-to-one is representable so a future *verified* link costs one `UPDATE` and no
  migration; no code writes that edge today, and `ChannelIdentity` ships with no re-link method.
- **The port's methods are outbound-only.** Receiving already points inwards, so it is a command
  (`ReceiveChannelMessage`), not a method — a `ParseInbound(bytes, headers)` would have encoded "a
  channel arrives over HTTP", which is false for a long-polling adapter. The name
  `IInboundChannelAdapter` is kept from this item anyway; the mismatch is recorded rather than hidden.
- **Idempotency adds no new mechanism**: the provider's message id maps by a pure function to the
  `ClientMessageId` that `5-07`'s `Conversation.AddMessage` already deduplicates on.
- **No provider timestamp exists anywhere in the contract** — the refusal is structural, and an arch
  test fails if a field is added.
- **Canonicalising the raw address is the adapter's job**, not the Domain's; case is preserved.
- **Resilience is keyed per channel, not per tenant** — the deliberate contrast with `6-05`'s per-site
  bulkhead, since a channel provider is shared by every tenant on it.
- **The handler composes `StartConversationHandler` + `SendVisitorMessageHandler`** — the first
  handler-calls-handler here, taken so that channel messages cannot bypass the rate limits and body
  validation a widget message goes through.
- Use case named `ReceiveChannelMessage`, not this item's `ChannelMessageReceived`, to match the
  verb-first `UseCases/` convention (`SendMessage`, `StartConversation`, `RecordUnread`).

## Open questions

None — the concept and port shape follow directly from the product spec's own description of what an
external channel identity needs to answer ("which external chat-id/phone-number corresponds to which
visitor/conversation"); the aggregate-vs-value-object storage question is a real decision this item
makes and records, not a blocking one.

**Carried into `14-02`** (not blocking this item, but the first adapter is where each is settled):
the resilience thresholds are unmeasured starting points; the terminal-versus-transient split in
`ChannelSendOutcome` has never met a real provider API; and one human appearing as two visitors in one
console has no operator-facing merge yet.
