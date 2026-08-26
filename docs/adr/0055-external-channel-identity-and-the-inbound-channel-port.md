# ADR-0055: External channel identity, and the shape of the inbound channel port

- **Status**: Accepted
- **Date**: 2026-08-26
- **Stage**: 14 (`backlog/14-01-external-channel-identity-and-inbound-port.md`)

## Context

AGO Inbox (`adr/0027`: an extension of AGO Chat, not a third product) lets a shop be reached over
channels it does not own — MAX, SMS, later Telegram and WhatsApp. `14-01` builds the concept and the
seam; `14-02` and `14-03` build the first two real adapters. Nothing about a specific provider is
decided here, and that is deliberate: this item's success condition is that a reviewer can describe
how a second channel plugs in without editing anything written for the first.

Four forces shape it.

**AGO Chat has exactly one way of knowing who a person is, and it does not generalise.** A `Visitor`
is a browser holding a signed token this system issued and validates but never stores (`adr/0034`,
`adr/0048`; the row itself is `id`, `site_id`, `first_seen_at`, `last_seen_at` and nothing else). An
SMS sender is a phone number a carrier attests to. A MAX user is an opaque id that provider owns.
These are different *kinds* of claim, established by different parties, with different strengths —
and this is the first time more than one of them exists at once.

**Inbound delivery from any external channel is at-least-once** (CLAUDE.md rule 5), and it is
at-least-once in a way webhooks-out are not: we do not control the retry policy, we cannot ask the
provider to stop, and a redelivery arriving hours later is normal. Duplication can happen at three
levels — a second visitor, a second conversation, a second message — and each has a different
symptom, the first two being the ones an operator actually sees.

**Every provider stamps its deliveries with a time, and none of those clocks are ours.** CLAUDE.md
rules 6 and 11 already say per-conversation order is the server-assigned `sequence` and never a clock;
Stage 14 is the first time an externally-supplied timestamp gets anywhere near the write path, so it
is the first time that rule can actually be broken by accident.

**Resilience has a settled shape here already.** `resilience.md`'s table and `6-05`'s webhook
dispatcher establish what a boundary with an independently-failing third party gets: timeout, bounded
retry with backoff, circuit breaker, bulkhead, all built from `Ago.Platform.Resilience` and hidden
behind the port. An outbound call to a channel provider is that same kind of boundary. Nothing new is
needed — but the wiring has to exist before the first adapter, or each adapter will grow its own.

## Decision

### 1. `ChannelIdentity` is its own aggregate and its own table, not a value object on `Visitor`

`channel_identities` — `id`, `site_id`, `kind`, `external_address`, `visitor_id`, `first_seen_at`,
`last_seen_at` — with a unique index on `(site_id, kind, external_address)`.

Three facts decide it. One human can hold several identities *at once* (the same person messaging by
MAX and by SMS), which an embedded value object cannot express without becoming a collection anyway.
The link has to survive being unlinked, and a value object deleted from its parent leaves no trace.
And the write pattern is resolve-or-create keyed on columns that are not `Visitor`'s primary key, so
an embedded collection would make every inbound message load a whole visitor to reach data it does not
use, and would put two aggregates in one transaction for nothing.

### 2. A widget visitor and an external-channel sender are two `Visitor` rows — and stay that way unless something *proves* otherwise

This is the decision the whole item turns on, and it is a refusal rather than a mechanism.

Nothing in either signal proves the two are the same human. Merging them on a guess discloses one
channel's conversation history to whoever holds the other — a privacy failure in the direction that
actually harms someone, and one that cannot be undone by noticing later. So there is no merge, no
fuzzy match, no "same site, similar identifier" heuristic anywhere in this slice.

The model is deliberately asymmetric: **many-to-one is representable, and only ever created by
evidence.** `visitor_id` is a plain column, so several channel identities pointing at one visitor is
an ordinary row shape, and a future verified-link step (the person proves the number belongs to that
session) is one `UPDATE` and no migration. What does not exist is any code that would perform that
update on inference. `ChannelIdentity` therefore ships with no re-link method at all — a write path
with no caller is not built on speculation, the same standing rule `Conversation.MarkReadByOperator`'s
absent visitor-side twin already follows.

Made falsifiable in `Ago.Chat.Application.Tests`:
`AWidgetVisitorAndAnSmsSender_AreTwoVisitors_NotOne`, plus the same separation across channels and
across tenants.

### 3. The port's methods are outbound-only; the inbound half is a command

`IInboundChannelAdapter` (`Ago.Chat.Application.Abstractions`) declares `ChannelKind Kind` and
`Task<ChannelSendOutcome> SendAsync(OutboundChannelMessage, CancellationToken)`. That is all.

