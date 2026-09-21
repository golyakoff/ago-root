# 25-200 · The touch routing sheet's rows read too small

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-21, the author, live on `golyakov.net` (mobile), after `25-197`/`25-198`/`25-199`
  shipped. The author's own request: make the channel icons twice their current size and the
  channel-name text one and a half times its current size, and round every resulting dimension to
  the nearest whole number - no fractional `rem`/`px` values left behind.

## What is actually true today

`.ago-touch-routing-row` (`ui/styles.css`) sets `font-size: 0.9375rem` and nothing else about
sizing. Every icon inside a row - the brand icons from `buildChannelSwitcherRow`
(`CHANNEL_ICON_TREES`) and the chat-bubble icon on the "Онлайн чат" row (`createSvgIcon`) - is built
with `width="1em" height="1em"` as an inline SVG attribute, so today an icon's rendered size is
*coupled* to the row's own `font-size`: both currently render at the same computed pixel size,
because `1em` resolves against the element's own font-size. Scaling the icon and the text by
*different* factors (2x vs 1.5x) requires decoupling them - the icon can no longer rely on `1em`.

## Scope

- **Confirm the real current computed sizes first**, on the actual live site (or a local build
  served the same way) via `getComputedStyle` - do not assume the `rem` math resolves to a clean
  16px root; a host page can set its own root font-size, and this widget's `rem` values resolve
  against the *host document's* root, not the shadow tree, since Shadow DOM does not create a new
  `rem` context.
- Give every icon inside `.ago-touch-routing-row` an explicit fixed pixel size (a real CSS rule
  overriding the inline `width="1em"`/`height="1em"` attribute - standard CSS-over-presentation-
  attribute precedence, no `!important` needed) equal to twice today's confirmed computed icon size,
  rounded to the nearest whole pixel.
- Set `.ago-touch-routing-row`'s own `font-size` to one and a half times today's confirmed computed
  value, rounded to the nearest whole pixel, expressed as a plain whole-number `px` value rather than
  a fractional `rem` (the author's own "round to avoid fractions" instruction reads as wanting away
  from exactly the `0.9375rem` shape this file already has).
- Check the row's own layout after the resize - padding, `gap`, and whether the sheet's own
  `max-height`/scroll still behave reasonably with taller rows - and adjust only if something visibly
  breaks (clipping, overlap); the author did not ask for a padding change, so do not invent one that
  is not needed.
- Verify **live on `golyakov.net`**, not only against a local build - the author's own explicit
  instruction this time, given the miscommunication earlier this session about a mockup that was
  never actually shipped as code.

## Out of scope

- Any other row (`AboveComposer`'s card, `BelowLauncher`'s icon row) - this item is the touch
  routing sheet only.
- The sheet's own panel width/max-height, unless the resize actually breaks it.

## Done when

- [ ] The real current computed icon and text pixel sizes are confirmed (not assumed) before any
      change is written.
- [ ] Every icon inside the touch routing sheet renders at exactly double that confirmed size,
      rounded to a whole pixel, and is provably decoupled from the row's own font-size (a test that
      changes font-size and asserts the icon's own rendered size is unaffected).
- [ ] The row's own text renders at exactly one and a half times that confirmed size, rounded to a
      whole pixel, expressed as a whole-number value with no fractional unit.
- [ ] Verified live on `golyakov.net` - a real screenshot or equivalent live-DOM check, not only a
      jsdom/vitest assertion.
- [ ] Every other row/placement (`AboveComposer`, `BelowLauncher`) is provably unaffected.
- [ ] `npm run typecheck`/`lint`/`test`/`ux-gate` all green.
