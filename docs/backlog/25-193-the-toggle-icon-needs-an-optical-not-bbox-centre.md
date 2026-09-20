# 25-193 · The toggle icon needs an optical, not bounding-box, centre

- **Stage**: 25
- **Status**: done — `ago-widget#114`
- **Found**: 2026-09-21, the author, reviewing a live mockup of `25-192`'s own hover behaviour -
  the closed launcher's chat-bubble icon (just flex-centred by `25-190`) still read as sitting too
  high inside the button.

## What was actually true

`25-190` fixed a real bug: `.ago-toggle` had no flex centring at all, so the icon's position rode
on default inline/baseline layout. Flex centring is correct as far as it goes - it centres the
icon's own bounding box exactly - but the Material Symbols `chat_bubble` glyph's *visual* mass is
not centred inside that box. Its tail is a thin spike hanging below the rounded rect that is
actually the shape's visual body, so the rect's own centre sits noticeably above the bounding
box's true centre. Bounding-box centring alone therefore reads as "too high" - correct by the
numbers, wrong to the eye.

## Fix

`.ago-toggle svg { transform: translateY(0.125rem); }` - a small, explained optical correction,
scoped to the toggle's own icon only. `.ago-close`'s own icon (a plain X, no tail) needs no
equivalent nudge and gets none.

## Done when

- [x] The toggle's icon reads as visually centred, not merely bounding-box centred.
- [x] No change to any other button's icon.
- [x] `npm run typecheck`/`lint`/`test`/`ux-gate` all green - including the bundle-size guard,
      which the first draft of this fix's own comment briefly exceeded (46.2 KB vs. the 46 KB
      budget) before being trimmed.
