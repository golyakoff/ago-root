# 26-36 · Drive back-press tests through `onBackPressedDispatcher`, not the system input pipeline

- **Stage**: 26
- **Status**: done — merged as `ago-android#40`. Real CI run (`35754803964`) confirmed independently by
  the managing session via the run's own downloaded JUnit XML: all five `BackContract*Test` files
  executed (10 tests total), 0 failures.
- **Found**: 2026-09-22, by the author, pushing back on the shape of `26-25`→`26-27`→`26-33`→`26-35`
  after two consecutive real CI runs of `26-33`'s identical fix disagreed (one clean, one failing 7
  tests): "мы что, изобрели какой-то тест, который не может выполниться на гитхаб раннере? как люди
  проверяют подобные вещи, ты что-то перемудрил, может? можно проще проверить как-то то, что ты
  проверяешь? поищи решение для исходной задачи..." A real web search (not memory) confirmed the
  concern was right.

## What four items chasing the same failure actually did, and why it kept recurring

- `26-25`: replaced `Espresso.pressBack()` with `UiDevice.pressBack()` to escape
  `RootViewWithoutFocusException` — a real, correctly-diagnosed fix for that specific exception.
- `26-27`: added `UiDevice.waitForIdle()` because `UiDevice.pressBack()` has no synchronization to
  Compose/Espresso's idle state at all — also correctly diagnosed, still insufficient on real CI.
- `26-33`: converted every post-press assertion to a `composeTestRule.waitUntil` poll (12s budget) —
  passed one real CI run, failed the very next one on the identical commit, every failure a full
  12-second timeout with zero progress.
- `26-35`: tried to stop gating CI on these five files entirely (first via a broken comma-separated
  `notClass` argument that silently excluded only one of five classes, then via a `@FlakyOnCi`
  annotation) — the right instinct given the evidence in hand, but built on top of the same shaky
  foundation rather than questioning it.

**Every one of these was a real, well-reasoned fix for a real problem it found — and every one was
fixing the wrong layer.** `UiDevice.pressBack()` dispatches a *system*-level key event through
UiAutomator's accessibility-event pipeline: emulator → Android's input system → accessibility service →
the app. That pipeline is exactly what a headless, hardware-acceleration-dependent CI emulator is least
reliable at, and no amount of polling on the *receiving* end fixes a press that the *pipeline itself*
occasionally never delivers - which is exactly what "timed out after the full 12000ms with zero partial
progress" looks like, as opposed to "arrived late."

## The actual fix, confirmed by a real search rather than assumed

Every one of these tests exists to prove **this app's own `BackHandler`/`androidx.activity.compose`
back-handling logic** - not "does Android's OS-level back button work," which is Android's own concern,
proven by Android's own test suite, not this app's. `BackHandler` is registered on the Activity's
`OnBackPressedDispatcher`, and that dispatcher can be invoked **directly, in-process, synchronously**,
with no system input event, no UiAutomator, no accessibility service, and therefore nothing for a
headless CI emulator's flakiness to ever touch:

```kotlin
composeTestRule.activityRule.scenario.onActivity { activity ->
    activity.onBackPressedDispatcher.onBackPressed()
}
```

