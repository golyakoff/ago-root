# 25-153 · A text-channel visitor has no way to give PD consent

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-18, scoping `25-138`. `RecordVisitorContactDetailHandler.
  ConsentSatisfiedAsync` already refuses to record a contact detail when a site has
  `RequireContactConsent` on and no consent is on file - but a text-channel visitor has no checkbox to
  tick, and **the booking flow's own phone-reply handler never calls that consent check at all**.
  `HandlePhoneProvidedAsync` sends a typed phone number straight to `BookEventHandler`, never through
  `RecordVisitorContactDetailHandler` - so a Telegram/MAX booking completes today with **no consent
  check whatsoever**, on any site, regardless of that site's own `RequireContactConsent` setting. This
  is not a hypothetical gap: it is a live compliance hole on the exact mechanism `24-05` built to close
  it for the widget.
- **Depends on**: none technically (this is an independent gate, not tied to `25-151`/`25-152`'s own
  contact-capture mechanism) - but land after `25-151` in the same lane, since both touch
  `ReplyToModuleTaskHandler`'s own phone-collection path and a rebase is cheaper than a merge conflict.
  Touches `ago-chat` only.

## The design, as scoped directly with the author, 2026-09-18

Before the booking flow ever reaches the phone-collection step (`ModuleStepFactory.PhoneForm`) on a
site with `RequireContactConsent` on and no consent already on file for that visitor, insert a
mandatory consent step ahead of it - reusing the existing `choice_list` primitive exactly as-is, no
new wire vocabulary:

- Prompt names the tenant's own consent document (title + link, the identical
  `ConsentDocumentSummary`/`GetConsentRequirementHandler` data the widget's own checkbox already
  reads) and offers two actions: accept, decline.
- A text channel renders this as the ordinary numbered list `PrimitiveTextRenderer` already builds for
  any `choice_list` step, and the existing generic reply-matching (a numeric reply resolved against
  the last step's own actions) answers it with no new inbound handling at all - this step needs no
  channel-specific code on either side.
- **On accept**: proceed to the phone-collection step exactly as today.
- **On decline**: **do not cancel the booking task.** Re-offer the identical consent choice, with an
  added sentence explaining *why* - the author's own words: tell the visitor plainly that without
  consent the phone number cannot be recorded and the booking cannot be completed, and ask again,
  since a visitor who understands the requirement may reconsider. This is the same "re-offer rather
  than dead-end" shape `ReplyToModuleTaskHandler.HandlePhoneProvidedAsync` already uses when a booking
  attempt loses a slot race (`ReopenForSlotChoice`) - reuse that precedent's spirit, not a new pattern.
  A visitor who simply stops replying leaves the task exactly where an abandoned module task already
  sits today - no special "give up" handling needed.
- This gate is **general, not calendar-specific**: express it as a check `ReplyToModuleTaskHandler`
  (or a shared point above it, if `25-152`'s own contact-button flow needs the identical gate before
  offering a contact button - check whether that item has landed first and share the gate rather than
  duplicating it) performs before any step that would collect a contact detail, not a
  booking-module-only rule.

## Scope

- A new consent-gate check, keyed on `RequireContactConsent` (already read by `RouteConversationToModuleHandler`
  elsewhere - reuse that resolution) and whether a consent acceptance already exists for this visitor
  (the same fact `GetConsentRequirementHandler` already computes for the widget).
- The consent step itself: a `ModuleStep`/`choice_list` built the same way `ModuleStepFactory`'s other
  steps are, in whichever layer already owns "decide what to send next" for this flow -
  `ReplyToModuleTaskHandler` most likely, since it already owns the equivalent decision for the phone
  step.
- Recording acceptance: reuse whatever `RecordVisitorContactDetailHandler`'s own consent-acceptance
  write path already does for the widget (`24-01`'s acceptance record) - a text-channel "accept" reply
  must produce the identical stored fact, not a second, parallel consent-tracking mechanism.
- The decline-and-re-explain loop: a small, bounded state on the module task (or derivable from
  "the last step sent was this consent step and the reply was decline") - do not add an unbounded
  retry counter or any new persistent field if the existing task state already tells this story.

## Where this is likely to go wrong

- **Never let this step's own text be interpreted as AGO authoring consent language on the tenant's
  behalf** (`adr/0076`'s standing boundary) - the document title and link are the tenant's own; the
  surrounding "please review and accept/decline" framing is this widget's/channel's own UI chrome, the
  identical split the widget's own consent checkbox label already draws.
- **Confirm this actually closes the compliance gap named above** - write a test proving a Telegram/MAX
  booking on a site with `RequireContactConsent` on and no consent on file cannot reach
  `BookEventHandler` at all until consent is accepted, not merely that the new step renders.
- Don't gate a site with `RequireContactConsent` off (the default) behind any new step - this item's
  entire behavior must be inert for the common case, exactly like the widget's own consent checkbox
  already is.

## Done when

- [ ] A Telegram/MAX visitor on a site with `RequireContactConsent` on sees the consent step before
      any phone question, text-channel-rendered as an ordinary numbered choice
- [ ] Accepting proceeds to the phone step exactly as today, and records the identical acceptance fact
      `24-01`'s own mechanism already produces for the widget
- [ ] Declining does not cancel the task - it re-offers the same choice with an explanation of why
      consent is required, and a visitor can accept on a later attempt
- [ ] A booking cannot reach `BookEventHandler` without consent on a `RequireContactConsent` site -
      proven by a test that exercises the real path, not just that the step renders
- [ ] A site with `RequireContactConsent` off is completely unaffected - no new step, no behavior
      change
