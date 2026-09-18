# 25-158 · A rich-form prompt's URL renders as plain text

- **Stage**: 25
- **Status**: ready — diagnosed 2026-09-19, root cause confirmed against `origin/main`
- **Found**: 2026-09-19, live-testing a calendar booking flow through the widget. The consent step's
  prompt (`25-153`'s own gate) rendered a policy link as raw, non-clickable text:

  > Чтобы продолжить, пожалуйста, ознакомьтесь с документом «Согласие на обработку персональных
  > данных»: https://office.reserve-me.ru/policies/site-consent-contact-01a06262-d4f0-7fb6-94e0-9ff702db8a43

- **Split from**: originally filed together with the consent step's silent-answer bug as one item.
  Split 2026-09-19 per rule 15 - the two share no file and no cause; the other half is `25-159`
  (`ago-chat`, reply resolution). This item is `ago-widget` only (rendering).

## Root cause, confirmed

`ago-widget/src/ui/primitives/render.ts` turns every piece of prompt/title/label/value text into DOM
via `element.textContent = someString`, with **no URL detection anywhere in the file or the repo** -
confirmed by search, not assumed:

- `choice_list`/`date_time_picker` case (`25-154`'s own addition): `title.textContent = prompt;` - the
  exact path that rendered the consent step's own message, since the consent gate is an ordinary
  `choice_list` step from the widget's point of view.
- `confirmation_card`'s title and each line's label/value: the identical pattern.
- `form`'s `fieldLabel`: same.

A sibling instance exists in `ago-widget/src/ui/widget.ts` (`bubble.textContent = body`, the mandatory
plain-`body` fallback) - not in scope here; that call site is outside `render.ts`'s shared primitive
path and is a separate, smaller fix if it turns out to matter.

**No existing URL-detection/linkify utility exists** in `ago-widget` or `ago-chat`. The two closest
precedents are validation-only, not text-scanning, and neither is directly reusable:
- `ago-widget/src/ui/appearance.ts` (`parseNoticeUrl`) validates that a *whole string* is an absolute
  `https://` URL via `new URL(value)` - it does not find a URL *inside* a longer string.
- `ago-widget/src/ui/contactCapture.ts` builds a real `<a>` for a *structurally separate* link field
  (`link.href = ...; link.target = "_blank"; link.rel = "noreferrer"; link.textContent = summary.title;`)
  - this is the anchor-attribute convention to mirror, but for a field that already carries a URL as
    its own value, not one embedded in prose.

**The `textContent`-only discipline is deliberate and must be preserved.** `widget.ts`'s own comment on
the `body` fallback states explicitly that this untrusted content is never treated as markup. Any fix
must keep that invariant - build `<a>` elements procedurally, never parse the string as HTML.

## Scope

Add one small helper in `render.ts`, e.g. `appendLinkedText(parent, text)`: a regex over
`https?:\/\/[^\s<>"]+` finds URL runs, and for each one appends a real `<a>` (`createElement("a")`,
`.href`/`.textContent` set directly, `target="_blank" rel="noreferrer"`) interleaved with
`document.createTextNode()` runs for the surrounding text - never `innerHTML`. Only `http(s)://`
substrings become clickable by construction (the regex admits no other scheme, so a
`javascript:`-shaped string is never turned into a live anchor).

Replace the plain `.textContent = ...` assignments named above (`choice_list`/`date_time_picker`'s
title, `confirmation_card`'s title and line label/value, `form`'s field label) with calls to this
helper, so every rich-form primitive gets it - not a special case for the consent step alone.

## Out of scope

- `widget.ts`'s own `bubble.textContent = body` fallback - a separate call site, not part of this
  item's own shared-primitive-path fix.
- Anything about the consent step's *reply handling* - that is `25-159`.

## Done when

- [ ] A `choice_list`/`date_time_picker` prompt containing an `http(s)://` URL renders it as a real,
      clickable `<a>` (correct `href`, `target="_blank"`, `rel="noreferrer"`), proven by a unit test
- [ ] The same holds for `confirmation_card`'s title/lines and `form`'s field label
- [ ] A prompt with no URL renders exactly as before (regression safety - unchanged text output)
- [ ] A URL-shaped string on a disallowed scheme (e.g. `javascript://…`) is confirmed, by an explicit
      test, never turned into a live anchor
- [ ] The exact consent-step message from this item's own repro renders its link as clickable in a
      real, live booking flow - not only proven by a unit test
