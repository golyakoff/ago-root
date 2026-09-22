# 26-27 · `pressSystemBack()` needs a real synchronization wait, not `waitForIdle()` alone

- **Stage**: 26
- **Status**: ready — dispatched to a background worker
- **Found**: 2026-09-22, live, on `ago-android#33`'s own `instrumented-tests` run (a PR that touches
  only `.github/workflows/ci.yml` — no app code at all), immediately after `26-25` merged and its own
  PR had reported this exact job green. Six tests across four files failed, every one of them an
  assertion checking UI state **immediately after** `pressSystemBack()` (`26-25`'s own
  `UiDevice.pressBack()`-based replacement for `Espresso.pressBack()`) — the assertion runs before the
  back press's effect has actually landed.

## What is actually true today, confirmed against the real failed run's own JUnit XML

Downloaded `26-25`'s own new artifact (`instrumented-test-reports-<run>-<attempt>`, exactly the report
this item's own predecessor added so a failure would be diagnosable — it worked) from
`https://github.com/golyakoff/ago-android/actions/runs/35729574271`. Six failures, every one an
`assertExists`/`assertDoesNotExist` immediately following a `pressSystemBack()` call, not a
`RootViewWithoutFocusException` (the flake `26-25` actually fixed — that failure mode is genuinely
gone; this is a different, new one):

- `BackContractBottomBarTest.clause3_backOffAnotherTabLandsOnDialogi` (line 65) and
  `.clause3_backNeverWalksThroughPreviouslyVisitedTabs` (line 127) — both already call
  `composeTestRule.waitForIdle()` right after `pressSystemBack()`, and still fail to find the expected
  text.
- `BackContractBottomBarTest.clause3_backOnDialogiExitsTheApp` — `ComposeTimeoutException` on the
  `waitUntil(timeoutMillis = 5_000) { ... Lifecycle.State.DESTROYED }` poll `26-25` itself added — 5
  full seconds was not enough, or the state genuinely never arrives via this signal reliably.
- `BackContractMoreScreenTest` (two cases), `BackContractSheetDismissTest`, `BackContractStepFlowTest`
  — the identical shape: an assertion right after a `pressSystemBack()` call finds stale UI.

**The real cause, to confirm before fixing (do not assume without checking)**: `Espresso.pressBack()`
is integrated with Espresso's own `IdlingResource`/synchronization machinery — it does not return until
the app's main-thread work queue is genuinely idle, which is what let every one of these tests get away
with no explicit wait of their own before `26-25`. `UiDevice.pressBack()` (`androidx.test.uiautomator`)
operates entirely outside that machinery — it dispatches a system-level key event and returns
immediately, with no synchronization to Compose's or Espresso's own idle state at all.
`composeTestRule.waitForIdle()` alone is not enough because it only inspects **Compose's own** current
idle/recomposition state — if the system back event has not even been *delivered* to the app's dispatcher
yet, there is nothing for Compose to be non-idle *about*, and `waitForIdle()` returns immediately having
waited for nothing real.

## The proposed fix — verify this actually closes the gap, don't assume

`UiDevice` has its own `waitForIdle()` (and a `waitForIdle(long timeoutMillis)` overload) — a real,
long-standing UiAutomator API that waits for the accessibility-event stream itself to go quiet, which is
the layer a system-dispatched back key event's window-transition side effects actually flow through.
Add a call to it *inside* `pressSystemBack()` (`app/src/androidTest/kotlin/ago/chat/android/testing/
SystemBackPress.kt`), after `device.pressBack()`, before the function returns — so every call site gets
the wait for free rather than each test needing its own copy. Confirm this genuinely fixes the observed
failures (see Verify below) rather than trusting the API's name alone; if it does not fully close the
gap, say so and find what does (a longer `Lifecycle.State` timeout for the one redesigned exit-check
test, an additional `composeTestRule.waitForIdle()` call stacked after the `UiDevice`-level one, or
something else you find by actually reproducing this).

## Scope

- `SystemBackPress.kt`: add the real synchronization wait, with a doc comment explaining why
  `composeTestRule.waitForIdle()` alone was not enough (the two-layer synchronization gap above) —
  this is exactly the kind of thing a future reader will otherwise "fix" by reaching for
  `Espresso.pressBack()` again, undoing `26-25`.
- If `waitForIdle()` alone does not fully close the gap for `clause3_backOnDialogiExitsTheApp`'s own
  `Lifecycle.State.DESTROYED` poll, adjust that test's own timeout or synchronization — but only after
  confirming, live, that the base fix in `SystemBackPress.kt` doesn't already resolve it (an Activity
  finishing is a slower, multi-step lifecycle transition than a Compose recomposition settling, so it
  may still need its own margin even once the underlying event-dispatch race is closed).

## Out of scope

- Reverting to `Espresso.pressBack()` — that reintroduces the real, confirmed `RootViewWithoutFocusException`
  flake `26-25` exists to fix. Not an acceptable fallback.
- `26-26`'s own changes (tag/title/changelog/`needs:`) — unaffected, this item only unblocks its
  `instrumented-tests` gate from a real, separate regression this discovery is not to be conflated with.

## Verify for real — this is the whole point of this item

- Run the five `BackContract*Test` files (and `AssignmentNeverNavigatesTest`, if it also drives a back
  press) **repeatedly** against a real device/emulator, not once — the previous fix (`26-25`) also
  reported one clean run and still had this gap; one green run proves nothing about a race. If your
  environment has no real emulator/device, say so plainly (as `26-25`'s own worker did) rather than
  claiming a confidence level you did not establish, and note that the managing session will confirm via
  repeated real CI runs.
- `./gradlew ktlintCheck lint test assembleDebug` green.

## Done when

- [ ] `pressSystemBack()` includes a real synchronization wait proven (not merely reasoned) to close the
      race the failed run above demonstrates.
- [ ] The five `BackContract*Test` files pass repeatedly, not just once — either verified directly
      against a real device in this task, or explicitly handed to the managing session's own repeated
      CI verification with that hand-off stated plainly.
- [ ] `ago-android#33` (or whichever PR is current by the time this lands) goes green on
      `instrumented-tests` without a lucky rerun.
