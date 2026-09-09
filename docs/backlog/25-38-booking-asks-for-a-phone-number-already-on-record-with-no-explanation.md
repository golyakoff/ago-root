# 25-38 · Booking asks for a phone number already on record, with no explanation

- **Stage**: 25
- **Status**: done — `ago-calendar#56`, `ago-chat#247` — with one Done-when box only partially met,
  see Outcome
- **Found**: 2026-09-09, live, reported by the author — having already given a phone number earlier in
  the same conversation (the widget's own "represent yourself" contact capture, `25-28`), the booking
  flow's phone step reads as asking the same question again for no visible reason.
- **Depends on**: `25-37` (shares the same file and should not be built as two separate diffs to the
  same strings — land whichever lands second on top of the first, not as parallel edits).

## Why this isn't simply "reuse the number" — read this before scoping the fix

`ModuleStepFactory.PhoneForm()` deliberately emits `VerifiedPhoneFormStep`, not a plain form
(`20-09`'s own comment on the method, `docs/adr/0082-*`). Chat's earlier contact capture collects a
**self-reported, unverified** phone number; `BookEventHandler` requires `PhoneVerifiedAt` — proof of
control over the number — before it will hold a slot (`ReplyToModuleTaskHandler.HandlePhoneProvidedAsync`,
`RequiresVerifiedPhone: true`). **That strictness is correct and this item is not asking to remove
it.** A booking is a real-world commitment (a worker's calendar slot, a no-show risk); a typed string
from `25-28`'s contact form is not proof of anything.

The actual gap is that the *step itself never says why*. It reads as the system having forgotten the
number the visitor just gave, rather than as a deliberate second, stronger check.

## Scope

- If the visitor already gave a phone number earlier in the conversation, **prefill** the verified-phone
  step with that number rather than presenting an empty field — the visitor confirms/edits instead of
  retyping from memory.
- Change the prompt's wording (alongside `25-37`'s localization pass) to say what is actually
  happening — e.g. naming that this step confirms the number for the booking itself, distinct from the
  contact info already on file — so a visitor understands why they're asked again instead of assuming
  a bug.
- Do not weaken `RequiresVerifiedPhone` or skip the verification step even when a number is already on
  file — that would undo `20-09`'s guarantee.

## Where this is likely to go wrong

- The already-known number lives on the `Conversation`/contact-capture side (`ago-chat`), not in
  `ago-calendar`'s own `ChatBookingTask` — this needs whatever the module boundary already carries (or
  doesn't) from Chat to Calendar per task. If that plumbing doesn't exist, say so and scope adding it,
  rather than inventing a lookup that reaches across the module boundary directly.

## Done when

- [~] A visitor who already gave a phone number earlier in the same conversation sees it prefilled
      (not re-typed from scratch) at the verified-phone step. — **partially met, and named honestly
      rather than rounded up**: there is no wire-level "default value" for a form field in this
      contract (`adr/0065`'s closed primitive vocabulary), and adding one would only ever be honoured
      by `ago-widget`'s own input rendering, outside this change's scope. The number is instead named
      in the prompt text itself ("is +7999… still the best number…"), reaching every renderer this
      contract has today with zero new plumbing — but the visitor still sends a reply, same as before,
      rather than confirming a pre-populated field with one tap. A real prefill needs `ago-widget`
      changes and is left for whoever picks that up.
- [x] The step's own wording explains that this confirms the number for the booking, distinct from the
      earlier contact info — verified by reading the rendered copy, in whichever language `25-37`
      lands.
- [x] `RequiresVerifiedPhone` behaviour is unchanged — a booking still requires proof of control over
      the number regardless of what was on file before.

## Outcome

Landed alongside `25-37`/`25-39` (same files, same PRs — `ago-calendar#56`, `ago-chat#247`). The known
phone number is resolved by `RouteConversationToModuleHandler` from the visitor's most recent
`VisitorContactDetail` and resent fresh on every reply, the same wire shape `25-37`'s locale and
`25-39`'s setting use. See the box above for the one real scope limit: this is a wording fix, not a
true form prefill.
