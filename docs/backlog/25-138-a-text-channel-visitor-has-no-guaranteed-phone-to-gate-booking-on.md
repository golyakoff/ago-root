# 25-138 · A text-channel visitor has no guaranteed phone to gate booking on

- **Stage**: 25
- **Status**: needs analysis — filed as a question, not yet scoped for implementation
- **Found**: 2026-09-17, while scoping `25-136` (booking's contact-details gate). Filed at the
  author's own explicit request: do the contact gate client-side, in the widget, for now - but file
  the harder question of a server-side equivalent so it isn't lost.
- **Depends on**: `25-136` (establishes the widget-side gate this item's eventual server-side version
  would generalize).

## The question

`25-136` gates the booking flow on contact details client-side, in `ago-widget` - deliberately, because
a server-side gate in `RouteConversationToModuleHandler` would have to apply to *every* channel a
conversation can arrive through, and a Telegram or MAX visitor (`25-121`'s own delivery path) has no
contact-capture form at all. A client-side gate is real UX for an honest widget visitor and no
security boundary at all - trivially bypassable by anyone crafting a raw reply, and entirely absent
for a text-channel visitor today.

**The question this item exists to answer:** how would AGO Chat ever ask a Telegram/MAX visitor for a
name and a phone number - the minimum needed to make a booking's contact requirement mean the same
thing regardless of which channel a visitor arrives through - and only once that's answered, what
would a server-side version of `25-136`'s gate look like that applies uniformly?

Candidate shapes, none evaluated yet:

- A `form`-primitive step, inserted by `RouteConversationToModuleHandler` itself (not by Calendar)
  before routing the first booking reply, asking for name + phone the same way `ModuleStepFactory.
  PhoneForm` already asks for a phone later - reusing the existing primitive vocabulary rather than
  inventing a new one.
- Treating the *channel identity itself* (a Telegram user's own phone-linked account, if the bot API
  ever exposes one; a MAX account's own verified number, if that platform provides it) as already
  satisfying the requirement for that channel - channel-specific, and worth checking against each
  provider's actual capabilities before assuming it's available.
- Something narrower: server-side gate is simply never built, and the risk a client-side-only gate
  accepts is judged acceptable at this project's current scale - a legitimate answer, but one the
  author should reach deliberately rather than by default.

## Scope

None yet. This item is the analysis itself - whoever picks it up next should read `25-136`'s own
Outcome once it lands, check what a real Telegram Bot API or MAX conversation actually exposes about
a user's phone/contact today, and bring back a scoped proposal (or a recommendation to leave the gate
client-side-only) for the author to decide, rather than a built change.

## Where this is likely to go wrong

- Don't assume Telegram's `contact` message type (an explicit "share phone number" button a bot can
  request) is available equivalently on MAX - check each channel adapter's own actual capability
  (`ago-chat`'s `IInboundChannelAdapter` implementations) rather than assuming parity between them.
- This is exactly the kind of decision `CLAUDE.md` says gets filed as the question rather than
  silently implemented either way - resist the temptation to just pick the `form`-primitive shape and
  build it without the author confirming the tradeoff (extra step for every text-channel visitor,
  even one who never intends to book).

## Done when

- [ ] Not yet defined - this item's own first deliverable is a proposal with the tradeoffs above
      actually checked against each channel adapter's real capability, handed back to the author as a
      decision, per this item's own Scope.
