# 25-138 · A text-channel visitor has no guaranteed phone to gate booking on

- **Stage**: 25
- **Status**: ready — decided by the author, 2026-09-18: build a `form`-primitive name+phone step,
  inserted by `RouteConversationToModuleHandler` before routing a conversation's first booking reply.
  Channel-neutral, reuses the existing primitive vocabulary - no new wire shape.
- **Found**: 2026-09-17, while scoping `25-136` (booking's contact-details gate). Filed at the
  author's own explicit request: do the contact gate client-side, in the widget, for now - but file
  the harder question of a server-side equivalent so it isn't lost.
- **Depends on**: `25-136` (establishes the widget-side gate this item's eventual server-side version
  would generalize). `25-153` (the general "insert a step before routing to the module, general and
  channel-neutral" pattern this item reuses - read that item's own `RouteConversationToModuleHandler`
  changes first, they are the direct precedent and the reason this stopped being merely analysis).

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

**Decided, 2026-09-18** - build the `form`-primitive shape, the first of the three candidates above,
using `25-153`'s own consent-gate as the direct implementation precedent:

- Before `RouteConversationToModuleHandler` routes a conversation's **first** reply into a module (the
  same `TryStartTaskAsync` entry point `25-153`'s own gate hooks), check whether this visitor already
  has a known name+phone on file (`IVisitorContactDetailRepository`, the same read `25-151`'s own
  `RecordChannelVisitorContact` writes through). If not, insert a `form`-primitive step asking for
  name+phone instead of forwarding the reply to the module - general, not booking-specific, so any
  future module gets the identical gate with no changes here.
- On a reply, record the contact via the existing `RecordChannelVisitorContact`/
  `RecordVisitorContactDetailHandler` write path (`25-151`) - the identical consent-gate-aware,
  rate-limited path, never a second one. If `RequireContactConsent` is on, `25-153`'s own gate applies
  here too, in the same order it already applies before a module's own phone-collection step -
  reuse that check, do not duplicate it.
- Once satisfied (already on file, or just recorded), forward the original reply to the module exactly
  as today - this step must never eat the visitor's first real message, only precede it.
- **Only for a channel with no equivalent capture already** (Telegram/MAX today - the widget's own
  `25-136` client-side gate already covers the widget). Gate on `ChannelKind`, not on "not the widget" -
  a future channel with its own native contact mechanism should be excluded explicitly, by name, not
  by exclusion of the widget alone.

## Where this is likely to go wrong

- Don't assume Telegram's `contact` message type (an explicit "share phone number" button a bot can
  request) is available equivalently on MAX - check each channel adapter's own actual capability
  (`ago-chat`'s `IInboundChannelAdapter` implementations) rather than assuming parity between them.
- This is exactly the kind of decision `CLAUDE.md` says gets filed as the question rather than
  silently implemented either way - resist the temptation to just pick the `form`-primitive shape and
  build it without the author confirming the tradeoff (extra step for every text-channel visitor,
  even one who never intends to book).

## Done when

- [ ] A Telegram/MAX visitor with no name/phone on file is asked for one, as a `form`-primitive step,
      before their first reply ever reaches a module
- [ ] A visitor who already has a name+phone on file (e.g. from a prior conversation, or `25-151`'s own
      contact-share recording) skips the step entirely - forwarded straight through
- [ ] `RequireContactConsent`-on sites still gate correctly - the same consent step `25-153` built
      applies here too, reused rather than duplicated
- [ ] A widget visitor is completely unaffected - this item is Telegram/MAX only
- [ ] The recorded contact is the identical `VisitorContactDetail` shape/write-path every other source
      already produces, findable by `ResolveKnownPhoneAsync` and visible in the operator queue
