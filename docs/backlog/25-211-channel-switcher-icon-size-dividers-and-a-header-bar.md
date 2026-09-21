# 25-211 · Channel switcher: bigger icons, a divider between every row, and a header bar

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-22, the author, live against a local sizing picker (icon scale 100-200%, row
  padding, a header-bar preview) built to answer "how much bigger" without guessing. Final picks,
  read directly off the picker: icon size **175% → 28px** (from the current 16px/1rem baseline,
  `.ago-channel-switcher-row`'s inherited font-size, since the icon's own `width="1em" height="1em"`
  attribute already resolves against it), row vertical padding **0.625rem → 10px** (was `0.5rem`/8px).
- **Depends on**: `25-210` (the header bar's own title text and the setting behind it) - this item
  renders whatever that one produces; it does not invent its own title source.

## What is actually true today, confirmed against real code

`ago-widget/src/ui/styles.css`'s `.ago-channel-switcher-row` sets the icon/label font-size (currently
inherited, unset - 1rem/16px) and `padding: 0.5rem 0.75rem`. Only `.ago-channel-switcher-row--open-chat`
(the "Онлайн чат" row, the *last* row in the banner) carries a divider - `border-top: 0.0625rem solid
#e5e7eb`. Every other row (one per connected channel) has no divider between it and its neighbour.
`buildChannelSwitcherBanner` (`ui/widget.ts`) builds the banner with no header element at all - it is
a bare white rounded card, channel rows straight through to the "Онлайн чат" row.

## Scope

- **Icon size**: `.ago-channel-switcher-row` gets an explicit `font-size: 1.75rem` (28px - the icon's
  own `1em` sizing attribute resolves against this). **The label text must not grow with it** - give
  `.ago-channel-switcher-row span` (or an equivalent scoped selector) its own `font-size: 1rem` so the
  label stays exactly where it reads today; only the icon and the row's own vertical rhythm change.
  Confirm live (a screenshot or the picker's own reproduction) that this matches the approved 28px,
  not an approximation.
- **Row height**: `.ago-channel-switcher-row`'s `padding` becomes `0.625rem 0.75rem` (10px vertical,
  horizontal unchanged).
- **A divider between every row, not only before "Онлайн чат."** Move the `border-top` rule from
  `.ago-channel-switcher-row--open-chat` onto every row after the first - the standard "divider
  between siblings" shape (`:not(:first-child)` on the shared row class, scoped to rows inside
  `.ago-channel-switcher-banner` specifically, since the touch-sheet and below-launcher placements
  are explicitly out of scope below and must not pick this up by accident). `--open-chat` keeps its
  own accent **color**, just not sole ownership of the divider.
- **A header bar atop the banner**, sibling of the channel rows inside `.ago-channel-switcher-banner`,
  first child: dark background (a gray in the neighbourhood of `#374151`/`#384454` - already this
  file's own established neutral, see `25-205`/`25-206`'s own color decision - pick one and say which
  and why), white bold text, **no close control of any kind** - this banner has nothing to dismiss
  that clicking outside/re-hovering-away does not already handle. Rounded top corners matching the
  banner's own `border-radius: 0.75rem` (only the top two corners, the banner's own `overflow: hidden`
  already clips the rest). Its text is whatever `25-210` produces - read the widget's own resolved
  greeting the identical way the real `.ago-header h1` does, never a second hardcoded copy of the
  string.
- **`BelowLauncher` and the touch-sheet placements are explicitly untouched** - this item's scope is
  `buildChannelSwitcherBanner`/`.ago-channel-switcher-banner` only, the same scoping discipline
  `25-200`/`25-201`/`25-202` already applied when they changed the touch-sheet's own sizing without
  touching this banner.

## Out of scope

- The header bar's own title text or its configurability - `25-210`'s entire scope.
- `BelowLauncher`'s circular launcher-icon row (`.ago-channel-switcher-launcher-icon`) and the touch
  routing sheet (`.ago-touch-routing-row`) - neither renderer is this item's banner.
- Any change to which channels appear, their order, or their brand icons.

## Done when

- [ ] The icon renders at 28px (1.75rem) in the banner, confirmed live, with the label text
      unchanged at its current size.
- [ ] Row vertical padding is 0.625rem (10px), confirmed live.
- [ ] A divider line appears between every pair of adjacent rows inside the banner, including between
      two connected-channel rows - not only before "Онлайн чат."
- [ ] The header bar renders above the first row, dark background, white bold text, no close control,
      showing `25-210`'s configured-or-default greeting - proven for both an unconfigured site (shows
      the built-in default) and a site with an override set.
- [ ] `BelowLauncher`'s row and the touch-routing sheet are provably unchanged - a screenshot or test
      of each showing the pre-existing sizes/dividers.
- [ ] `npm run typecheck`/`lint`/`test`/`build`/`ux-gate` all green in `ago-widget`.
