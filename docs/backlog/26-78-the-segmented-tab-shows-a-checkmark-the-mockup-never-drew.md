# 26-78 · The segmented tab shows a checkmark the mockup never drew

- **Stage**: 26
- **Status**: done — merged as [ago-android#63](https://github.com/golyakoff/ago-android/pull/63),
  independently verified by the managing session (`./gradlew ktlintCheck lint test assembleDebug
  assembleDebugAndroidTest` green, 306 unit tests passed, 0 failures). Also fixed `TeamChatScreen.kt`'s
  own `SegmentedButton`, not named in this item's own Found section — found by grepping every
  `SegmentedButton(` call site in the repo (only three exist).
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

- [~] Диалоги's Мои/Ожидают segmented control shows no checkmark on the selected tab. **Partial**: the
      code fix (`icon = {}`) is in and independently verified by reading the diff; a real device was
      available but the app landed on the sign-in screen with no credentials available for this
      session, so the fixed screen itself was never seen live — code-level confidence only, not a
      live-device confirmation.
- [~] Записи's segmented control shows no checkmark either — same code fix, same partial: verified by
      reading the diff (it shares the identical `SegmentedButton` composable/bug), not confirmed live.
      `Команда`'s own segmented row had the identical bug and got the identical fix, found while
      grepping for every call site in the repo — not named in this item's own Found section, worth
      recording here since it was fixed under this ticket's own promise ("no Material-3-default
      checkmark on any segmented tab in this app").
- [x] `./gradlew ktlintCheck lint test assembleDebug assembleDebugAndroidTest` green — independently
      re-verified by the managing session.
