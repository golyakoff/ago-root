# 26-69 · `tappingSignOutCallsOnSignOut` fails 100% of the time on a real device, and never on CI's emulator

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, verifying PR #47 (26-40/26-41/26-42) — a full `connectedDebugAndroidTest` run
  on the real connected phone (`F6VCHEZDAMRCPNJZ`, 23106RN0DA, Android 15) failed one test outside that
  PR's own diff, on `ago-android` `main` at `280ebeb`.

## Found

`ago.chat.android.shell.SettingsScreenTest.tappingSignOutCallsOnSignOut` fails deterministically on
this real device — 3 for 3 runs, including one against a **clean worktree cut straight from
`origin/main`** with none of PR #47's changes present, isolating this from that PR entirely:

```
java.lang.AssertionError: expected:<true> but was:<false>
	at ago.chat.android.shell.SettingsScreenTest.tappingSignOutCallsOnSignOut(SettingsScreenTest.kt:159)
```

The test (`SettingsScreenTest.kt:141-160`):

```kotlin
composeTestRule.setContent {
    SettingsScreen(..., onSignOut = { signedOut = true }, ...)
}
composeTestRule.onNodeWithText("Выйти").performClick()
assertEquals(true, signedOut)
```

`performClick()` runs, the node is found (no "node not found" error — the failure is the assertion,
not a lookup), and `onSignOut` still never fires.

**This is not what CI sees.** The identical file passed on GitHub's own emulator runner in each of
PR #43 (26-38), PR #44/#45 (26-43/26-44), and PR #46 (26-39)'s `instrumented-tests` job — all green,
all including this exact test. The divergence is real-device-versus-emulator, not
flaky-versus-stable: three separate real-device runs (two on `feat/26-40-thread-appbar-composer-ticks`,
one on a clean `main` worktree) all failed the same way, while every emulator run on file has passed.

## What is actually true today, confirmed against real code

- `SettingsScreen.kt:162-169`: the sign-out control is the **last item in a `LazyColumn`**
  (`:125`), a plain `TextButton(onClick = onSignOut) { Text(stringResource(R.string.action_sign_out)) }`.
- The five other `SettingsScreenTest` cases in the same file, exercised in the same run immediately
  before and after this one, all pass — including `backArrowCallsOnBack`, which clicks a different
  control on the same screen. Only the `LazyColumn`'s last, off-the-first-screen item fails.
- Two candidate mechanisms, neither confirmed yet:
  1. **A `LazyColumn` visibility/composition timing gap real devices hit and the emulator does not** —
     `performClick()` on a Compose semantics node does not require the node be on-screen, but it does
     require the node be *composed*; if the sign-out row is laid out just past the last fully-measured
     item on this real device's actual screen height (unlike the emulator's), Compose's own
     `beyondBoundsLayout`/prefetch window could compose it just late enough to click a node that gets
     disposed and re-created before the click's coroutine resumes — this is a real, previously reported
     Compose `LazyColumn` + test-click interaction, not a guess invented for this item.
  2. Something about this specific device's `Android 15` build recomposing the screen once after
     `setContent` (a config-change-shaped extra pass) that a stock emulator image does not.
- Not yet checked: whether adding `composeTestRule.waitForIdle()` before the click (present in most of
  this file's sibling tests via other synchronization, absent here) changes anything, and whether
  scrolling the `LazyColumn` to the item first (`performScrollToNode`) changes anything.

## Scope

One promise: **`tappingSignOutCallsOnSignOut` passes reliably on the real connected device, not only
on CI's emulator.**

1. Reproduce with `--stacktrace`/verbose Compose test logging to see whether the click lands on a node
   that gets torn down, or whether `onSignOut` is called with a stale closure.
2. If it is the `LazyColumn` composition-timing mechanism, the fix is almost certainly
   `composeTestRule.onNodeWithText("Выйти").performScrollTo().performClick()` — scroll it into a stable
   composed state before clicking, the same pattern any `LazyColumn`-bottom-item test needs regardless
   of the exact root cause.
3. Confirm the fix on the real device across several repeated runs, not once — this item exists
   because "it passed once" was already true for every emulator run and told nobody anything about the
   real device.

## Out of scope

- Any other `SettingsScreenTest` case — all five others pass reliably on both surfaces.
- Making CI itself run on a real device. That is a separate, much larger question this item does not
  raise.
- PR #47 (26-40/26-41/26-42), which this bug is unrelated to and does not block — confirmed by
  reproducing it on a clean `main` worktree with none of that PR's changes present.

## Done when

- [ ] `tappingSignOutCallsOnSignOut` passes at least 5 consecutive times on the real connected device.
- [ ] The root cause is stated, not just the fix — which of the two candidate mechanisms above (or a
      third one) actually explains it.
- [ ] No other `SettingsScreenTest` case regresses.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
