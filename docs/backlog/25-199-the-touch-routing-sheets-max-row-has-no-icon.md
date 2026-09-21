# 25-199 · The touch routing sheet's MAX row has no icon

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-21, the author, live on `golyakov.net` (mobile), same report as `25-198`: "на
  тапе в меню нет иконки Max" - every other channel row in the routing sheet (`25-197`) shows its
  brand mark; the MAX row does not.

## What is actually true today, and the likely cause

`buildChannelSwitcherRow()` (`ui/widget.ts`) is reused unchanged by both the `AboveComposer` card
and the new touch routing sheet (`25-197`) - it calls `buildBrandIcon(link.kind)` for every row
unconditionally, so nothing in the row-building code itself special-cases MAX or skips its icon.
The `AboveComposer` card renders MAX's icon correctly (confirmed in the author's own earlier
screenshot of that card), so the icon tree itself (`CHANNEL_ICON_TREES.Max`) is not simply broken.

**The one thing that actually is MAX-specific**: `CHANNEL_ICON_TREES.Max` is the *only* brand icon
built from `<defs>` + `<linearGradient>`/`<radialGradient>` elements carrying fixed `id`s (`a`, `b`,
`c`, `d`) referenced via `href="#a"` etc. (`widget.ts` ~L313-383) - every other brand (`Telegram`,
`WhatsApp`, `Vk`) is flat `fill="#hex"` paths with no `id` at all. `loadChannelSwitcherCard()` builds
the `AboveComposer` card - MAX icon included - **the moment the session resolves, regardless of
whether the panel is open** (its own doc comment: "so an auto-opened panel gets it too"), so a
second `buildBrandIcon("Max")` call from the touch sheet, moments later, appends a *second* SVG
carrying the identical `id="a"`/`id="b"`/`id="c"`/`id="d"` into the same shadow root. Two elements
sharing an `id` inside one document (a shadow root is its own `id` scope, but does not stop two
children of it from colliding) is invalid, and which copy's `<defs>` a browser actually resolves
`href="#a"` against is not something either icon's own markup controls - this is a strong
candidate, not yet proven against the live DOM, for why MAX's icon specifically goes missing only in
the second place it is built. Confirm by inspecting the real shadow root before fixing rather than
assuming this is the whole story.

## Scope

- Whatever the confirmed cause turns out to be, `CHANNEL_ICON_TREES.Max`'s row renders its full
  brand mark wherever `buildChannelSwitcherRow`/`buildBrandIcon("Max")` is called - including when
  more than one instance of it exists in the same shadow root at once (the `AboveComposer` card and
  the touch routing sheet, concurrently, is the real case this item exists for). If the `id`
  collision is confirmed, the fix makes each built instance's internal `id`s unique to that instance
  (a per-call suffix is the obvious shape) rather than fixed literals.
- A regression test that builds two MAX rows in the same document and asserts the second one's
  gradient still paints (or, short of a real paint assertion, that its `id`s do not collide) -
  proven failing against today's code before the fix, passing after.

## Out of scope

- `25-198`'s own defect (the card appearing at all on a touch device) - fixing that would make this
  item's own reproduction path (two MAX icons at once) rarer but not impossible (`BelowLauncher` +
  the sheet, or the card on a hover device that later narrows to touch mid-session), so this item
  stands on its own regardless of `25-198`'s outcome.

## Done when

- [ ] The real cause is confirmed against a live or test DOM before any fix is written.
- [ ] A test proves the MAX icon renders correctly when it is the only instance in the document.
- [ ] A test proves the MAX icon renders correctly when a second instance already exists in the same
      document - the actual shape of this bug - fails against today's code, passes after the fix.
- [ ] Every other brand icon (`Telegram`/`WhatsApp`/`Vk`) is provably unaffected by the fix.
- [ ] `npm run typecheck`/`lint`/`test`/`ux-gate` all green.
