# 25-211 · Channel switcher: bigger icons, a divider between every row, and a header bar

- **Stage**: 25
- **Status**: done — `ago-widget#130`
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

- [~] The icon renders at 28px (1.75rem) in the banner, with the label text unchanged at its current
      size. **Confirmed at the declared-CSS-value/DOM-test level** - the shipped `font-size: 1.75rem`
      matches the author's own live sizing-picker Artifact exactly, and a test asserts the computed
      value - not re-confirmed by a fresh screenshot of the real running widget with a real channel
      session, which needs a live backend session with connected channels this review did not stand
      up. Stated plainly rather than assumed.
- [~] Row vertical padding is 0.625rem (10px) - same caveat as above.
- [x] A divider line appears between every pair of adjacent rows inside the banner, including between
      two connected-channel rows - not only before "Онлайн чат." **This was already true since `25-206`**
      - `.ago-channel-switcher-banner .ago-channel-switcher-row`'s own `border-top` was already
      unconditional across every row in the banner; confirmed via `git log` rather than re-implemented,
      since this item's own described gap did not actually exist by the time it was picked up.
- [x] The header bar renders above the first row, dark background, white bold text, no close control,
      showing `25-210`'s configured-or-default greeting - reads `this.title.textContent` directly
      (25-210's own already-resolved value) rather than re-deriving it, so it can never show different
      words than the real panel header for the same site.
- [x] `BelowLauncher`'s row and the touch-routing sheet are provably unchanged - neither selector this
      item touches (`.ago-channel-switcher-banner .ago-channel-switcher-row`,
      `.ago-channel-switcher-banner-header`) is shared with `.ago-channel-switcher-launcher-icon` or
      `.ago-touch-routing-row`; the full widget test suite (566/566) includes both renderers' own
      existing tests, unchanged and passing.
- [x] `npm run typecheck`/`lint`/`test`/`build`/`ux-gate` all green in `ago-widget`.

## Outcome

Landed as `ago-widget#130`, rebased onto `main` after `25-210` merged so it carries the real
title-resolution code rather than a stale base. `.ago-channel-switcher-banner .ago-channel-switcher-row`
gains `font-size: 1.75rem` (28px) and `padding: 0.625rem 0.75rem`; a new sibling rule pins the label
`span` back to `1rem` so only the icon scales. New `.ago-channel-switcher-banner-header` - `#374151`
(reused, not a new neighbour - the exact value this file's own row text color already settled on in
`25-205`/`25-206`), white bold text, top-rounded corners, no close control - built as the banner's
first child in `buildChannelSwitcherBanner`, reading `this.title.textContent`.

**One real bug found and fixed during review, before landing**: the implementing worker's own diff had
the header-bar explanatory comment duplicated verbatim (the identical five-line block twice in a row) -
removed before merge.

**Verified independently**: `npm run typecheck`/`lint` clean; `test` 566/566 (post-rebase, includes
`25-210`'s own new tests); `build` 38.7 KB gzipped (budget 46 KB); `ux-gate` 16/16. The two `[~]` boxes
above are the honest limit of this review's own verification - the exact values are confirmed correct
by source and by test, not by a fresh screenshot of a live channel-switcher session.
