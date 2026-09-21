# 25-198 · The `AboveComposer` card still shows inside the panel a touch visitor already routed past

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-21, the author, live on `golyakov.net` (mobile), immediately after `25-197`
  shipped - a screenshot of the real open panel on `demo-shop1` (`AboveComposer` placement) showing
  the MAX/Telegram channel-switcher card still rendered above the composer, with the composer's own
  controls visibly crowded/misaligned underneath it. The author's own words: "ты сделал только часть
  задачи... не почистил вид окна диалога от кнопок каналов, из-за этого съехали все кнопки в окне."

## What is actually true today

`25-197` added a routing sheet that intercepts a touch visitor's tap on the *closed* toggle,
offering every connected channel plus "Онлайн чат" before the chat panel ever opens. What it did
not touch is `loadChannelSwitcherCard()` (`ui/widget.ts`, `25-149`'s own renderer) - it builds the
`AboveComposer` card unconditionally whenever `session.channelLinks.length > 0` and the card has not
been dismissed, with no awareness that a touch visitor choosing "Онлайн чат" from the new sheet has
*already* been offered the identical set of channels seconds earlier.

The result on a touch device configured for `AboveComposer` (`demo-shop1`'s own placement): tap the
toggle, see the routing sheet, pick "Онлайн чат", land in a panel that shows the same MAX/Telegram
choice a second time - now competing for space with the header, the transcript and the composer in
a viewport already short on vertical room, which is the crowding the author's screenshot shows.

`25-197`'s own "Out of scope" line only excused *hover-capable* devices from any change - it never
considered what the already-built `AboveComposer`/`BelowLauncher` renderers should do on the device
class the item's whole point was to treat differently. That gap is this item's whole scope.

## Scope

- `loadChannelSwitcher()` (or the renderer it calls) gains the identical gate `toggleOpen()` already
  uses - `session.channelLinks.length > 0 && matchMedia("(hover: none)").matches` - and when it is
  true, skips building the `AboveComposer` card / `BelowLauncher` icon row entirely. The routing
  sheet is now the touch device's *only* channel-choice surface; the panel itself returns to
  exactly what it rendered before either channel-switcher placement existed - header, transcript,
  composer, nothing above it.
- A hover-capable device is unaffected: both existing placements keep rendering exactly as they did
  before `25-197`, unconditionally.
- A touch device with nothing connected is unaffected either way - both the card and the sheet
  already pay nothing when `channelLinks` is empty.

## Out of scope

- Any redesign of what the routing sheet itself shows (`25-199` is the sheet's own icon defect).
- Any change to `AboveComposer`/`BelowLauncher` behaviour for a hover-capable visitor.

## Done when

- [ ] On a `(hover: none)` device with at least one connected channel, opening the panel (by any
      path - the sheet's own "Онлайн чат" row, or a future path that opens it directly) never
      builds an `AboveComposer` card or a `BelowLauncher` icon row - proven by a real test.
- [ ] The panel's own layout on such a device is provably identical to a site with zero connected
      channels (no extra child between the header and the composer).
- [ ] A hover-capable device's `channelSwitcher.test.ts`/`channelSwitcherLauncher.test.ts` suites
      still pass unchanged.
- [ ] `npm run typecheck`/`lint`/`test`/`ux-gate` all green.
