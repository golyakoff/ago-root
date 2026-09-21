# 25-204 · `AboveComposer` becomes a hover-revealed banner above the toggle, not a card inside the panel

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-21, the author, live on `golyakov.net` (desktop) - tested the console's own
  "Баннеры над окном диалога" placement a second time and found it unchanged: the channel card still
  renders **inside** the open panel, above the composer, exactly as before. The author's own words:
  "я же уже объяснял, что надо их убрать из окна диалога и сделать их именно НАД окном диалога" -
  referencing a Jivo screenshot (icon+text rows, floating above the widget's own launcher) a second
  time.

## What is actually true today, confirmed against real code before this was filed

The console's own label for this placement, verbatim (`ago-console/src/i18n/ru.ts:413`,
`en.ts:415`): **"Баннеры над окном диалога"** / **"Banners above the chat window"**. The wire value
is `"AboveComposer"` (`Ago.Chat.Domain.ChannelSwitcherPlacement`). What it actually renders
(`loadChannelSwitcherCard`, `ago-widget/src/ui/widget.ts`): `this.composer.parentElement?.insertBefore(card, this.composer)`
- a sibling of the composer, **inside the already-open chat panel**, directly above the input box.
The label has been wrong since `25-149` shipped it; this is a real defect, not a design preference.

The only placement that is genuinely **outside** the panel today is `BelowLauncher` ("Круглые значки
под окном диалога") - a row of icon-only circles beside the toggle, hover-revealed since `25-192`,
with the hover-island gap fix from `25-203`. **`BelowLauncher` is unaffected by this item and stays
exactly as it is** - confirmed with the author directly: this item only changes what `AboveComposer`
renders.

## Scope, confirmed with the author directly (not assumed)

- **This replaces `AboveComposer`'s current rendering entirely.** The card-inside-the-panel code path
  (`loadChannelSwitcherCard`) is retired for hover-capable devices; `AboveComposer` now means a
  floating panel that appears **above the toggle, outside the chat panel**, on hover - the console's
  own label becomes true rather than corrected to match the wrong behaviour.
- **Content matches the mobile touch routing sheet's own rows** (`25-197`'s `buildTouchRoutingSheet`/
  `buildChannelSwitcherRow`): one row per connected channel (real brand icon + name, real link,
  `target="_blank" rel="noopener noreferrer"`), plus a final row that opens the chat panel for real
  (`open()`, not merely focusing the composer - the panel is closed when this banner is showing,
  unlike the old inside-panel card). Reuse `buildChannelSwitcherRow` - do not re-invent row rendering
  a third time.
- **No "Отмена"/cancel row.** Dismissal is purely "the pointer left the hover region", matching
  `BelowLauncher`'s own model - not a click target, because nothing in the Jivo reference or the
  author's own description shows one.
- **The exact `25-203` hover mechanism, explicitly required by the author**: a hover region spanning
  both the toggle and the new banner, with a grace period after the pointer leaves either one before
  it actually hides (`isHoverRegionActive`/`HOVER_REGION_LEAVE_GRACE_MS`/`enterHoverRegion`/
  `scheduleHoverRegionLeave`/`cancelHoverRegionLeaveTimer`, `ui/widget.ts`). Reuse those names/that
  mechanism directly rather than writing a second, parallel hover-region implementation - if
  `BelowLauncher` and this banner need to be hoverable *independently* (a site could in principle be
  configured for either, never both at once per `parseChannelSwitcherPlacement`, so in practice only
  one hover-region instance is ever live at a time), confirm that live rather than assuming it, but do
  not fork the mechanism into two copies if one already covers both.
- **Position**: anchored above the toggle, mirroring `.ago-position-left`/right the same way `.ago-panel`
  already does. Unlike the mobile touch sheet (flush to the viewport's bottom edge), this banner keeps
  a real bottom margin - the author's own words: "снизу тоже отступ, а не 'до самой нижней границы'
  как у телефонного тапа". The natural anchor is the same `bottom: 4.25rem` offset `.ago-panel`
  itself already uses, so the banner sits where the chat panel would, not flush to the screen edge.
- **Decide, and state the decision plainly rather than silently picking one**: does this new banner
  keep any form of `storage.getChannelSwitcherDismissed()` persistence (the old card's "seen once,
  never again" memory), or does it behave like `BelowLauncher` - purely a function of live hover
  state, no persisted memory at all? The author's own repeated comparison to `BelowLauncher` and to
  the mobile sheet (both stateless) is the lean, but this item should say so explicitly rather than
  leave it to be discovered.

## Out of scope

- `BelowLauncher` - untouched, confirmed with the author.
- The mobile touch routing sheet (`25-197`/`25-198`/`25-199`/`25-200`/`25-201`) - untouched, a
  different device class and a different trigger (tap, not hover).
- Any change to the console's own labels/config - they already say the right thing; only the widget's
  own behaviour is wrong.

## Done when

- [ ] On a hover-capable device with `AboveComposer` configured, hovering the toggle reveals a
      floating panel **above the toggle, outside the chat panel** - never inside it, never a sibling
      of the composer.
- [ ] The panel's own rows are built via the shared `buildChannelSwitcherRow`, one per connected
      channel, plus a row that opens the chat panel for real.
- [ ] The hover region spans both the toggle and the new banner with the identical `25-203` grace-
      period mechanism, reused rather than re-implemented - a pointer crossing the gap between them
      never hides the banner mid-crossing (verified the same way `25-203` verified it: real
      `PointerEvent` dispatch with controlled timing against a real browser, not only jsdom).
- [ ] The banner sits with a real bottom margin (anchored the same way `.ago-panel` is), never flush
      to the viewport's bottom edge.
- [ ] The dismiss-persistence question is answered explicitly, with a stated reason, not left
      implicit.
- [ ] `BelowLauncher` is provably unaffected - every existing `channelSwitcherLauncher.test.ts` test
      still passes unchanged.
- [ ] The old inside-panel `loadChannelSwitcherCard` rendering no longer runs for `AboveComposer` on
      a hover-capable device - confirmed by a test that finds no `.ago-channel-switcher` card inside
      the panel when the banner is what's showing.
- [ ] `npm run typecheck`/`lint`/`test`/`ux-gate` all green.
