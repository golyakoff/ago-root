# 25-154 · Three widget rendering fixes, found testing the consent flow live

- **Stage**: 25
- **Status**: done — `ago-calendar#70`, `ago-widget#103`
- **Found**: 2026-09-18, the author testing `25-153`'s consent gate live on the demo stand.
- **Depends on**: nothing. Touches `ago-calendar` (date format) and `ago-widget` (the other two).
  One worker, both repositories - the widget half needs the calendar half's own context to avoid
  guessing at the wire shape.

## 1. A `choice_list`/`date_time_picker` step's own prompt text never reaches the widget - real bug

**This is the reason the consent step showed two bare buttons with no question at all.** Confirmed by
reading the code, not assumed:

- `RouteConversationToModuleHandler.SendConsentPromptAsync` (`25-153`) builds a correct payload -
  `{ prompt: "Чтобы продолжить, пожалуйста, ознакомьтесь с документом «...»: <link>" }` - through the
  same `PrimitiveKinds.ChoiceList` shape every other choice-shaped step already uses.
- `ago-widget`'s `ui/primitives/render.ts`, `case "choice_list": case "date_time_picker":` calls
  `appendActionButtons` and returns - **it never reads `content.prompt` at all**, unlike
  `case "confirmation_card"`, which renders `card.title` as a `.ago-primitive-title` div before its
  lines and buttons (read that case for the exact pattern to mirror).
- `ui/widget.ts`'s own `25-133` fix suppresses the plain-text `Message.Body` fallback whenever a rich
  `primitive` renders (its own comment: "showing the plain-text rendering underneath it is... a
  redundant second rendering"). For `form`/`confirmation_card` that reasoning holds - their rich
  rendering already carries the meaningful text. For `choice_list`/`date_time_picker` it does not: the
  rich rendering is bare buttons, so `25-133` silently removed the *only* text this step ever showed,
  for every `choice_list`/`date_time_picker` step this build has ever sent - not merely the new consent
  one. It went unnoticed until now because most existing choice-shaped steps (which service, which
  worker, which date) are self-explanatory from context or from button labels alone; the consent step
  is the first one where the missing sentence is load-bearing (it names a specific document).

**Fix**: in `ui/primitives/render.ts`, `choice_list`/`date_time_picker` reads `content.prompt` (the
identical field `Ago.Chat.Domain.PrimitiveTextRenderer.TryReadPrompt` already reads server-side) and
renders it before the buttons, the same way `confirmation_card` renders `card.title` - reuse that
class/pattern rather than inventing a new one. Verify this doesn't produce a visibly redundant prompt
for an existing choice-shaped step whose prompt is already implied by context (spot-check the
service/worker/date pickers after the fix); if one reads badly, that is a copy problem in the
individual step's own prompt text, not a reason to special-case rendering per step.

## 2. The date-choice step's own button labels: abbreviate the weekday, keep day/month/year full

`ago-calendar`'s `ModuleStepFactory.DateChoice` labels each date button with
`Strings.FormatDate(date)` - `25-145` grew this from `"вт, 15 сен"` to the full
`"вторник, 18 сентября 2026"`. The author's own ask, testing live: keep the year (right call from
`25-145`), but the weekday name is too long for a button - shorten it to `"Вт, 18 сентября 2026"`
(abbreviated, capitalized weekday; day, month and year stay exactly as `25-145` left them).

**Scope this narrowly, to the date-choice buttons only** (`DateChoice`'s own call to
`strings.FormatDate`) - `FormatDate` is also called from `DescribeRange` (the confirmation card's own
"Когда" line), which the author did not ask to change and which plausibly reads better in full prose
form ("Когда: пятница, 18 сентября 2026, 17:00–18:00 МСК"). Do not change `FormatDate` itself if that
would also shorten the confirmation card - either give `DateChoice` its own short-form date string
(reusing `Weekdays`/`Months` tables, a new method beside `FormatDate` rather than a parameter that
changes `FormatDate`'s own contract), or thread an explicit `abbreviateWeekday: bool` through
`FormatDate` defaulting to `false` so every other caller is unaffected by construction. State which you
chose and why - this is exactly the kind of "what crosses this boundary" call worth one sentence in the
PR, not a new ADR.

Both `en`/`ru` `Strings` records carry `Weekdays`/`Months` tables (`ModuleStepFactory.cs`) - the English
side presumably wants the equivalent shortening (`"Friday, September 18, 2026"` → `"Fri, September 18,
2026"`), confirm this rather than leaving English inconsistent with the fix's own intent.

## 3. Remove the "automatic reply" label entirely - the author's own explicit decision, 2026-09-18

**This reverses part of `14-04`'s original disclosure design, deliberately, not by omission.** `14-04`
added `.ago-message--auto::before { content: var(--ago-auto-reply-label, ...); text-transform:
uppercase; ... }` (`ui/styles.ts`) plus `strings.autoReplyLabel` (`i18n/en.ts`/`ru.ts`) and the
`--ago-auto-reply-label` custom property (`ui/widget.ts`) specifically so a visitor is never misled
into thinking a person answered. Asked directly, 2026-09-18: the author chose removing the label
entirely over softening its styling (dropping only the uppercase transform was the other option,
declined).

Remove: the `.ago-message--auto::before` rule and its own surrounding comment in `ui/styles.ts`; the
`--ago-auto-reply-label` custom-property write in `ui/widget.ts`; `autoReplyLabel` from `WidgetStrings`
and both locale files, **only if nothing else reads it** (check before deleting - `strings.ts`'s own
interface may be referenced by a test fixture that needs updating too, not only production code). Leave
`.ago-message--auto`'s own base styling (the border-left accent, the shared incoming-bubble shape) - the
author asked to remove the *label*, not to make an automatic reply visually identical to an operator's;
confirm this reading is right rather than assuming silently, since it is the one place this item's own
scope could be read two ways.

State plainly, in the PR, that this reverses `14-04`'s own stated disclosure purpose - a future reader
of `14-04` should not conclude the label still exists.

## Done when

- [x] A `choice_list`/`date_time_picker` step's `content.prompt` renders in the widget before its
      buttons, mirroring `confirmation_card`'s own title pattern - proven for the consent step
      specifically (the prompt naming the tenant's document now visible), and spot-checked against at
      least one existing choice-shaped step to confirm no visible regression
- [x] A date-choice button reads `"Вт, 18 сентября 2026"` (ru) / the equivalent English short form -
      the confirmation card's own "Когда" line is unaffected, proven by a test naming both call sites
- [x] No trace of the automatic-reply label remains in `ago-widget` - the CSS rule, the custom-property
      write, and the now-unused string keys, with a note in the PR that this deliberately reverses part
      of `14-04`'s own disclosure design
- [x] Full test suites green in both repositories, re-verified independently

## Outcome

`ago-widget#103`: `render.ts`'s `choice_list`/`date_time_picker` now renders `content.prompt` as a
`.ago-primitive-title` div before the buttons, mirroring `confirmation_card`; spot-checked against
the existing service/worker/date pickers with no regression. The auto-reply label removed entirely
(CSS rule, custom property, and `autoReplyLabel` string, confirmed no other reader) - base bubble
styling unchanged. 453/453 tests green.

`ago-calendar#70`: new `Strings.FormatDateShort` beside `FormatDate` (a dedicated method, not a
boolean parameter, so every other `FormatDate` caller stays untouched by construction) - `DateChoice`'s
button labels abbreviate the weekday; `DescribeRange`'s confirmation-card line is unaffected. English
gets the equivalent treatment. Full suite green: Domain 235, Application 214, Architecture 28,
Concurrency 26, Integration 346.
