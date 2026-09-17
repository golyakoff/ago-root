# 25-130 · The composer starts at one line

- **Stage**: 25
- **Depends on**: nothing
- **Status**: ready
- **Found**: 2026-09-17, the author's own request: the message textarea should be at least three lines
  tall from the start, not grow from a single line.

## What is actually true today

`.ago-input` (`ui/styles.ts`) sets `max-height: 6rem` (grows up to roughly four lines as content wraps)
but no minimum - the textarea renders at its native single-row height until content pushes it taller.

## Scope

- Give `.ago-input` a `min-height` (or an explicit `rows` attribute on the `<textarea>` element itself,
  `ui/widget.ts:497` - pick whichever this codebase's own convention favors for a fixed CSS box versus
  a native attribute, and say which) sized to roughly three lines of its own font/line-height/padding,
  while keeping the existing `max-height: 6rem` growth behavior above that floor unchanged.
- Check `.ago-composer-row`'s own `align-items: flex-end` comment (`ui/styles.ts:326`) - it exists so
  the round send button stays pinned to the input's bottom edge as the textarea grows; confirm a taller
  starting height does not misalign the send/attach/emoji/save row, and adjust only if it actually does.

## Done when

- [ ] The composer textarea renders at roughly three lines tall on open, before any text is typed.
- [ ] It still grows up to its existing `max-height` as content wraps further, and the composer row's
      other controls stay aligned to its bottom edge at every height.
