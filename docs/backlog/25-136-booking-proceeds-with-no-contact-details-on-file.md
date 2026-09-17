# 25-136 · Booking proceeds with no contact details on file

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-17, live, reported by the author: triggering `/записаться` and picking a service
  and a worker required no name, phone, email, or personal-data consent at any point - the visitor
  simply progresses.
- **Depends on**: none. Touches `ago-widget` only. Shares `ui/widget.ts` with `25-133` - land in the
  same lane, same worker, sequentially (two commits/PRs, one worktree).

## The gap

The contact-capture control the author expected to be required (`ui/contactCapture.ts`, name+phone+
email, with a consent checkbox when the site's `RequireContactConsent` is on) is not wired to the
booking flow at all. It only appears where it does today by accident: `ui/widget.ts`'s own
`appendMessageBubble` shows it whenever `message.authorKind === "System" && !this.contactCaptureShown`
(around line 1831) - a branch written for `14-04`'s out-of-hours auto-reply, before module-task steps
existed. Since `20-07`, a module step's own prompt is *also* delivered as a `System` message, so
typing `/записаться` incidentally triggers this same branch and the form appears next to the
service-choice prompt - which is what the author saw and reasonably read as "the form is part of this
flow." It has no relationship to booking whatsoever: nothing reads what it collects before allowing
the flow to continue, and nothing blocks a reply if it's never shown or never submitted.

Confirmed live: the phone prompt the author saw partway through the flow (`ModuleStepFactory.
PhoneFormPrompt`, the *no-known-number* variant) is exactly what `RouteConversationToModuleHandler`
resolves when there is genuinely no `VisitorContactDetail` on record for that conversation - proving
the form was never actually submitted, consistent with it being decorative rather than required.

## Scope (per the author's own decision, 2026-09-17 - narrower than the largest possible fix)

- **Client-side only.** The widget itself refuses to let the booking flow's first reply (the service
  choice) go out until the contact-capture form has been submitted - it does not touch
  `RouteConversationToModuleHandler` or any other `ago-chat` server-side gate. A server-side gate was
  considered and explicitly deferred: it would need to treat a widget-originated conversation
  differently from a Telegram/MAX one, since a text-channel visitor has no contact-capture form to
  fill in at all (`25-121` shipped four days before this item, and this item must not break it) - see
  `25-138` for the follow-up this defers to.
- Unconditional whenever the booking module task is active for a widget conversation - not a new
  per-site toggle. This is a structural precondition of booking a real slot (someone has to be
  reachable), not an optional tenant preference like `RequireContactConsent`/`AttractAttention`.
- Detach the contact-capture control's *display* from the accidental `authorKind === "System"`
  branch it currently rides - make the "a module step is active and no contact detail is on file yet"
  case its own deliberate condition in `ui/widget.ts`, rather than leaving the coincidence in place
  and only bolting a gate onto it.
- Reuses the existing form as-is (name+phone+email all required, per `23-58`; the consent checkbox
  shows and is required exactly when `RequireContactConsent` is already on for that site, per `24-05`
  - no new field, no new site setting).

## Where this is likely to go wrong

- A visitor who already has a contact detail on file (an earlier conversation, or the console's own
  operator-entered contact) must **not** be shown the form again or blocked by it - check
  `VisitorContactDetail` state before deciding to gate, the same check `ResolveKnownPhoneAsync`
  already does server-side for the phone prompt.
- This is a client-side gate: it improves the UX for an honest visitor and is not a security boundary
  - a visitor could still bypass it by crafting a raw reply. That is an accepted, named limitation
  (see `25-138`), not an oversight to silently harden here.
- This item and `25-133` both touch `ui/widget.ts` - land sequentially, not as two parallel branches.

## Done when

- [ ] A widget visitor with no contact detail on file who triggers the booking module is shown the
      contact-capture form before the service-choice step will accept a reply, and cannot answer that
      step until the form is submitted
- [ ] A visitor who already has a contact detail on file is not shown the form again and proceeds
      straight to the service step
- [ ] A site with `RequireContactConsent` on cannot submit the form without the consent tick (already
      true today - confirm it still holds once the form's display condition changes)
- [ ] A text-channel (Telegram/MAX) visitor's booking path is unaffected by this item
- [ ] `25-138` is filed (done - see that item) so the server-side question this defers is not lost
