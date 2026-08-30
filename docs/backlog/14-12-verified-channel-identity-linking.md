# Verified channel-identity linking and unlinking

- **Stage**: 14
- **Status**: done (`ago-chat#135`, `ago-console#69`, merged 2026-08-30)
- **Depends on**: `adr/0079-verified-channel-identity-linking-and-a-preferred-reply-channel.md` - the
  full "why this shape" statement; `14-01-external-channel-identity-and-inbound-port.md` (done) - the
  `ChannelIdentity` aggregate this item adds the first real mutation to since it shipped

## Goal

An operator who learns a visitor's identity on another channel mid-conversation (a Telegram id, a MAX
id) can link it to the same visitor - verified by the visitor themselves, never by inference - and can
undo a mistaken link. A visitor can also start the same process themselves, from inside the channel
they are already using.

## What this item does not solve, stated before scoping the rest

If the claimed address already belongs to a *different* existing visitor, this item refuses the link
outright rather than merging two histories - `adr/0079`'s own "Alternatives considered" section names
why that is a separate, harder problem. This item only ever creates a link where none existed before.

## Scope

- **Domain**: `ChannelIdentity` gains its first mutation beyond `LastSeenAt` - `Active` (bool, default
  `true`) and `UnlinkedAt` (nullable), written by a new `Unlink(now)` method, the same shape
  `ChannelCredential.Revoke` already uses. Every existing reader of `ChannelIdentity`
  (`FindMostRecentForVisitorAsync`, `OperatorAnalyticsReadStore`'s channel tiebreak) is updated to filter
  to `Active` - proven by a test seeding an unlinked identity and confirming it is excluded from both.
- A new, small aggregate for a pending link request: site, target `VisitorId`, requested `ChannelKind`,
  a short code, `ExpiresAt`, who requested it (nullable `OperatorId` - `null` when visitor-initiated).
  Short-lived; expired rows are excluded from matching, not necessarily swept by a job in this item (say
  which you chose).
- `ReceiveChannelMessageHandler` gains one new branch, ahead of its existing "no matching identity ->
  mint a new visitor" path: an inbound address with no existing `ChannelIdentity`, whose message body
  exactly matches a live pending code for this site and channel kind, calls `ChannelIdentity.Link` with
  the pending request's own `VisitorId` and consumes the code. Every other inbound message is unchanged
  - proven by a test that the ordinary "no match -> new visitor" path still fires for a message that is
  not a valid code.
- **Console-initiated request**: an endpoint an operator calls from a conversation to generate a pending
  request for a given channel kind, gated on the same permission `ConversationSend` already requires
  (requesting a link is not more sensitive than replying). The console surfaces the code and
  instructions; a composer quick-insert (the same convention `Composer`'s own `insertCannedResponse`
  already establishes) drops the relay text into the reply.
- **Visitor-initiated request**: a small, closed command parser (not `TriggerCommandMatcher` - see
  `adr/0079` for why that class does not fit), following `docs/conventions/text-commands.md`'s own
  syntax/matching rule, recognizing `/linkidentity <channel-kind>` in an inbound message on an *existing*
  conversation, creating the identical pending-request row and replying in that conversation with the
  code and instructions for the target channel. `linkidentity` is added to the reserved-word list
  `EnableModuleForSite` checks a site's own trigger words against - proven by a test that registering
  a colliding trigger word is refused.
- **Collision handling**: the confirmation branch above, when the claimed address already has an active
  `ChannelIdentity` pointing at a different visitor, refuses - no link created, and (for the
  console-initiated path) the operator sees why. Proven by a test seeding a colliding identity and
  asserting no mutation happens.
- **Unlink endpoint**: gated on a new `Permission.ChannelIdentityUnlink`, granted to no role by default
  (`adr/0016`'s own granular-permission vocabulary). The site owner's own unconditional ability to
  unlink reaches through whatever authorization path already lets an owner act outside the
  operator/role system - confirm the exact existing mechanism before wiring this, do not assume.
- Console: a panel on `VisitorPanel` (beside `ConversationOutcomePanel`/`ConversationTagsPanel`/
  `ConversationNotesPanel` - the established "operator manages a small piece of state about this
  visitor" shape) listing the visitor's own active channel identities, a "link a channel" action that
  starts the console-initiated flow above, and an "unlink" action per identity, visible only when the
  operator holds the new permission (or is the owner).

## Out of scope

- Real cross-visitor merging - named and rejected above and in `adr/0079`.
- A background sweep job for expired pending requests, unless the implementation finds it is needed to
  keep the table from growing unboundedly - decide and record either way.
- Any channel this system has no adapter for (SMS/email) - this item's verification mechanism requires
  a real inbound message, which only an adapted channel can ever produce. See `14-14` for those.

## Done when

- [x] An operator can generate a pending link request from a conversation, relay the code, and the
      visitor confirming it from the new channel results in a real `ChannelIdentity` linked to the
      correct visitor - proven end to end through the real inbound handler chain.
- [x] A visitor can start the same process themselves with `/linkidentity <channel-kind>` from inside an
      existing conversation and receive the code/instructions in that same conversation, proven by a
      test.
- [x] A site attempting to register a module trigger word that collides with `linkidentity` (or any
      other reserved Chat-native command) is refused, proven by a test - `docs/conventions/text-commands.md`'s
      own registration-time collision guard.
- [x] A claimed address already linked to a different visitor is refused, not merged, proven by a test.
- [x] An operator without `Permission.ChannelIdentityUnlink` cannot unlink; one who holds it (via a role
      the tenant defined) can; the resulting identity is excluded from `FindMostRecentForVisitorAsync`
      and analytics channel attribution - proven by tests covering all three. Independently re-proven by
      the managing session: removing the `Active` filter from `FindMostRecentForVisitorAsync` left an
      unlinked identity still eligible for delivery.
- [x] Cross-site isolation is proven by a test (a pending code for one site must never match an inbound
      message on another site, even with the identical code value by coincidence).

## Open questions

Whether expired pending requests need an active sweep or can simply be filtered out of matching
indefinitely - left for the implementation to decide and record, per the Out of scope note above.
