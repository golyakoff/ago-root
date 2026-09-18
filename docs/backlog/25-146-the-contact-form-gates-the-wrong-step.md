# 25-146 · The contact form gates the wrong step

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-18, live, reported by the author after completing a real booking: the
  contact-capture form (`25-136`) appears immediately, glued onto the *service-choice* step's own
  message, before the visitor has invested anything in the booking - and it reads as an unexplained
  block rather than a deliberate step of its own. The author's own reasoning for moving it: a visitor
  who has already picked a service, a worker, a date and a time has invested real effort and made real
  decisions - asking for contact details *there*, as its own clearly-labelled step immediately before
  confirmation, both reads less like a wall going up front and (the author's own words) makes a visitor
  who has come this far more willing to finish than to abandon.
- **Depends on**: `25-136` (done, `ago-widget#94`) - this item changes *when* that item's own gate
  fires, not whether one exists.

## What is actually true today, and why moving "when" is smaller than it looks

`25-136`'s gate fires on the *first* module-task step reached with no known contact detail
(`ui/widget.ts`'s `appendMessageBubble`, keyed on `primitive !== null && !this.storage.
getHasKnownContactDetail()`) - which for booking is the service-choice step, the very first thing the
module sends. The rich contact-capture control (name/phone/email/consent, `contactCapture.ts`) is
inserted as a child of *that* message's own bubble - which is the "glued onto a question" shape the
author is objecting to, not merely its timing.

**`ago-calendar` already sends a step at exactly the position the author wants the form to occupy.**
`ModuleStepFactory.PhoneForm` (via `ReplyToModuleTaskHandler.HandleSlotChosenAsync`) already fires
*after* a time slot is chosen and *before* confirmation - it is a `ModuleStepKind.Form` (or
`VerifiedPhoneForm`) step with `fieldId: "phone"`, asking for a phone number as its own, standalone
message. Today the widget answers it with `renderPrimitiveContent`'s generic single-field form (a
bare text input) - a different, older code path from `25-136`'s own rich contact-capture control.
**The fix is not inventing a new step - it is recognising this existing one and answering it with the
richer control instead of the generic one**, exactly where "after time selection, before confirmation"
already is on the server side.

`25-137`'s own live setup (`AcceptUnverifiedPhone` on) means a visitor with a contact detail already
known skips this step entirely - `ago-calendar` never sends it, so the question of "does the rich
control ever re-show for a returning visitor" mostly does not arise: it is skipped server-side, the
same way it already is today.

## Scope

- **`ago-widget` only** - no `ago-chat`/`ago-calendar` change needed; the position this item wants
  already exists on the wire.
- Remove `25-136`'s "gate the *first* step" condition entirely.
- Add a new condition: when an incoming module-task step's `contentKind` is `form` (or
  `verified_phone_form`, if the widget ever builds a control for that kind - out of scope today per
  `25-133`'s own `KNOWN_KINDS`) **and** its `content.fieldId === "phone"` **and** no contact detail is
  already known, render the rich contact-capture control as this step's own reply-answering control -
  in place of, not alongside, the generic bare-input form `renderPrimitiveContent` would otherwise
  build for it. This makes the form its own standalone message, answering its own standalone step,
  never glued onto service/worker/date/time choices - the author's own explicit ask ("не надо
  склеивать форму с каким-то вопросом").
- On successful submission: record the contact detail exactly as `25-136` already does (`Phone`/
  `Name`/`Email`, consent first if required), **and** send the submitted phone number as this step's
  own reply value (the same reply mechanism a plain `form` step's submit already uses) so
  `ReplyToModuleTaskHandler.HandlePhoneProvidedAsync`/`BookEventHandler` proceed exactly as they do
  today for a plain phone reply - this item changes which control collects the phone, not what happens
  once it is collected.
- Mandatory, not skippable: the step's own answer cannot be submitted any other way while this control
  is showing - the same "disable the primitive's own controls until submitted" mechanism `25-136`
  already built, applied to this step instead of the first one.

## Where this is likely to go wrong

- **Do not special-case this by module name.** Gate on the wire facts already present (`contentKind`
  + `fieldId`), not a hardcoded assumption that this is "the booking module" - `adr/0065`'s own closed
  primitive vocabulary is what any future module would send too, and this widget must stay ignorant of
  which module produced a given step (`ui/widget.ts`'s own existing remarks on the one place it is
  allowed to name `"calendar"` explicitly - this is not that place).
- **A `form` step with a different `fieldId`** (this module has none today, but the vocabulary does not
  forbid one) must keep rendering the generic bare-input form, unchanged - this item's own condition is
  specific to `fieldId === "phone"`, not "any form step in a task this widget has gated once."
- **Do not re-introduce the double-ask this session already closed (`25-137`/`25-138`).** Confirm live,
  end to end, that a first-time visitor sees this rich form exactly once, submits it, and reaches
  confirmation with no further phone question - and that a visitor with a known contact detail (from an
  earlier conversation) never sees this step at all, because `ago-calendar` already skips sending it.
- **Text-channel (Telegram/MAX) behaviour is unaffected by this item** - a `form`-kind step still
  renders as plain text there regardless of `fieldId`, which is correct and unrelated to this item's
  own widget-only scope.

## Done when

- [ ] The contact-capture form no longer appears on the service-choice step, or any step before the
      phone-collection one
- [ ] The form appears exactly once, as its own standalone message, immediately after a time slot is
      chosen and before the booking is finalized - proven live, not just against a test fixture
- [ ] Submitting it both records the contact detail and completes the booking, with no further phone
      question
- [ ] A returning visitor with a known contact detail never sees this step at all (unchanged,
      server-side skip already in place)
- [ ] A `form`-kind step with a `fieldId` other than `"phone"` still renders the plain generic input,
      unchanged