A port exists to invert a dependency — it is needed exactly where inner code must call outer code.
Sending a reply is that case: the application knows an operator answered and has no idea whether that
means an HTTPS POST or a carrier session. *Receiving* already points inwards: the adapter is the outer
thing, it is what a webhook or a long poll wakes, and it calls
`ReceiveChannelMessageHandler` with a `ReceiveChannelMessage` it built itself. Adding a
`ParseInbound(bytes, headers)` method for symmetry would have hard-coded "a channel arrives over
HTTP" — false for a long-polling adapter — and dragged a transport shape above the Infrastructure
boundary, which is the exact failure `adr/0006` warns about for `IEventPublisher` and RabbitMQ
exchanges. The inbound contract is a command rather than a method, and it is no less binding: it is
the only entry point a channel has.

The name `IInboundChannelAdapter` is kept from the backlog item even though the interface's methods
are outbound. It reads "the adapter for an inbound-capable channel", and renaming it would cost the
backlog item's own Done-when its literal referent for no gain. Recorded here because it is the kind of
mismatch a reviewer should be told about rather than left to notice.

`IInboundChannelAdapterRegistry` resolves an adapter by `ChannelKind`; the implementation refuses two
adapters claiming one channel at construction time, because silently picking one would route half a
tenant's replies through a provider nobody chose.

### 4. Idempotency reuses `5-07`'s existing mechanism; no new one was added

The provider's own message id is mapped, by a pure function, to the `ClientMessageId` that
`Conversation.AddMessage` already deduplicates on: a name-based UUID (RFC 9562 version 8) over
`{ChannelKind}` + U+001F + `{provider message id}`.

- **No second visitor** — the identity lookup finds the existing row (`ux_channel_identities_site_kind_address`
  is the storage backstop for two processes racing the first message from one number).
- **No second conversation** — `StartConversationHandler` resumes the visitor's active one, unchanged.
- **No second message** — `AddMessage` returns the original, burns no sequence, raises no second
  `MessageAdded`; the `(conversation_id, client_message_id)` unique index backs it up across processes.

A hash rather than a `channel_message_ids` ledger: a ledger would be a second idempotency store to
keep consistent with the first, and would have to be written in the message's own transaction to be
worth anything. The channel is mixed into the digest because a bare integer id is common across
providers and a collision here is not a duplicate — it is one tenant's message silently swallowed as
another's retry.

Version 8 rather than 5, because version 5 is defined as SHA-1 over a namespace UUID and this is
SHA-256 over a string; stamping it 5 would claim a construction it does not use.

### 5. No provider timestamp crosses the boundary, in either direction

`ReceiveChannelMessage` has no timestamp field and `OutboundChannelMessage` has none either. A value
that is accepted and then silently dropped is worse than one that is refused, so the refusal is
structural: there is no slot to put it in, `PendingMessage` has no slot for it either, and
`ChannelPortTests.ReceiveChannelMessage_CarriesNoTimestamp` fails if anyone adds one. An item that
genuinely needs "the provider says it was sent at…" for *display* should add it under a name that says
so, and should have to change that test deliberately.

### 6. Canonicalising the raw address is the adapter's job, not the Domain's

`ExternalChannelAddress` validates only what is true of every channel — non-empty, trimmed, bounded at
256 characters. It does no E.164 rewriting, no numeric parsing, and no case folding. Format rules
belong to one provider, and a Domain type that guessed at them would be wrong for the first provider
that hands us a national-format number — where being wrong means two rows for one human. Case is
preserved because folding it is safe for a phone number and unsafe for an opaque provider-issued id,
where two spellings can be two people; an adapter whose provider is case-insensitive folds case
itself.

### 7. The resilience pipeline is keyed per channel, not per tenant

`ChannelResiliencePipelines` caches one `ResiliencePipeline` per `ChannelKind`, and
`ResilientInboundChannelAdapter` decorates any adapter with it. Breaker outermost, then retry, then
timeout — inheriting `6-05`'s finding (made against a real hanging provider, not from reading Polly's
source) that a breaker inside a timeout never sees `TimeoutRejectedException` at all.

This is a deliberate contrast with `6-05`, which bulkheads per *site*. A webhook endpoint is chosen by
each tenant, so one tenant's dead CRM is one tenant's problem. A channel provider is chosen by us and
shared by every tenant on it, so per-tenant keys would give N breakers all watching one outage, each
needing its own `MinimumThroughput` before reacting — slower to open, no better isolated.

The port's contract carries the matching distinction: a **terminal** provider refusal (unknown number,
blocked recipient) returns `Delivered: false`, because retrying it would never help; a **transient**
fault is thrown, because throwing is what the pipeline acts on. An adapter that swallowed a timeout
into `Delivered: false` would silently disable every retry and breaker built around it.

### 8. `ReceiveChannelMessageHandler` composes two existing handlers

It calls `StartConversationHandler` and then `SendVisitorMessageHandler`. This is the first
handler-calls-handler in the codebase, and both alternatives are worse. Re-implementing
resolve-or-create-conversation plus enqueue would produce a second pipeline for channel messages —
precisely what this item exists to prevent, and the concrete content of "AGO Inbox is not a third
product". Calling `IMessagePipeline` directly would look tidier and would skip
`SendVisitorMessageHandler`'s per-visitor and per-site rate limits and its body validation — and an
SMS flood is exactly what those limits are for, on the one path an attacker does not need a browser
for.

