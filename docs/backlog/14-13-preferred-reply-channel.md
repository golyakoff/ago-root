# Preferred reply channel

- **Stage**: 14
- **Status**: done (`ago-chat#138`, `ago-console#72`, merged 2026-08-30)
- **Depends on**: `14-12-verified-channel-identity-linking.md` - a visitor only ever has more than one
  active `ChannelIdentity` once that item ships; `adr/0079` - the full "why `Visitor`, not
  `Conversation`" reasoning

## Goal

Once a visitor has more than one linked channel, an operator can mark which one AGO Chat should actually
use for the next reply - overriding today's implicit "whichever channel was heard from most recently"
rule with an explicit, durable choice.

## Scope

- **Domain**: `Visitor` gains a nullable `PreferredChannelIdentityId`, settable only to one of that
  visitor's own currently-`Active` `ChannelIdentity` rows - never an arbitrary id, so this can never
  route to something that was never verified. Unlinking the preferred identity (`14-12`) clears the
  preference rather than leaving it dangling - proven by a test.
- `DeliverChannelMessageHandler`: checks the preference first (only when the referenced identity is
  still `Active`); falls back to today's existing `FindMostRecentForVisitorAsync` unchanged when unset
  or stale. Proven by a test for each of the three cases (set and active, set and unlinked, unset).
- Console: the same `VisitorPanel` list `14-12` adds gains a way to mark one active identity preferred
  (a radio/star, not a separate page) - one more control on the panel that item already builds, not a
  second one.

## Out of scope

- Reconciling `OperatorAnalyticsReadStore`'s own earliest-identity channel tiebreak with this
  preference - named in `adr/0079` as a real, separate follow-up, not bundled here. This item does not
  touch analytics.
- A per-conversation override on top of the visitor-level default - the author's own framing was
  durable/cross-conversation; a future item can add a narrower override later without changing this
  item's own shape.

## Done when

- [ ] An operator can set a visitor's preferred channel to one of their own active identities, and the
      next outbound message for that visitor's conversations goes there instead of the most-recent one
      - proven end to end.
- [ ] Unlinking the preferred identity clears the preference, and delivery falls back to the existing
      most-recent rule, proven by a test.
- [ ] Attempting to set the preference to an id that is not one of the visitor's own active identities
      is refused, proven by a test.
- [ ] Cross-site isolation is proven by a test.

## Open questions

None. Every real decision here is already made in `adr/0079`.
