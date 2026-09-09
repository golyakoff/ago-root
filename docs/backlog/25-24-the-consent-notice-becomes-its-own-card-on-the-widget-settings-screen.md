# 25-24 · The consent notice becomes its own card on the widget settings screen

- **Stage**: 25
- **Status**: done — `ago-console#190`
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

- [x] The consent notice is shown in its own card, separate from the `requireContactConsent` checkbox.
- [x] The card shows the current text truncated to 10 lines with a working "show fully" expansion.
- [x] Nothing about how the notice text is authored or saved changes — display only.

## Outcome

The notice card defaults to a read-only view of the *current* text/link (never the live edit draft),
truncated via a new pure `truncateToLines` helper with a "Show fully"/"Show less" toggle. Editing is a
secondary action behind an Edit/Cancel toggle, the same `formOpen`/`formVisible` shape `25-21`'s
`ConsentDocumentPanel` already established for the identical problem on `/account/documents`.
`requireContactConsent` moved into its own separate "Contact consent" panel; saving is unchanged, one
`<form>`, one PUT. `25-21` itself (bundled with this item for the same file/theme) was found already
merged directly by the author before this branch was cut — verified against its own Done-when rather
than redone.