The cost is a call graph one level deeper than anywhere else here, which is the same objection the
"no MediatR by default" note in `clean-architecture.md` raises. It is paid explicitly, in that
handler's own remarks.

### 9. Write order is visitor → identity → conversation → message, and the order is chosen for its crash windows

Four saves, not one transaction (data-model.md's one-aggregate-per-transaction rule; the same
visitor-then-conversation shape `StartConversationHandler` already had). A crash after the visitor and
before the identity leaves an orphan `visitors` row with no conversation and no messages — the
redelivery mints a fresh one and proceeds correctly, and an operator never sees it. A crash after the
identity is fully recoverable: the redelivery finds it and resumes the same visitor.

The order that looks more natural — conversation first, identity last — is the one that breaks. A
crash before the identity save would leave the redelivery unable to recognise the sender, so it would
mint a second visitor and a second conversation, and the operator would see one phone number as two
people. The identity row is written as early as the `visitors` foreign key allows.

## Consequences

**What gets easier.** A second channel is one class implementing one two-member interface, one DI
registration, and whatever wakes it. Nothing in Domain, Application, the pipeline, the outbox, the
fan-out or the console needs to know it exists — a channel message is an ordinary visitor message from
the moment it is mapped, so it inherits ordering, batching, unread counts, webhooks and realtime
delivery for free. Resilience is opt-out rather than opt-in: an adapter author writes a plain
"call the provider, translate the answer" class and gets the pipeline by composition at the root.

**What gets harder, and what we now maintain.**

- **One person can appear as several visitors in one console**, with their history split. That is the
  price of decision 2, and it is the right price, but it is a real product wart and the operator-facing
  answer to it (a manual "these are the same person" merge, verified) is unbuilt work that `14-02`'s
  first real users will ask for. The schema is ready for it; nothing else is.
- **Four saves, not one transaction.** The crash windows above are bounded and analysed, not absent.
- **The resilience thresholds are guesses.** They are starting points modelled on `6-05`'s, which were
  at least exercised against a real hanging endpoint; nothing here has been measured, and CLAUDE.md
  rule 7 means they stay guesses until `14-02` has a provider to measure against.
- **The port is unproven against a real provider.** Everything below `SendAsync` is exercised only by
  a stub. `14-02` is the first item that can find out whether the two-state
  terminal-versus-transient contract survives contact with a real API — the most likely place this
  design is wrong.
- **`ExternalChannelAddress` pushes canonicalisation onto every adapter**, so two adapters can
  disagree about it. That is the correct place for the knowledge and the wrong place for
  consistency; if a third adapter repeats the same normalisation, that is the moment to extract it —
  into Infrastructure, not Domain.

## Alternatives considered

**Channel identity as nullable columns on `visitors`.** Cheapest on day one, and cannot represent one
person on two channels at all — the case the product spec explicitly anticipates.

**One `Visitor` per human, merged across channels.** What a customer would say they want. Rejected on
the evidence question: nothing available proves two identities are one person, and the failure mode of
guessing is disclosing someone's support history to a stranger. Deferred behind a verification step
that does not exist yet, at zero schema cost.

**A symmetric port with a `ParseInbound` method.** Rejected in §3: it would encode a transport
assumption the port exists to avoid, and it inverts a dependency that already points the right way.

**A dedicated `channel_message_ids` idempotency ledger.** Rejected in §4: a second store to reconcile,
where a pure function needs none.

**Carrying the provider's timestamp as an unused field.** Rejected in §5: accepted-and-dropped is
worse than refused, and the refusal is only enforceable if there is nowhere to put the value.

**Reusing AGO Calendar's `20-05` `ISmsSender`** (or making one implement the other). Rejected, and
worth stating explicitly because the two will look similar in a listing: `ISmsSender` is outbound-only,
fixed-template, and genuinely platform-shaped (`Ago.Platform.Abstractions`); this port is
bidirectional, arbitrary-conversation, and product-shaped, because it is defined in terms of
AGO Chat's own `Visitor` and `Conversation`. `clean-architecture.md`'s platform test — "can it be
described without naming chat, visitors, or operators?" — fails on this one in its first sentence.
Neither should ever implement the other.

**A `Widget` member on `ChannelKind`.** Rejected: it would suggest the widget is one channel among
four, when the real shape is one built-in identity mechanism plus N external ones that link into it. A
widget visitor has no `channel_identities` row and never will.

**Putting the channel port or `ChannelIdentity` in `Ago.Platform.*`.** Fails the qualifying rules in
`clean-architecture.md` on the first test — it contains a domain concept — and `adr/0027` is the
worked precedent for rejecting a promotion that looks tempting even with a real second product in
hand.
