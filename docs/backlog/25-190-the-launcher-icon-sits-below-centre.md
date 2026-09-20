# 25-190 · The closed launcher's own icon sits below centre

- **Stage**: 25
- **Status**: done — `ago-widget#112`
- **Found**: 2026-09-21, the author, live on `golyakov.net` (mobile) - a screenshot showing the
  chat-bubble glyph inside the closed launcher circle sitting visibly below the button's own
  vertical centre.

## Root cause, confirmed

`createSvgIcon` (`ago-widget/src/ui/widget.ts`) sets `svg.style.verticalAlign = "text-bottom"` on
every icon it builds. That anchors the SVG to the **line box's own bottom**, not the button's
centre - how much empty space that leaves above the icon depends on the surrounding line box's
font metrics (ascent/descent, `line-height`), which differ by platform. `.ago-toggle` (the closed
launcher, `ui/styles.ts`) never overrode this with its own centering, so the icon's position was
riding on default inline/baseline layout rather than anything the button itself controlled -
looking "close enough" on some renderers and visibly off on others (mobile Safari, per the report).

`.ago-send` (the composer's round send button) already solves this identical "round, icon-only
button" shape correctly, with an explicit comment stating why: `display: flex; align-items:
center; justify-content: center` - which makes an icon's own `vertical-align` irrelevant, since a
flex item is not part of an inline formatting context at all. `.ago-toggle` had never been given
the same treatment.

## Fix

Add the identical three flex properties to `.ago-toggle`. No change to `createSvgIcon` or any
other button - every other icon-only button in this file (`.ago-send`) already centres this way,
so this fix makes `.ago-toggle` consistent with the rest of the codebase rather than introducing a
new pattern.

## Done when

- [x] `.ago-toggle` centres its icon via flexbox, matching `.ago-send`'s own established pattern.
- [x] `npm run typecheck`/`lint`/`test`/`ux-gate` all green.