This is a real, standard, documented pattern (confirmed via web search, not memory - see the previous
chat turn's cited sources) for testing back-press behavior that lives behind `OnBackPressedDispatcher`,
which is exactly where Compose's own `BackHandler` lives. It removes the actual race, rather than
racing it for longer or refusing to look at the result.

## Scope

- `SystemBackPress.kt` (`app/src/androidTest/kotlin/ago/chat/android/testing/`): replace the
  `UiDevice`-based `pressSystemBack()` with a dispatcher-based call. Rename it (`pressSystemBack` no
  longer describes what it does — the function no longer touches the system input pipeline at all;
  pick a name that says what it now does, e.g. `triggerBackPress()` or `pressBack()`) and update every
  call site. Confirm the correct thread-marshalling API against this project's actual
  `createAndroidComposeRule` version (`...junit4.v2`) rather than assuming `activityRule.scenario
  .onActivity { }` is exactly right without compiling and running it.
- Remove the twelve-second `composeTestRule.waitUntil` polling this item's own predecessor (`26-33`)
  added at every call site across the five `BackContract*Test` files, replacing each with whatever
  minimal, real synchronization is actually needed after a synchronous, already-completed dispatcher
  call (likely just `composeTestRule.waitForIdle()` for the following recomposition to settle - a
  real wait for real, already-triggered work, not a wait for an external event that may never arrive).
- Remove the `@FlakyOnCi` annotations and `FlakyOnCi.kt` from the five `BackContract*Test` files
  (`26-35`'s own work, never merged) and the `.github/workflows/ci.yml` `notAnnotation` exclusion -
  these tests are expected to be reliable again and belong back in the normal CI gate.
- `app/build.gradle.kts`: `androidx.uiautomator` (`androidTestImplementation(libs.androidx.uiautomator)`,
  line ~283) is used **only** by `SystemBackPress.kt` (confirmed by a full-source grep) - remove the
  dependency if nothing in this item's own rewrite still needs it.
- The one test needing special handling: `BackContractBottomBarTest.clause3_backOnDialogiExitsTheApp`
  currently reads `composeTestRule.activityRule.scenario.state == Lifecycle.State.DESTROYED` because
  `UiDevice.pressBack()` has no "nothing consumed this" signal. Confirm whether invoking
  `onBackPressedDispatcher.onBackPressed()` with no enabled callback still reaches the same real
  production fallback (the Activity's own default back behavior, which finishes it) - it should, since
  this is the same dispatcher `BackHandler(enabled = false)` falls through to in production - but prove
  it rather than assume it, since this is exactly the kind of assumption `26-27`'s own predecessor got
  wrong.

## Out of scope

- `AssignmentNeverNavigatesTest` or any other instrumented test not in the five `BackContract*Test`
  files - not shown to share this problem, not touched here.
- Re-litigating `26-25`'s own diagnosis of `RootViewWithoutFocusException` - that exception is real and
  `Espresso.pressBack()` is still not being reintroduced; this item moves to a third mechanism, not
  back to the first.

## Verify for real - this item exists because "verified locally" has already been wrong twice here

- `./gradlew ktlintCheck lint test assembleDebug assembleDebugAndroidTest` green.
- Run all five `BackContract*Test` files repeatedly against a real device/emulator (the standing bar
  this whole chain has used) - report exact counts, not one clean run.
- **This item's own explicit bar, unchanged from `26-33`'s**: a real, managing-session-watched green CI
  run of `instrumented-tests` is what closes this out. Given the *reason* for this rewrite is that a
  headless CI emulator's input pipeline is the actual unreliable component, and this fix's whole point
  is to stop depending on that pipeline, a real CI run is the one environment where this claim can
  actually be tested honestly - state plainly if a real CI run isn't obtained before reporting.
- If a real CI run's `instrumented-tests` job still fails on one of these five files after this change,
  the failure will no longer be a `ComposeTimeoutException` (there is nothing left to time out on an
  in-process, synchronous call) - a different failure shape at that point means a different, real bug
  in the rewrite itself, not a repeat of this same flake, and should be diagnosed as such rather than
  assumed to be "the same problem again."

## Done when

- [x] `pressSystemBack()` (renamed `triggerBackPress()`) drives back-press through
      `onBackPressedDispatcher`, not `UiDevice`/system input, for four of the five files. The fifth
      (`BackContractSheetDismissTest`) uses `Instrumentation.sendKeyDownUpSync` instead — a real,
      genuinely-different finding: Material3's `ModalBottomSheet` owns its own separate dispatcher via
      an internal `ComponentDialog`, so the Activity's dispatcher cannot answer that test's actual
      question (which window a back signal reaches first). Still never touches UiAutomator/accessibility.
- [x] The five `BackContract*Test` files no longer poll for up to 12 seconds after a back press
      (26-33's polling was never merged to begin with).
- [x] `26-35`'s CI exclusion is removed — all five files run in the normal CI gate again (`@FlakyOnCi`
      was never merged either).
- [x] `androidx.uiautomator` removed from `app/build.gradle.kts` and `gradle/libs.versions.toml`.
- [x] A real CI run of `instrumented-tests` on this exact change is green — confirmed independently by
      the managing session via the run's own downloaded JUnit XML (10/10 tests, 0 failures), not merely
      the worker's report.
