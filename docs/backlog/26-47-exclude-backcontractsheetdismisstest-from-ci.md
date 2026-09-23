# 26-47 · Exclude `BackContractSheetDismissTest` from CI; run it locally only

- **Stage**: 26
- **Status**: ready
- **Depends on**: `26-36` (the dispatcher-based rewrite this item narrows, not reverses)
- **Found**: 2026-09-23, live, on `ago-android`'s own `main` branch CI (run `35820742974`, the run for
  the `26-38` merge commit) — `instrumented-tests` failed, which skips `publish-apk` entirely (it
  `needs: [build-test, instrumented-tests]`), so **no release published at all** for that push. This is
  the author's own pre-agreed fallback ("если не поможет - выноси эти падающие тесты отдельно.
  Локально их будешь запускать сам, удалённо - не будем"), now triggered for one specific test rather
  than the five `26-35` first considered.

## What is actually true today, confirmed against two of the last three real post-`26-36` CI runs

`26-36` rewrote four of the five `BackContract*Test` files to drive back-press through
`onBackPressedDispatcher` directly (in-process, no system input event at all) and left exactly one,
`BackContractSheetDismissTest`, on a real key press
(`SystemBackPress.kt`'s `pressBackOnFocusedWindow()`, `Instrumentation.sendKeyDownUpSync`) — a
deliberate, narrower exception: `ModalBottomSheet` renders inside its own platform `Dialog`, which owns
its own separate `OnBackPressedDispatcher`, so the Activity's dispatcher cannot answer "did the sheet
dismiss" at all.

Both real failures are the identical shape, on the identical assertion:

```
java.lang.AssertionError: Failed: assertDoesNotExist.
Reason: Did not expect any node but found '1' node that satisfies:
  (Text + InputText + EditableText contains 'SHEET_CONTENT' (ignoreCase: false))
	at ago.chat.android.ui.components.BackContractSheetDismissTest
	    .clause5_backDismissesTheSheetBeforeItReachesTheScreenUnderIt(BackContractSheetDismissTest.kt:86)
```

`26-36`'s own report already named the same failure mode once during its own development (a second
press's window-focus not yet transferred back from the closing dialog) and added a real fix for it
(`composeTestRule.waitUntil { composeTestRule.activity.hasWindowFocus() }` between the two presses,
"confirmed by 3 consecutive clean runs" locally) before landing. That fix is real and stays — it did not
turn out to be wrong, it turned out to be insufficient on real CI, the identical shape this whole area
has hit twice before (`26-27`, then `26-33`) for the other four tests before `26-36` finally removed the
system input pipeline from them entirely. The one test that still cannot remove that pipeline (a real
cross-window back signal has no other way to be proven) inherits the identical residual risk.

**Run count**: three real CI runs of `instrumented-tests` since `26-36` merged (`ago-android` runs
`35793371664`, `35796832036`, `35820742974`). Two failed, both on this exact test, both this exact
assertion. One passed.

## Scope

- Mark `BackContractSheetDismissTest` `@FlakyOnCi` (`app/src/androidTest/kotlin/ago/chat/android/
  testing/FlakyOnCi.kt` — `26-35` designed this annotation and its `ci.yml` wiring but never merged
  either; recreate both here, single-value this time). Use `-Pandroid.testInstrumentationRunnerArguments.
  notAnnotation=ago.chat.android.testing.FlakyOnCi`, **not** `notClass` — `26-35`'s own finding was
  that a comma-separated `notClass` list only excludes the first entry on this project's Gradle/AGP
  version combination, a real tool limitation, not something a single-value exclusion (this item needs
  only one) would hit, but `notAnnotation` is the already-proven-correct mechanism (`26-36`) and using
  it here keeps one convention for "this test is deliberately CI-exempt" rather than two.
- A doc comment on the CI exclusion (`ci.yml`) and on the test class itself, naming this item, the
  real failure evidence above, and that the test still exists and still runs — just not as a gate on
  every push.
- No change to the test's own logic or to `pressBackOnFocusedWindow()` — the `hasWindowFocus()` wait
  `26-36` already added is a real, correct improvement over not having it; this item does not undo it,
  it stops trusting a single real key-press round trip on a real CI runner to be reliable enough to
  gate a release, which the evidence above says it currently is not.

## Out of scope

- Any further attempt to fix the underlying timing in this pass — two real CI failures out of three
  runs is enough evidence to stop iterating on the same bug class for now, matching the reasoning
  `26-35` already used for the other four tests before `26-36` found the real fix for those.
- The four dispatcher-based tests (`26-36`'s own rewrite) — not implicated by either failure, stay in
  the normal CI gate.

## Done when

- [ ] `BackContractSheetDismissTest` is annotated `@FlakyOnCi` and excluded from `instrumented-tests`
      via `notAnnotation`.
- [ ] The exclusion and its real evidence are recorded in `ci.yml` itself, not only here.
- [ ] A real CI run of a PR touching unrelated code confirms `instrumented-tests` no longer executes
      this one test (check the job's own log/report, don't assume the flag worked — `26-35`'s own
      first attempt got exactly this wrong and only found out by checking).
- [ ] `publish-apk` runs and publishes on the next ordinary push, confirmed by the managing session
      reading the real release — this is the concrete, user-visible thing this item exists to restore.
