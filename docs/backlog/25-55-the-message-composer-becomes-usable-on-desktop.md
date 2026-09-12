# 25-55 · The message composer becomes usable on desktop

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-12, `feedback.md` — a real, live usability defect, not only a style preference

## What is actually true

The Диалог panel's own message-compose area is, in the desktop layout, reduced to roughly 10-20
pixels wide — effectively non-functional for typing a real message. The three action buttons
(Прикрепить, Предложить, Отправить) do not fit in a row either, even on desktop.

## Scope

- The text-entry area becomes a wide, multi-line textarea — roughly 5 rows tall by default, growing
  in height as a message exceeds that without a fixed cap that clips content.
- Buttons (Прикрепить / Предложить / Отправить) move to directly below the textarea, not beside it.
  If rendered as icons (post-`25-46`), fit all three in one row; if rendered as text labels, stack
  them in a column instead — pick whichever the icon-based row allows, since it fits and a stacked
  column of icons would be wasted vertical space.

## Where this is likely to go wrong

- **This is the panel's own layout allocation, not just the textarea's CSS** — the surrounding
  three-panel layout (`23-xx`'s own three-column shape) may need to give this panel more width when it
  holds focus, per the feedback's own separate note about panels "sужаться" — that broader panel-focus
  UX is not this item's own scope (it is a bigger, separate redesign question), but this item's own
  fix must not silently rely on that redesign happening — it must work inside today's panel widths.

## Done when

- [ ] On a real desktop viewport, the compose textarea is wide enough to type and read a real
      message, not clipped to a sliver.
- [ ] The textarea starts at roughly 5 rows and grows for longer messages rather than clipping.
- [ ] Прикрепить/Предложить/Отправить sit directly under the textarea and all fit without wrapping
      oddly, on both desktop and mobile.
