# 25-158 · A consent step's link is plain text, and its answer is silent

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-19, live-testing a calendar booking flow through the widget. The consent step
  (`25-153`'s own gate, reached mid-booking) rendered as:

  > Чтобы продолжить, пожалуйста, ознакомьтесь с документом «Согласие на обработку персональных
  > данных»: https://office.reserve-me.ru/policies/site-consent-contact-01a06262-d4f0-7fb6-94e0-9ff702db8a43
  > - Согласен(на)
  > - Не согласен(на)

  Two separate defects observed in the same live message:

  1. **The URL renders as plain text, not a link** - not clickable, has to be copy-pasted by hand to
     read the actual policy it is pointing at.
  2. **Clicking "Согласен(на)" produced no visible reaction at all** - no recap of the choice, no
     "Готово!" confirmation, nothing distinguishing "answered" from "not yet answered" in the widget.

## What is confirmed vs. what is only observed

- **Confirmed by reading the code**: `ago-widget/src/ui/primitives/render.ts` has no URL-linkification
  anywhere - every prompt/body string it renders is plain text by construction, not just for this one
  step. So symptom 1 is not specific to the consent gate; any rich-form prompt containing a URL renders
  the same way.
- **Not yet diagnosed**: symptom 2. It could be the widget genuinely not rendering a reply confirmation
  for this step's own reply shape, the underlying `RouteConversationToModuleHandler`/consent-gate reply
  handling not completing as expected, or something specific to how a two-step gate (phone, then this
  consent step) hands off afterward - `25-138`'s own contact-gate mechanism sits right next to this
  code and reuses the identical phone-collection-shaped step, so the two are worth checking together
  rather than assuming they are unrelated.

## Scope

- **`ago-widget`**: render a URL inside prompt/body text as a real, clickable link - likely in
  `render.ts`'s shared text-rendering path so every rich-form primitive gets it, not just this one
  step. Sanitize what gets treated as a link; do not blindly regex-linkify user-authored free text
  without limiting it to how these prompts are actually built server-side.
- **`ago-chat` (or wherever the real cause turns out to live)**: find why answering the consent step's
  choice produces no visible confirmation - reproduce live first (the same booking flow this item was
  found in), read the actual reply-handling path rather than guessing between the two candidates named
  above, then fix whichever one is real.

## Done when

- [ ] A rich-form prompt containing a URL renders it as a clickable link in the widget, proven by a
      live message (not only a unit test)
- [ ] Answering the consent step's choice shows a visible confirmation/recap in the widget, proven by
      a live booking flow reaching this step
- [ ] The real cause of the silent answer is stated in this item's own Outcome, not left as "fixed,
      cause unclear"
