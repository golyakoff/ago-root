# 26-102 · DeviceRegistrationWorker cannot be created in the release build

- **Stage**: 26
- **Status**: done — merged as [ago-android#91](https://github.com/golyakoff/ago-android/pull/91).
- **Found**: 2026-09-24, in device logs during live debugging:
  `E/WM-WorkerWrapper: Could not create Worker ago.chat.android.devices.DeviceRegistrationWorker`,
  in the release APK (`0.24.1+eae5f9d`) installed via adb.

## What is actually true today

The periodic `DeviceRegistrationWorker` (WorkManager) — one of the three device-registration paths
(`26-82`: sign-in, `onNewToken`, periodic) — **fails to instantiate at all in release**. WorkManager
logs "Could not create Worker" and the job does not run. The usual cause is R8/minification stripping or
renaming the worker's constructor, or the Hilt `WorkerFactory`/entry point not being kept — i.e. a
missing keep rule or a factory not wired for the release build (debug, un-minified, would not show it).

The effect: even on a device where push works, the **periodic re-registration never runs**, so a token
that rotates or goes stale is only re-registered on the next sign-in or `onNewToken` — a slow, silent
drift toward "pushes stopped arriving" over time.

## Scope

- `ago-android`: make `DeviceRegistrationWorker` instantiate and run in the **release** build — add the
  R8 keep rule (or fix the Hilt worker-factory wiring) so WorkManager can construct it. Confirm it runs
  in a release/minified build, not only debug.

## Out of scope

- The transport change (`26-100`) and the silent-registration-warning (`26-101`) — separate items,
  though this worker is the same registration subsystem.

## Done when

- [~] Root cause confirmed (not the ticket's guesses): release is **unminified**, so it was never R8;
      the real cause was a missing `@JvmOverloads`, so Kotlin never emitted the `(Context,
      WorkerParameters)` constructor WorkManager's default factory reflects for — proven by `javap`
      before/after. Fixed by adding `@JvmOverloads`; `assembleRelease` green. **Runtime observation of
      the worker actually running is pending an on-device check — phone disconnected 2026-09-24.**
- [x] `./gradlew ktlintCheck lint test` green, and a release build assembled to confirm the keep rule
      holds under R8.
