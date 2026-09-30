# 26-328 · [android] Huawei (EMUI/HarmonyOS): autostart & battery system-dialog buttons do not open

- **Stage**: 26
- **Status**: ready — on-device verification required (Huawei)
- **Found**: 2026-09-30, first real device (Алёна, Huawei).

  First real-device failure (Алёна's Huawei): the app's «Настройки автозапуска» and battery-mode buttons did not open the corresponding system screens.
  
  **Diagnosis (from code):**
  - Autostart: `AutostartAdvisor.autostartTargetFor("huawei")` returns a SINGLE component `com.huawei.systemmanager/.startupmgr.ui.StartupNormalAppListActivity`. Huawei has used several component names across EMUI/HarmonyOS versions, and newer builds block launching `systemmanager` components from third-party apps (ActivityNotFoundException/SecurityException). `openAutostartSettings` then catches and silently does nothing → no window opens.
  - Battery: `openBatteryOptimizationSettings` chains REQUEST_IGNORE_BATTERY_OPTIMIZATIONS → IGNORE_BATTERY_OPTIMIZATION_SETTINGS → APPLICATION_DETAILS_SETTINGS (always present). It should fall back, but it also failed to help on her device — needs on-device confirmation of what actually happened.
  
  **Approach (best-effort hardening — Huawei is undocumented, so this can't be guaranteed blind):**
  1. Autostart Huawei: try a CHAIN of known Huawei components (multiple EMUI/HarmonyOS variants: `startupmgr.ui.StartupNormalAppListActivity`, `optimize.process.ProtectActivity`, `appcontrol.activity.StartupAppControlActivity`, …) via the existing startFirstResolvable pattern; if none resolves, fall back to launching the Phone Manager app (`com.huawei.systemmanager` launcher), then App-info.
  2. Make the same multi-component + phone-manager fallback shape available for the other restrictive OEMs (Xiaomi/Oppo/vivo also drift across versions).
  3. Ensure a PROMINENT, always-visible manual-steps caption on each button ("Диспетчер телефона → Запуск приложений → включите AGO") so that when auto-launch fails the user still knows where to go — auto-launch is a convenience, the guidance is the guarantee.
  4. Battery: confirm on-device why the fallback didn't help; ensure App-info fallback truly fires.
  
  **Closing step (author/user-gated):** verify on Алёна's Huawei (and ideally one more EMUI/HarmonyOS build) that a button now opens a usable screen or the guidance is clear. Cannot be fully verified without the device.
  
  Related: push reliability (RuStore/FCM, OEM app-killing) — this is the same keep-alive surface. Details to live in docs/backlog/26-328.
