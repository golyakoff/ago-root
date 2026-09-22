# 26-25 · `instrumented-tests` fails roughly every other CI run

- **Stage**: 26
- **Status**: ready — dispatched to a background worker
- **Found**: 2026-09-22, by the author, pointing at a real failed run:
  `https://github.com/golyakoff/ago-android/actions/runs/35718774093/job/106716457886`. This same job
  has failed intermittently and been re-run to green at least three times already this session, each
  time assumed to be the known `reactivecircus/android-emulator-runner` `Espresso.pressBack()` →
  `RootViewWithoutFocusException` flake — a real, well-documented Android testing issue, but never
  actually confirmed against this run's own evidence, because **this CI job does not upload its own
  test report as an artifact**, so a failed run's exact stack trace is unrecoverable after the fact
  (confirmed live: `gh run view --log-failed` on the run above shows only "There were failing tests.
  See the report at: file:///…/index.html" — a path on a runner that no longer exists).

## What is actually true today, confirmed against real code

- `Espresso.pressBack()` is called directly, unwrapped, in five instrumented tests:
  `BackContractMoreScreenTest.kt`, `BackContractDialogsTabTest.kt`,
  `BackContractSheetDismissTest.kt`, `BackContractStepFlowTest.kt`, `BackContractBottomBarTest.kt`.
- `Espresso.pressBack()`'s own documented behaviour is exactly the failure mode seen here: it requires
  the app's window to hold input focus at the instant it runs, and throws
  `RootViewWithoutFocusException` if it does not — a known source of flakiness on CI emulators
  (headless, no hardware acceleration, a Compose recomposition or navigation transition that
  momentarily drops focus), independent of anything wrong with the app under test.
- **One of the five tests is not a mechanical case** —
  `BackContractBottomBarTest.clause3_backOnDialogiExitsTheApp` deliberately calls
  `Espresso.pressBack()` inside a `try`/`catch (NoActivityResumedException)`, using Espresso's own
  exception as the *success* signal (back was not consumed by anything, so the system's default
  "finish the task" behaviour ran) — the real failure this test exists to catch is no exception being
  thrown, meaning some callback swallowed the press instead. Any fix has to keep proving that same
  fact by some means, not just "call something that doesn't throw."

## The fix, and why it's the standard one for this exact flake

Replace `Espresso.pressBack()` with `UiDevice.getInstance(InstrumentationRegistry.getInstrumentation
()).pressBack()` (from `androidx.test.uiautomator:uiautomator`) everywhere it currently races the
window-focus requirement. `UiDevice`'s back press operates at the system/UiAutomator level rather than
through Espresso's own `ViewInteraction` machinery, and does not require the app window to hold input
focus — sidestepping the exact race `Espresso.pressBack()` is vulnerable to. This is the standard,
widely-documented fix for this specific `RootViewWithoutFocusException` class of flake, not an
invented workaround.

## Scope

1. **Add `androidx.test.uiautomator:uiautomator` as an `androidTestImplementation` dependency** — not
   currently a dependency anywhere in this project (`grep -rn uiautomator` currently finds nothing).
   Follow this repository's own `libs.versions.toml` catalog convention for adding it, matching
   whatever version is compatible with the rest of this project's `androidx.test.*` stack.
2. **One new shared test helper**, e.g.
   `app/src/androidTest/kotlin/ago/chat/android/testing/SystemBackPress.kt`, wrapping the `UiDevice`
   call — a single place naming *why* this exists (the window-focus race, this exact CI job's own
   history of flaking on it) rather than five copies of the same reasoning. No shared androidTest
   helper file exists in this project yet; this is the first one.
3. **Replace every plain `Espresso.pressBack()` call** (the ones that expect back to be consumed and
   simply wait for the result) with the new helper, across all five files.
4. **`BackContractBottomBarTest.clause3_backOnDialogiExitsTheApp` needs real thought, not a mechanical
   swap** — `UiDevice.pressBack()` does not throw when nothing consumes the press, so the
   `try { pressBack(); fail(...) } catch (NoActivityResumedException) {}` shape has no direct
   equivalent. Replace it with a way to prove the *same fact* (the Activity actually finished, nothing
   swallowed the press) by a different, real mechanism — e.g. polling `composeTestRule.activity
   .isFinishing`/`isDestroyed` after the back press with a short `waitUntil`, or reading
   `ActivityScenario`'s own lifecycle `State` if this test already has access to one. Whatever you
   choose, it has to genuinely fail if a callback swallows the press and the app stays on screen — the
   same thing this test already correctly catches today — not merely stop throwing and pass by
   accident.
5. **Add a test-report upload step to `instrumented-tests` in `.github/workflows/ci.yml`** (e.g.
   `actions/upload-artifact` for `app/build/reports/androidTests/connected/`, and ideally the raw
   JUnit XML under `app/build/outputs/androidTest-results/connected/` too) so a future failure —
   whether this exact flake recurring or a genuine regression — has real evidence attached to the run
   instead of requiring another guess. This is what today's investigation was missing and had to work
   around by pattern-matching against memory of past reruns.

## Out of scope

- Any other cause of CI flakiness (build-tools versions, emulator image, timeouts) — this item is
  scoped to the one specific, well-evidenced pattern (`Espresso.pressBack()`'s own window-focus
  requirement) named above.
- Retrying the job automatically (a workflow-level retry step) — treated as a last resort in this
  project's own established practice this session (`gh run rerun --failed`, done by hand, every time),
  and inferior to actually removing the race.

## Verify for real

- `./gradlew ktlintCheck lint test assembleDebug` green.
- If a local emulator is available in your environment, run the five affected instrumented test files
  repeatedly (a genuine loop, not once) and report the real pass count — the fix's whole claim is
  "removes a race," which a single green run cannot distinguish from "got lucky this time."
- If no local emulator is available, say so plainly rather than claiming a confidence level you could
  not actually establish — the managing session will confirm via repeated real CI runs once this
  lands, and that is the honest place for the final verification to live if your own environment can't
  give it.

## Done when

- [ ] `uiautomator` is a real dependency, used by a single new shared helper, not five separate direct
      calls.
- [ ] All five `BackContract*Test.kt` files use the new helper wherever they currently call
      `Espresso.pressBack()` directly.
- [ ] `clause3_backOnDialogiExitsTheApp` still genuinely proves "nothing consumed the back press and
      the app exited" - by a real mechanism, not merely by no longer throwing.
- [ ] `instrumented-tests` uploads its own test report as a workflow artifact on every run (pass or
      fail), so a future failure carries real evidence.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
