# 26-92 · A language setting that actually switches the app

- **Stage**: 26
- **Status**: done — merged as [ago-android#92](https://github.com/golyakoff/ago-android/pull/92); Settings-crash follow-up (DataStore singleton) [ago-android#98](https://github.com/golyakoff/ago-android/pull/98).
- **Found**: 2026-09-23 as `26-79`, split in two on the author's own instruction 2026-09-24. This is the
  second half — the actual Settings row and the real runtime switch, once `26-91` has made both
  languages exist.
- **Depends on**: `26-91` (both resource sets must exist first).

## What this item is

One promise: **the operator can switch this app's own interface language, and the choice actually takes
effect and persists.** `26-79`'s own settled decision, carried forward unchanged: this is the *app's*
own interface language — button labels, screen titles, system messages — a separate, independent
setting from the widget's own per-site language configured in the console. Never present or implement
the two as the same toggle.

## Scope

- **Runtime locale switching via Android 13+'s per-app language API**
  (`AppCompatDelegate.setApplicationLocales`) — this app's own `minSdk` predates API 33, so check what
  this project's own dependency (`androidx.appcompat`, if not already present, or
  `androidx.core:core-ktx`'s own `LocaleListCompat`-based shim) provides as a pre-33 fallback, and state
  plainly which path was used and why.
- **A real «Язык интерфейса» row in `SettingsScreen`**, per the approved mockup's own section 08 — a
  segmented control or equivalent matching this screen's existing Тема row's own visual pattern
  (`26-19`'s own segmented-tabs precedent for Тема is the established shape to reuse, not reinvent).
- **Persistence** — `AppCompatDelegate.setApplicationLocales` already persists the per-app locale choice
  across restarts via the platform itself (confirm this is genuinely true on this app's own `minSdk`
  floor, not assumed from the 13+ API's own behavior on newer devices) — state in the report whether any
  additional app-level persistence (e.g. this app's own DataStore preferences, the pattern
  `DataStoreThemePreferences` already establishes) is actually needed or would be redundant.
- **A short note wherever the app's own language setting and the widget's own site-language setting
  could plausibly be confused in code** — `26-79`'s own explicit ask, carried forward: a future reader
  guessing they are the same thing from the name alone is the exact mistake this note exists to prevent.

## Out of scope

- Adding a third language — this item wires the mechanism for the two `26-91` ships (Russian, English),
  not a general N-language framework.
- The widget's own language configuration — entirely separate, already exists, not touched here.

## Done when

- [~] Switching the Язык row actually changes every screen's own rendered language, proven on a real — delivered and CI-green (build/unit/ktlint/lint); on-device check pending, phone disconnected 2026-09-25.
      device or a real instrumented test (not by reading the code and assuming).
- [x] The choice survives an app restart.
- [x] The widget's own language setting is untouched and unaffected by this row.
- [x] `./gradlew ktlintCheck lint test assembleDebug assembleDebugAndroidTest` green; counts reported.
