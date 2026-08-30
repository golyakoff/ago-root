# Verified channel-identity linking, unlinking, and a preferred reply channel

- **Status**: Accepted
- **Date**: 2026-08-30

## Context

`14-01`/`adr/0055` gave one `Visitor` the ability to hold more than one `ChannelIdentity` row
structurally (`ChannelIdentity.cs`'s own remarks: "one human can hold several at once - the same
person messaging a shop by MAX and by SMS is two rows against one `VisitorId`"), but deliberately built
no way to *create* that link. Today's only write path (`ChannelIdentity.Link`, called from
`ReceiveChannelMessageHandler`) always mints a brand-new `Visitor` the first time an address is seen -
exact-match lookup on `(site, kind, address)` only, no fuzzy matching, no inference. `adr/0055` names
the reason explicitly: merging on a guess would disclose one channel's conversation history to whoever
holds the other, and named this the one failure direction that cannot be undone. It left the door open
for exactly one thing to close this gap later: "some future, deliberate, *verified* linking step."

The author's own concrete scenario is the everyday case that step needs to serve: an operator is
mid-conversation (say, over the widget) and the visitor mentions a Telegram id, wanting future replies
to go there. Today AGO Chat has no way to act on that at all - not to link the identity, not to prefer
it for delivery, and (per `personal-data.md`) not even to record it as a fact about the visitor if the
channel in question has no adapter yet.

Two more gaps surfaced while investigating this:

- **Two different, never-reconciled rules already answer "the channel" for a visitor.** `18-08`'s
  analytics read (`OperatorAnalyticsReadStore`) picks the identity with the *earliest* `FirstSeenAt`;
  `DeliverChannelMessageHandler` picks the one with the *latest* `LastSeenAt`. Neither is wrong for its
  own purpose, but nothing today lets an operator override either, and the two disagree by construction
  the moment a visitor has more than one identity - which this ADR is what finally makes possible.
- **No structured contact information is ever captured from what a visitor types.** `messages.body` is
  free text; a phone number or email a visitor types mid-conversation is never extracted, and for a
  channel this system has no adapter for at all (SMS/email, both still unbuilt - `14-03`/`14-09`), there
  is no *routable* identity to create even if verification were solved.

## Decision

### 1. Verified linking is evidence-based, and the evidence is an inbound message - never a proactive send

