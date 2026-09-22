# 25-219 · The channel-switcher banner header doesn't match `.ago-header`'s own look

- **Stage**: 25
- **Status**: done — `ago-widget#131`
- **Found**: 2026-09-22, live, by the author reviewing the widget: `.ago-channel-switcher-banner-header`
  (`25-211`'s header bar atop the hover-revealed channel banner) is a flat `#374151` at
  `font-weight: 700`, while `.ago-header` (the real chat panel's own header, directly above it in the
  same visual stack — the banner sits where the panel itself opens) is the tenant's own accent colour
  as a radial gradient, `h1` at `font-weight: 600`. The two read as two disconnected brand surfaces
  rather than one chrome.

## Scope

- `.ago-channel-switcher-banner-header`'s `background` becomes the identical
  `radial-gradient(...) + color-mix(...)` expression `.ago-header` already declares — copied, not
  factored into a shared custom property (a CSS custom property can hold a colour but not a whole
  `background` shorthand with two layers).
- `font-weight` drops from `700` to `400` (`.ago-header h1` itself is only `600` — `700` was heavier
  than the surface it was supposed to echo, not just a different colour).
- Update `channelSwitcher.test.ts`'s two tests that asserted the old flat colour/weight — the second
  ("reuses the exact `#374151`...") is replaced with the real invariant now being proved: the header's
  background equals `.ago-header`'s own.

## Out of scope

- Any other visual property of the banner (border-radius, padding, the row styling below it) —
  unaffected and untouched.
- The entrance/exit animation the author separately asked to rehearse in an Artifact first, to be
  filed as its own item once a speed/style is chosen — this item is a static-style fix only.

## Done when

- [x] `.ago-channel-switcher-banner-header`'s background is `.ago-header`'s own gradient, not a flat
      neutral.
- [x] `font-weight: 400`, matching `.ago-header h1`'s own weight relationship to its surface.
- [x] `npm run typecheck` and the full `vitest` suite green (566/566), including the two rewritten
      tests.
