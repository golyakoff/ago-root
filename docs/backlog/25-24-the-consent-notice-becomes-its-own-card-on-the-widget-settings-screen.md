# 25-24 · The consent notice becomes its own card on the widget settings screen

- **Stage**: 25
- **Status**: ready — **blocked in practice, not on another item's number**: `WidgetConfigPage.tsx` is
  being actively edited by an in-flight worker landing `23-64` (the auto-open greeting) as this is
  filed. Do not start this until that lands — same file, real conflict, not a hypothetical one.
- **Depends on**: `16-04` built the notice text and its checkbox; this only reorganises how they are
  shown.
- **Found**: 2026-09-09, the author using the widget settings screen

## What is actually true

`WidgetConfigPage.tsx` shows the tenant's data-processing notice text (`noticeText`/`noticeUrl`,
`16-04`) grouped together with the **«Требовать согласие перед сбором контактных данных»** checkbox
(`requireContactConsent`). They are two different questions — what the notice says, and whether
accepting it is mandatory before contact data is collected — and showing them as one grouped control
reads as if they are the same setting.

## Scope

- Split the notice into its **own card**, titled something like "Согласие на обработку персональных
  данных", separate from the `requireContactConsent` checkbox.
- Inside that card, show the tenant's **current, actual notice text**, read-only, **truncated to the
  first 10 lines** with a "показать полностью" control that expands the full text in place.
- The `requireContactConsent` checkbox stays where it functionally belongs (gating collection) but no
  longer visually implies it is part of composing the notice text itself.

## Where this is likely to go wrong

- **This is the same file `23-64` is landing** (the auto-open greeting's own settings fields go into
  this page too). Rebase onto whatever `23-64` leaves behind rather than assuming the file's current
  shape — read it fresh before starting.
- **Do not turn this into an editor.** The notice's text is still authored wherever `16-04` put that
  control; this item only changes how the *current* text is displayed and grouped, not how it is
  written.

## Done when

- [ ] The consent notice is shown in its own card, separate from the `requireContactConsent` checkbox.
- [ ] The card shows the current text truncated to 10 lines with a working "show fully" expansion.
- [ ] Nothing about how the notice text is authored or saved changes — display only.
