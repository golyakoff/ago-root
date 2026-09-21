# 25-202 · A touch routing sheet's button rows don't fill the panel - the divider looks cut off

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-21, the author, live on `golyakov.net` (mobile) - a screenshot with the two
  short divider lines circled in red, described as "почему-то отрезанных линий" (dividers cut off
  for some reason). Confirmed directly against the real live DOM before filing (see below), not
  assumed from the screenshot alone.

## What is actually true today

Confirmed via `getBoundingClientRect`/`getComputedStyle` against the real, live touch routing sheet
on `golyakov.net` (mobile emulation, panel width 375px):

| Row | Element | Measured width |
|---|---|---|
| MAX | `<a>` | **375px** (fills the panel) |
| Telegram | `<a>` | **375px** (fills the panel) |
| Онлайн чат | `<button>` | **156.95px** (shrinks to its own content) |
| Отмена | `<button>` | **89.09px** (shrinks to its own content) |

Every row - real channel link or not - shares `.ago-channel-switcher-row`'s `display: flex` and
`.ago-touch-routing-row`'s `border-top`. `display: flex` blockifies any element into a block-level
box per the CSS Display spec, and an ordinary block box's `width: auto` fills its container - which
is exactly what happens for the two `<a>` rows. The two `<button>` rows do not get that same
stretch: a `<button>`'s own UA-stylesheet sizing keeps it shrink-to-fit under `display: flex` in the
browsers this was tested in, a real, documented cross-browser quirk for form controls specifically -
`<a>`/`<div>` are unaffected because they carry no such UA default. `border-top`'s own length always
matches the element's own box width, so a shrink-to-fit button's divider reads as "cut off" exactly
where the button's own content ends, rather than spanning the panel like every `<a>` row's divider
correctly does.

Only the sheet's own two non-channel rows are `<button>` (`buildTouchRoutingSheet`'s own
`onlineChatRow`/`cancelRow`, `ui/widget.ts`) - every real channel row is a real `<a>`
(`buildChannelSwitcherRow`), which is why the bug reads as "some dividers, not all".

## Scope

- Make `.ago-channel-switcher-row` (or a rule scoped narrowly enough not to touch anything outside
  the touch routing sheet, at the author's/implementer's judgment) stretch a `<button>` row to the
  same full width its `<a>` sibling rows already get - `width: 100%` is the direct fix; confirm it
  actually closes the gap live rather than assuming the one declaration is sufficient.
- Check whether this same shrink-to-fit gap exists anywhere else `.ago-channel-switcher-row` is used
  on a `<button>` - the `AboveComposer` card's own "Написать в чат"/`--dismiss` row is also a
  `<button>` sharing the identical base class, so it may carry the identical bug even though nobody
  has reported it there. Confirm live before deciding whether the fix belongs on the shared base
  class or the touch-sheet-scoped selector.

## Out of scope

- Any other visual aspect of the sheet's rows (text/icon size - `25-200`/`25-201`, already closed).

## Done when

- [ ] Both `<button>` rows in the touch routing sheet measure full panel width, matching the `<a>`
      rows - proven against a real rendered DOM, not only a CSS rule read by eye.
- [ ] The divider (`border-top`) visibly spans the full row width for every row in a real screenshot.
- [ ] The `AboveComposer` card's own `<button>` row is checked for the identical gap and either fixed
      alongside this item (if the same defect) or explicitly confirmed unaffected, with a reason.
- [ ] Every `<a>` row - unaffected before this item - is confirmed still full-width after it.
- [ ] `npm run typecheck`/`lint`/`test`/`ux-gate` all green.
