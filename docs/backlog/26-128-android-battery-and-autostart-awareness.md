# 26-128 · [android] Battery-mode + autostart awareness (first-launch prompt + Settings items)

- **Stage**: 26 — implementation of the author-approved battery/autostart mockup (round 3, circles
  slightly smaller). Designed with the kept-in-context worker; this is its implementation phase.
- **Status**: done — merged as `ago-android#113` (first-launch sheet + Режим работы/Автозапуск rows; permission-free intent; OEM autostart uniform UI; smaller circles). BOOT_COMPLETED inference = `26-129`.
- **Found**: 2026-09-25.

## Feature (per the approved mockup + decisions)

**A) First-launch prompt** (bottom sheet, replaces the raw system battery prompt). Yellow warning triangle
in the header. Short combined copy: (1) «Уведомления… могут не доходить… Рекомендуется режим «Без
ограничений».» → button «Настройки батареи»; (2) «Также рекомендуется установить программу в автозапуск,
чтобы не пропустить уведомления после перезагрузки.» → button «Настройки автозапуска»; then checkbox
«Больше не показывать это окно»; caption «Это можно изменить позже в Настройки → Режим работы».
**Non-blocking**: closing/dismissing (even with "don't show again") never gates app usage. Persist the
"don't show again" flag (a small store like `AppLanguageDataStore`/`ThemePreferences`). Trigger once from
`AgoChatApplication.onCreate()` (or `MainActivity`), the "once, here" convention.

**B) Settings → Уведомления — two new rows** (each: left status circle glyph — **slightly smaller circles**
than the round-3 mockup — humanized value, expandable card with explanation + its system-dialog button):
- «Режим работы: Экономия энергии / Без ограничений» — battery optimization.
- «Автозапуск: Выключено / Включено» — autostart after reboot.

## Detection & intents
- **Battery mode**: read `PowerManager.isIgnoringBatteryOptimizations(packageName)` (green `check` circle =
  unrestricted; orange `exclamation` circle = restricted). Button opens `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`
  (the permission-FREE system list — no `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission). Put the detector
  behind a port like `NotificationPermissionChecker`; refresh on `ON_RESUME`.
- **Autostart**: NO AOSP read API exists. Show it as a **recommendation, not a sensor** — orange
  `exclamation` on OEMs known to restrict (Xiaomi, Huawei, Oppo, vivo, Realme via `Build.MANUFACTURER`),
  green on Samsung/stock; the expanded card states plainly it's a recommendation, not a verified status.
  Button opens the OEM autostart screen via the reverse-engineered `ComponentName` intents
  (Xiaomi `com.miui.securitycenter/.permcenter.autostart.AutoStartManagementActivity`; Huawei
  `com.huawei.systemmanager/.startupmgr.ui.StartupNormalAppListActivity`; Oppo/ColorOS
  `com.coloros.safecenter/.permission.startup.StartupAppListActivity`; vivo/Realme similar), each wrapped in
  try/catch with a plain-text fallback caption if it doesn't resolve. **UI is uniform — never show an OEM
  name**; the button is always «Настройки автозапуска».
- Glyphs: real Material Symbols `check` / `exclamation` (not hand-approximated); `warning` triangle only in
  the sheet header. Strings as resources, ru + en. Branded colors (AgoLive green, an amber for orange).

## Out of scope
- The BOOT_COMPLETED autostart-inference signal — separate follow-up `26-129`.
- No `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` manifest permission (Option 2 chosen).

## Done when
- [x] First-launch prompt (combined, non-blocking) + the two Settings rows with correct glyphs/detection and
      the system-dialog buttons per the mockup; uniform UI (no OEM names); circles slightly smaller.
- [x] `./gradlew ktlintCheck lint test :app:compileDebugAndroidTestKotlin` green; tests for battery
      detection state→glyph and the OEM intent selection/fallback; counts reported.
