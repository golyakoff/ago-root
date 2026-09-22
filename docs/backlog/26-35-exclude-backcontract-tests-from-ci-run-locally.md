# 26-35 · Exclude the five `BackContract*Test` files from CI; run them locally only

- **Stage**: 26
- **Status**: superseded by `26-36` — never merged (the CI change alone was reverted by hand after
  discovering the `notClass` comma-list bug; the follow-up `@FlakyOnCi`-annotation attempt was never
  pushed). The author questioned the whole approach before this landed ("мы что, изобрели какой-то
  тест..."), and a real search confirmed excluding these tests from CI was treating the symptom -
  `26-36` removes the actual race instead (drives `OnBackPressedDispatcher` in-process rather than
  through the system input pipeline), so these tests belong back in the normal CI gate rather than
  excluded from it.
- **Found**: 2026-09-22, by the author, as the explicit fallback decided in advance: "давай дождёмся
  26-33, если не поможет - выноси эти падающие тесты отдельно. Локально их будешь запускать сам,
  удалённо - не будем."

## What is actually true today, confirmed against two real, back-to-back CI runs of `26-33`'s own fix

`26-33` (`ago-android` PR #37) converted every hard assertion after `pressSystemBack()` to a
`composeTestRule.waitUntil(timeoutMillis = 12_000)` poll, and was verified against two consecutive
real CI runs of the identical commit (only its base moved, via a rebase, between them):

- **Run 1** (`35744704312`'s predecessor, base = `303289f`): `instrumented-tests` **passed**, 5m41s,
  all tests green.
- **Run 2** (`35744704312`, base = `f3bd38c`, after rebasing onto `26-34`'s merge - no code change of
  its own): `instrumented-tests` **failed**, 7m31s. Downloaded the real JUnit XML
  (`instrumented-test-reports-35744704312-1`): **7 of the back-press tests failed**, every one a
  `ComposeTimeoutException: Condition still not satisfied after 12000 ms` - the poll exhausted its
  *entire* budget and never observed the expected state, not a near-miss. Two other tests that also
  call `pressSystemBack()` (`BackContractDialogsTabTest`'s own two cases) passed in the same run.

This is a **different symptom than the one `26-27`/`26-33` diagnosed and fixed** (an assertion firing
before a slow-but-real state change lands) - a full timeout with no partial progress is consistent with
the system back key event occasionally not reaching the app/its accessibility-event stream at all on
this specific CI runner's emulator, which no length of polling can fix because there is nothing
eventually true to wait for in that run.

Two consecutive real CI runs disagreeing (pass, then fail) on the identical fix is exactly the outcome
the item's own "verify for real" bar was written to catch, and exactly the trigger condition the author
set in advance for this fallback.

## Scope

- `.github/workflows/ci.yml`'s `instrumented-tests` job: change `./gradlew connectedDebugAndroidTest
  --no-daemon` to exclude the five files via AndroidJUnitRunner's own
  `-Pandroid.testInstrumentationRunnerArguments.notClass=` argument (comma-separated fully-qualified
  class names) - confirm this is still the correct, current AGP/AndroidX Test mechanism before using it,
  rather than assuming from memory.
- The five excluded classes:
  - `ago.chat.android.shell.BackContractBottomBarTest`
  - `ago.chat.android.shell.BackContractDialogsTabTest`
  - `ago.chat.android.shell.BackContractMoreScreenTest`
  - `ago.chat.android.ui.components.BackContractSheetDismissTest`
  - `ago.chat.android.ui.components.BackContractStepFlowTest`
- A doc comment on the exclusion, in `ci.yml` itself, naming this item, the two-run evidence above, and
  that these files still exist and still run - just not on every push - and are the managing session's
  own responsibility to run locally against a real emulator before trusting a change that touches them.
- No change to the test files themselves - `26-33`'s own polling-wait fix stays, since it is still a
  real, correct improvement over a hard assertion; it is just no longer the thing CI's own gate depends
  on for these five files.

## Out of scope

- Any further attempt to fix the underlying flake in this pass - two real, conflicting CI runs is
  enough evidence to stop iterating on the same bug class for now, per the author's own explicit call.
- The other back-contract-adjacent test the item's own `26-27` Verify section named
  (`AssignmentNeverNavigatesTest`) - not one of the five failing files above; leave it in CI unless it
  is separately shown to be part of the same problem.

## Done when

- [ ] `instrumented-tests` no longer runs the five named files; every other instrumented test still
      does.
- [ ] The exclusion and its reasoning are recorded in `ci.yml` itself, not only here.
- [ ] A real CI run of a PR touching unrelated code confirms `instrumented-tests` no longer executes
      the five files (check the job's own log/report, don't assume the flag worked).
