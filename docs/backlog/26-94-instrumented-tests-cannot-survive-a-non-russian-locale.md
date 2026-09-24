# 26-94 · The instrumented test suite cannot survive a non-Russian locale, on device or in CI

- **Stage**: 26
- **Status**: done — merged as [ago-android#83](https://github.com/golyakoff/ago-android/pull/83).
  Confirmed live: a real GitHub CI run of this exact fix passed all 14 previously-broken classes on the
  real `en-US` emulator. `LocaleForcingTestRunner` calls the platform `LocaleManager` directly in
  `onCreate`, before `Instrumentation` creates the target `Application` — not
  `AppCompatDelegate.setApplicationLocales`, the item's own first-suggested API, which decompiling
  `androidx.appcompat:appcompat:1.8.0` showed to be a dead end for an app with no `AppCompatActivity`
  anywhere in these flows. One follow-up class (`DialoguesTabUnreadBadgeTest`, written by a parallel
  `26-46` after this item started) needed a second, unrelated fix — `useUnmergedTree = true`, since
  `NavigationBarItem` merges its icon and label into one semantics node.
- **Found**: 2026-09-24, landing `26-91` — adding `values-en/strings.xml` made 14 test classes (42
  test methods) fail on GitHub's CI emulator, which boots `en-US`. `26-91`'s own PR (`ago-android#74`)
  excludes those 14 classes via `@FlakyOnCi` to keep `publish-apk` unblocked; this item is the real fix
  that lets them come back into the gate.

## What is actually true today, confirmed by four real, failed attempts

Before `values-en/strings.xml` existed, an English-locale device fell back to the default `values/`
resource set (Russian) for lack of any alternative — so the CI emulator's own `en-US` locale and every
test's hardcoded Russian-text assertion agreed by accident. The moment a real English resource set
existed, that stopped being true: **any English-locale device — the CI emulator or a real operator's
real phone — now genuinely renders English**, and nothing in the app controls that yet (`26-92`, the
in-app language toggle, has not started).

Three real, distinct mechanisms to force the CI emulator into `ru-RU` were tried, in order, on the real
`ago-android#74` PR, and none worked:

1. `adb shell settings put system system_locales ru-RU` + `adb shell am broadcast -a
   android.intent.action.LOCALE_CHANGED` — the broadcast is a protected one; `adb shell` (uid 2000)
   cannot send it at all (`SecurityException`), so the whole `&&`-chained CI script exited before
   `gradlew` ever ran.
2. The same, with `adb root` first (elevates to uid 0, which the framework does permit) — the broadcast
   now sends without error, but **the app still rendered English**. Writing `system_locales` and then
   manually broadcasting `LOCALE_CHANGED` does not itself run the actual reconfiguration
   `LocalePicker.updateLocales()` performs internally (an `IActivityManager.updateConfiguration()`
   call) — nothing reachable from a shell broadcast triggers that, so the write was silently inert.
3. Boot-time `-prop persist.sys.locale=ru-RU -prop persist.sys.language=ru -prop persist.sys.country=RU`
   via `emulator-options` — rejected outright by this emulator build: `unexpected '-prop' value
   ('persist.sys.locale=ru-RU'), only 'qemu.*' properties are supported`.

Each attempt cost a full CI run (~6-8 minutes) to disprove. `.github/workflows/ci.yml`'s own comment on
the `instrumented-tests` job records this history for whoever picks this up next.

**The real, live consequence is bigger than CI**: any real operator whose phone's system language is
English already sees the app partially or fully in English today, with no way to choose Russian instead
— not a bug in the resources themselves, just an unreviewed, untested surface the moment `values-en`
existed.

## Scope

One promise: **the instrumented test suite passes regardless of the *device's* locale**, because it
stops depending on the device's locale at all.

The right mechanism is almost certainly forcing the **app's own** locale inside the test process,
rather than continuing to fight the device/emulator's locale from outside it:

- `androidx.appcompat`'s per-app language API (`AppCompatDelegate.setApplicationLocales(LocaleListCompat
  .forLanguageTags("ru"))`) if this project already depends on AppCompat, set once per test run (a
  shared `TestRule`, a custom `AndroidJUnitRunner`, or an `@Before` in a common base class — investigate
  what these 14 files actually share today, since none currently show a common base). If AppCompat is
  not already a dependency, weigh adding it against hand-rolling the equivalent
  `Locale.setDefault`-plus-`Configuration`-override approach and say which and why (`CLAUDE.md`'s "no
  package without saying what it replaces" rule applies here too, even though this is a test-only
  concern).
- Whatever the mechanism, it must not depend on `adb`, root, or any device/emulator flag — the CI
  environment already can't be trusted to control this, per the three failures above, and a real
  device certainly can't be told to boot in a particular locale for a test run at all.
- Once proven working, remove `@FlakyOnCi` from the 14 classes `26-91` added it to and confirm all 42
  previously-failing tests pass in a real, non-cached CI run.

## Out of scope

- The in-app language *toggle* (`26-92`) — a real user-facing settings control, a different promise.
  This item only makes the *test suite* immune to locale, not the product.
- Rewriting any of the 42 assertions to read expected text from string resources instead of literals —
  a legitimate alternative fix, but a much larger diff across 14 files for the same outcome; only take
  this path if forcing the app's own locale turns out to be genuinely infeasible, and say why.

## Done when

- [x] All previously-failing tests across the 14 classes (70 methods, not 42 — `@FlakyOnCi` is
      class-level, so the earlier count undercounted) pass in a real CI run, with `@FlakyOnCi` removed
      from every one of them — confirmed on `ago-android#83`'s own real GitHub Actions run.
- [x] The mechanism does not depend on the device or emulator's own locale — proven by reasoning
      (`LocaleForcingTestRunner`'s own doc comment) and by the real CI run passing on the emulator's
      native `en-US` boot locale.
- [x] `./gradlew ktlintCheck lint test assembleDebug` and a real `connectedDebugAndroidTest` run both
      green — 435 unit tests locally, and the full CI instrumented run green on the real emulator.
- [x] `docs/architecture.md` gains "Pinning the locale instrumented UI tests render against (26-94)".
