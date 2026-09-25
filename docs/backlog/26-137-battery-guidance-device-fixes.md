# 26-137 · [ago-android] Battery/autostart guidance — device-test fixes (26-128 follow-up)

- **Stage**: 26 — follow-up to `26-128` (battery/autostart awareness). Found by the author on a real MIUI
  device.
- **Status**: ready.
- **Found**: 2026-09-25.

## Issues (from device testing)
1. **«Настройки батареи» opens the wrong screen.** It opens the system app-list "Расход заряда батареи
   приложением", forcing the user to find AGO Chat and drill in. It must open the **per-app** battery
   screen for AGO Chat directly — the «С оптимизацией»/«Без ограничений» dialog — i.e. the same
   `Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (`package:$packageName`) `MainActivity` already
   uses for the first-launch exemption (`MainActivity.kt:206`). Graceful fallback if unresolved. Update the
   recommendation copy to match what now opens (no "откроется системный список — найдите …").
2. **Add guidance for MIUI's "Приостановить работу приложения, если оно не используется"** (App Info →
   properties). No universal deep-link — open `ACTION_APPLICATION_DETAILS_SETTINGS` and recommend disabling
   it. Honest copy (can't read/confirm the state). Consistent with the «Режим работы»/«Автозапуск» rows.
3. **Brand name: «AGO Chat», never «АГО Чат».** Fix every recommendation string that renders "АГО Чат"
   (app_name is already "AGO Chat"; the offending text is hardcoded in the battery/autostart copy).
4. **Glyphs too thin/small.** The check-in-circle is extremely thin and the exclamation-in-circle is barely
   visible. Increase stroke weight to the max the style allows and slightly enlarge the glyphs (AgoIcons
   `strokeIcon` — the status indicators on the rows).

## Done when
- [ ] «Настройки батареи» opens the per-app unrestricted dialog directly (with fallback); copy matches.
- [ ] A recommendation + deep-link for the "pause app if unused" toggle exists, honestly worded.
- [ ] No "АГО Чат" remains — brand is "AGO Chat" everywhere.
- [ ] Check/Exclamation status glyphs are bolder and slightly larger, clearly legible.
- [ ] `ktlintCheck`, `lint`, `test`, `:app:compileDebugAndroidTestKotlin` green; strings as resources both langs.
