# 26-78 · The segmented tab shows a checkmark the mockup never drew

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, by the author, live on a real device — the screenshot at the very start of
  this session's UI-review conversation showed "✓ Мои 9" atop Диалоги's segmented control.

## What is actually true today, confirmed against real code

The mockup Artifact's own `.seg`/`.seg div.on` rule (`AGO Chat Design`, section "02 · Диалоги") never
draws a checkmark — `.seg div.on{background:var(--brand-tint); color:var(--brand-deep)}` is a
background/color change only, confirmed by reading the Artifact's own source directly.

The checkmark is Material 3's own default: `ConversationListScreen.kt:200-206`'s
`SegmentedButton(...)` call does not pass an `icon` parameter, so it falls back to
`SegmentedButtonDefaults.Icon(selected)`, which draws a check for the selected segment. This is a real
app/mockup divergence, not a mockup problem — the mockup needs no change.

## Scope

One promise: **the segmented tab shows only a background/color change on its selected item, no
checkmark**, matching the mockup exactly.

- `ConversationListScreen.kt`'s `SegmentedButton(...)` call passes `icon = {}` (Material 3's own
  documented way to suppress the default selected-check icon).
- Check `Записи`'s own Ожидают/Утверждены/Клиенты segmented row (`bookings/BookingsScreen.kt`) for the
  identical `SegmentedButton` usage — if it uses the same composable without overriding `icon`, it has
  the identical bug and gets the identical fix in the same change (same promise: "no
  Material-3-default checkmark on any segmented tab in this app").

## Out of scope

- Any other `SegmentedButton` styling change. This item is only about the default check icon.

## Done when

- [ ] Диалоги's Мои/Ожидают segmented control shows no checkmark on the selected tab, on a real
      device.
- [ ] Записи's segmented control (if it shares the same underlying composable/bug) shows no checkmark
      either, on a real device.
- [ ] `./gradlew ktlintCheck lint test assembleDebug assembleDebugAndroidTest` green.
