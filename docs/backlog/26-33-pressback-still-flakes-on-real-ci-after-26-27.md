# 26-33 · `pressSystemBack()` still flakes on real CI — `waitForIdle()` wasn't enough

- **Stage**: 26
- **Status**: ready — dispatched to a background worker
- **Found**: 2026-09-22, immediately after `26-27` merged: its own PR (`ago-android#34`) hit the
  **identical** six-failure pattern on real CI (`run 35734381435`) that `26-27` itself was written to
  fix. Confirmed this is genuinely the fix commit under test (`git show
  fix/26-27-pressback-synchronization-gap:.../SystemBackPress.kt` on the exact `headSha` the run
  reports) — not a stale run, not a different branch.

## The real lesson here, stated plainly before anything else

`26-27`'s own worker verified its fix with **9 repeated clean runs on a real Android
emulator/device in its own environment** and reported high confidence. That verification was
real and honestly reported — and it was still not equivalent to GitHub's actual
`reactivecircus/android-emulator-runner` CI environment, which is more resource-constrained and
evidently has different timing characteristics for exactly the race this whole chain of items is
chasing. **This is now confirmed twice**: `26-25`'s own fix, and now `26-27`'s, each looked solid
against local verification and each still failed on real CI. Do not treat another clean local-device
run as sufficient evidence this time. **The only verification that counts for this item is a real,
green CI run of `ago-android`'s own `instrumented-tests` job, watched by the managing session** — say
this plainly in your own report rather than re-offering local-device confidence as the close-out proof.

## What the real failed run actually shows

Downloaded the real JUnit XML from `instrumented-test-reports-35734381435-1` (the artifact `26-25`
itself added). The exact same six tests fail, with two new, important details `26-27`'s own diagnosis
did not have:

- `BackContractBottomBarTest.clause3_backOffAnotherTabLandsOnDialogi` **already calls both layers**
  `26-27` added — `pressSystemBack()` (which now itself calls `UiDevice.waitForIdle()`) **and then**
  `composeTestRule.waitForIdle()` immediately after, exactly the "stack both waits" fix a naive reading
  of `26-27`'s own gap might suggest trying next — and it still fails. **Stacking a second, Compose-level
  `waitForIdle()` after the `UiDevice`-level one is therefore already proven insufficient — do not
  reach for it as this item's own fix.**
- `BackContractBottomBarTest.clause3_backOnDialogiExitsTheApp` — the **`waitUntil(timeoutMillis =
  5_000) { ... Lifecycle.State.DESTROYED }` poll `26-25` itself added** (a retry/polling wait, not a
  single blocking one) **also timed out**. This is a real, separate data point: even a test that
  already polls for a specific condition, rather than blocking once and asserting, can still fail here
  - meaning either 5 seconds is genuinely not enough headroom on a loaded CI runner, or the back press
  is not reliably reaching the app at all in some fraction of runs (a real possibility with
  `UiDevice.pressBack()`, which can occasionally no-op if the accessibility service connection isn't
  fully settled — a known category of UiAutomator flakiness, not this codebase's own invention).

## Investigate before implementing — this needs real diagnosis, not another guess

1. **Confirm whether the back press is being delivered at all**, some fraction of the time, versus
   being delivered but the UI settling too slowly. If your environment can reach real CI logs/timing
   (or you can add temporary diagnostic logging to a throwaway CI run and read its output), check this
   directly rather than assuming either explanation.
2. **Convert every hard assertion immediately following a `pressSystemBack()` call, across all five
   `BackContract*Test.kt` files, into a polling wait** (`composeTestRule.waitUntil(timeoutMillis =
   ...) { <the same condition, expressed as a boolean> }`, then the existing assertion afterward,
   which will now trivially confirm what `waitUntil` already established) rather than a single
   `waitForIdle()` (of either kind) followed immediately by a hard assert. This is the standard,
   textbook-correct Compose-testing pattern for "an async system action, then the UI settles on its own
   schedule" — waiting for the *specific* expected evidence, not a generic "nothing is currently
   churning" signal that can be satisfied without the real target state ever being reached. Use a real
   timeout with headroom for a loaded CI runner (start higher than 5 seconds, e.g. 10-15, and say why
   you picked the number).
3. **If a retry belongs anywhere, it likely belongs on the back press itself**, not only on the
   assertion — consider (and justify your choice either way) having `pressSystemBack()` retry the
   press a bounded number of times if a caller-supplied condition hasn't become true within a short
   window, rather than pressing exactly once and hoping. This is a real design choice with a real
   tradeoff (a helper that takes a condition parameter is a bigger API than today's parameterless one)
   — make the call and explain it, don't default to the smallest possible diff if it doesn't actually
   solve the problem.
4. Keep `26-27`'s own `UiDevice.waitForIdle()` call — it is not wrong, it just isn't sufficient alone.
   Build on it rather than reverting it.

## Out of scope

- Reverting to `Espresso.pressBack()` — still not acceptable, still reintroduces the original,
  confirmed `RootViewWithoutFocusException` flake.
- `26-26`'s own changes.

## Verify for real

- Whatever you build, verify it as thoroughly as your environment allows (repeated real-device runs,
  as `26-25`/`26-27`'s own workers did) — but **state explicitly in your report that this is necessary,
  not sufficient**, and that the managing session's own real CI run is what actually closes this out.
  Do not write a report that reads as "done" on the strength of local verification alone — this item
  exists specifically because that pattern has now failed to catch the real problem twice.
- `./gradlew ktlintCheck lint test assembleDebug assembleDebugAndroidTest` green.

## Done when

- [ ] Every `pressSystemBack()` call site's own follow-up assertion uses a real polling wait for its
      specific expected condition, not a blocking "idle" signal alone.
- [ ] A real, actual green CI run of `instrumented-tests` on a PR carrying this fix — confirmed by the
      managing session, watching the real run, not inferred from local testing.
