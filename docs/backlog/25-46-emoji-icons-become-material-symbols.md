# 25-46 · Emoji icons become Material Symbols Outlined

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing — foundational for `25-47`/`25-48`/`25-51`, which need real icons in the new
  header menu and badges
- **Found**: 2026-09-12, `feedback.md` (the author's own console UI/UX review)

## What is actually true

`ago-console` renders emoji characters (💬, 🎨, etc.) as functional icons in several places —
buttons, menu items. Emoji glyphs render differently per browser/OS/font, which the feedback names
explicitly as the reason to stop: they are not a consistent icon set, they are whatever the visitor's
or operator's own platform happens to draw for that codepoint.

## Scope

- Replace every emoji used as a functional icon (button, menu item, status indicator) with a
  [Material Symbols Outlined](https://fonts.google.com/icons?selected=Material+Symbols+Outlined) icon
  in the matching style, at a consistent weight/size.
- Does **not** touch emoji used as genuine content or a deliberate visual mnemonic — `25-56`'s own
  per-visitor emoji pair is a new, separate, intentional use of emoji and is explicitly out of this
  item's scope in the other direction (do not "fix" those into icons).

## Where this is likely to go wrong

- **Find every instance before starting**, not just the ones already named in the feedback — a
  partial sweep leaves a visibly inconsistent mix of real icons and leftover emoji, which reads worse
  than either pure choice.
- **Load the font/icon set once, correctly**, rather than per-component — check the widget's own
  bundle-budget discipline (`build.mjs`) is not affected if any shared icon infrastructure is touched;
  this item is console-only, the widget is untouched.

## Done when

- [ ] No emoji renders as a functional icon anywhere in `ago-console`.
- [ ] Every replaced icon uses Material Symbols Outlined, consistent weight/size/style across the
      console.