Most channel providers this project has integrated (confirmed for Telegram; the same shape is expected
for MAX/VK/WhatsApp's own 24-hour-window rule already documented in `14-10`) do not let a bot message an
address that has never messaged it first. So the verification a new link needs cannot be "AGO Chat sends
a code to the new channel" - it has to be **the visitor sending a short-lived code *from* the new
channel**, which both proves control of that address and satisfies the provider's own "visitor-initiated
contact" requirement for free.

Mechanically: a pending link request (site, target `VisitorId`, requested `ChannelKind`, a short code,
an expiry, who requested it) is created, and `ReceiveChannelMessageHandler` gains one new branch ahead
of its existing "no matching identity -> mint a new visitor" path: if the inbound address has no
existing `ChannelIdentity` *and* the message body is exactly a live pending code for this site and
channel kind, call `ChannelIdentity.Link` with the **pending request's own `VisitorId`** instead of a
freshly-minted one, and consume the code. Every other inbound message keeps behaving exactly as today.

### 2. Two symmetric ways to start a pending request

- **Operator-initiated**, from the console: generates the code, and the operator relays it to the
  visitor as ordinary text in the conversation already open ("message our Telegram bot @ShopBot with:
  4821").
- **Visitor-initiated**, from within the channel they are already using: a chat-native command,
  `/linkidentity <target-channel>`, following the shared syntax/matching rule
  `docs/conventions/text-commands.md` now states once for every command this codebase has - exact,
  case-insensitive, whole-first-token match, optional leading slash on input - **not the same class as
  `TriggerCommandMatcher`**, since that class is bound to `IEnabledModuleReadStore`/`ModuleKey` and
  answers "does this open a module task," a different question from "does this open a link request."
  This is Chat's own small, closed command vocabulary, not module-routed - added to the reserved-word
  list that convention document describes, so no site can ever register a module trigger that collides
  with it. The system replies in that
  same conversation with the code and instructions.

Either path produces the identical pending-request row and the identical confirmation branch in
`ReceiveChannelMessageHandler` - initiation is a console/composer convenience, not a second mechanism.
A composer quick-insert button (the same convention `Composer`'s own `insertCannedResponse` already
establishes for `18-03`'s canned responses) drops the exact instruction text into the operator's reply,
so relaying a code never means retyping it by hand.

### 3. A claimed address already owned by a *different* visitor is refused, not merged

The unique index on `(site_id, kind, external_address)` means a pending request's confirmation branch
can find the address already claimed. That is the real cross-visitor merge case `adr/0055` also
anticipated and did not solve - two genuinely separate histories under one real person. This ADR does
not solve it either: the confirmation is refused outright, and the operator is told plainly that the
address already belongs to a different visitor. A real merge - reassigning conversations, reconciling
retention/erasure across two histories - is a materially bigger, riskier feature and stays a candidate
for its own future ADR, not an extension bolted onto this one.

### 4. Unlinking is a soft state, gated by a new permission the tenant grants through the existing role system

`ChannelIdentity`'s own remarks already named the shape before this ADR existed: "the link must survive
being unlinked: 'this number stopped being this visitor' is a fact worth keeping." So unlinking does
not delete the row - it marks it inactive (an `Active` flag plus `UnlinkedAt`, the identical shape
`ChannelCredential.Revoke` already uses elsewhere in this same domain), and an inactive identity is
excluded from routing/preference/lookup but stays in the record.

Gated by a new `Permission.ChannelIdentityUnlink` - granted to **no role by default**, the same
`resource:action`, granular-by-design vocabulary `adr/0016` already uses throughout (`Permission.cs`'s
own remarks on why `ConversationClose` is separate from `ConversationAssign`). No new grant mechanism is
needed: `Role`/`OperatorRole` are already real, DB-backed, per-site tables with a `Permissions` list
column (`PermissionChecker.cs`), so a tenant grants this by including the permission in any role
definition they control - exactly the "additional permission the tenant grants" the author asked for,
built entirely from what already exists. The site owner's own unconditional ability to unlink is
expected to reach through whatever authorization path already lets an owner act outside the
operator/role system (the owner-scoped endpoints this codebase already has) - the exact mechanism is
confirmed at implementation time, not asserted here.

### 5. A preferred reply channel lives on `Visitor`, not `Conversation`

The author's own framing - "a wish to communicate preferentially through Telegram," not "for this one
conversation" - is a durable, cross-conversation fact about the person, not a one-off choice, so it is
scoped like one: a nullable `PreferredChannelIdentityId` on `Visitor`. `DeliverChannelMessageHandler`
checks it first (only when the referenced identity is still `Active`); unset, or pointing at an identity
that has since been unlinked, falls back to today's existing `FindMostRecentForVisitorAsync` behaviour
unchanged. Setting it is only possible among a visitor's own currently-linked, active identities - never
an arbitrary address - so this cannot be used to route to something never verified.

This ADR does **not** change `OperatorAnalyticsReadStore`'s own earliest-identity tiebreak for channel
attribution. Reconciling that with a preferred channel, once one can exist, is a real, separate follow-up
worth doing - named here so it is not silently rediscovered later, not bundled into this ADR's own scope.

### 6. Unverified contact details stay a separate, simpler concept

For a channel this system has no adapter for at all (a phone number or email typed in chat, while
`14-03`/`14-09` remain unbuilt), or for any fact an operator simply wants to note without going through
verification, a new, small, explicitly-unverified concept (`VisitorContactDetail`: kind, value, who
recorded it, when) is **not** a `ChannelIdentity`. The distinction is trust, stated plainly rather than
blurred: a `ChannelIdentity` is only ever created by evidence (a real inbound message, or now a real
confirmation code); a contact detail is only ever an operator's own claim, never routable, never used
for delivery, never subject to the unique-address constraint. Mixing the two would let an unverified,
hand-typed value silently become a real send target the moment a matching channel is later built.

## Consequences

- `ChannelIdentity` gains its first mutation beyond `LastSeenAt`: an `Active`/`UnlinkedAt` pair,
  written only by the new unlink use case. Every existing reader (`FindMostRecentForVisitorAsync`,
  `OperatorAnalyticsReadStore`'s own channel tiebreak, the console) needs to filter to `Active` -
  named explicitly so it is caught at implementation time, not discovered as a bug once the first
  identity is ever unlinked.
- A new, small, closed command vocabulary now exists in `Ago.Chat.*` alongside the module-trigger one -
  the shared semantics both are held to (syntax, matching, and the registration-time collision guard
  between the two) are written down once in `docs/conventions/text-commands.md`, not re-derived per
  command.
- No schema change to `messages` or `conversations` - the pending-link-request table is new and small,
  and `ChannelIdentity`'s own `VisitorId` column already needed no change for this, exactly as its own
  remarks predicted three items ago.

## Alternatives considered

- **Proactive verification send** (AGO Chat messages the new channel first with a code) - rejected:
  most providers this project has integrated refuse to let a bot message an address it has never heard
  from, so this would not work for a genuinely new identity in the common case.
- **Fuzzy/automatic matching** (same phone number appearing in two channels implies one visitor) -
  rejected for the identical reason `adr/0055` already gives: it is a privacy failure in the one
  direction that cannot be undone.
- **Preferred channel on `Conversation`** - considered and rejected in favour of `Visitor`: the
  author's own framing is durable, not per-conversation; a future item can still add a per-conversation
  override on top of this without changing the `Visitor`-level default.
