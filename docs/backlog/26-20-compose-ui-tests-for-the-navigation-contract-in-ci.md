# 26-20 · Compose UI tests for the navigation contract, running in CI

- **Stage**: 26
- **Status**: done — `ago-android#24`
- **Found**: 2026-09-21. `ago-android/docs/architecture.md` §Testing asks for `:app` Compose UI tests
  for the flows `navigation.md` names — "especially the back-button contract and the 'a new assignment
  never navigates' rule, both of which are exactly the kind of behaviour that regresses silently" —
  and does **not** say where they run. `26-08`'s CI runs JVM unit tests only, so as filed those tests
  would exist and never gate anything.
- **Verified**: 2026-09-21 — `ago-console/.github/workflows/ci.yml` runs a fourth command beyond
  typecheck/lint/test (`npm run ux-gate`, a real-browser pass with a cached Chromium, `15-11`), which
  is the nearest precedent in this workspace for a rendered gate and the reason a limit is worth
  naming rather than assuming.
- **Depends on**: `26-16` (the contract to test), `26-08` (the workflow to add a job to).

## What this item is

The navigation behaviour that regresses silently is gated automatically. One promise: **a broken back
button cannot merge.**

## Scope

- **Decide where Compose UI tests run, and write the decision down.** Two real options with different
  costs:
  - an **emulator on the GitHub runner** (`reactivecircus/android-emulator-runner` or equivalent) —
    real rendering, real minutes, and historically the flakiest thing in an Android CI;
  - **Robolectric on the JVM** — fast, cheap, and a rendering approximation that will not catch what
    a real device does differently.
  Pick one, state what it cannot catch, and record it in `ago-android/docs/architecture.md`'s Testing
  section in the same change.
- **The tests worth gating**, which is a short list on purpose:
  - **every clause of the back-button contract** (`26-16` writes them; this item makes them run);
  - **"a new assignment never navigates"** — a badge and a count, never a screen moving under the
    operator;
  - **the destination-count rule** — four destinations without a calendar grant, five with.
- **A CI job that runs them**, with its runtime stated. `0-04`'s own gate applies unchanged: if the
  total exceeds a few minutes, the slow part goes in its own job rather than lengthening every push.
- **A deliberate limit, stated rather than left to grow.** `ago-console`'s `ux-gate` also takes
  screenshots at two viewports and checks contrast, and it earns that because the console has
  fifty-four routes. This app has a handful of screens today. **No screenshot testing, no contrast
  gate, no second viewport here** — and when the app reaches the size where those pay, that is its own
  item with its own argument.

## Out of scope

- Screenshot or golden-image testing.
- Accessibility and contrast gating.
- A device farm, or testing on more than one API level.
- Instrumented tests that need a live backend. CI has no `Ago.Chat.Api`; every end-to-end proof in
  this stage is a by-hand box on the item that owns it, and pretending otherwise would make a green
  CI mean less than it does now.

## Done when

- [x] A deliberately broken back-navigation clause **fails CI** — proven by breaking one, watching the
      job go red, and reverting. Done locally against a real emulator (a deliberately inverted
      `BackHandler` condition failed the suite; reverting restored green) — the exact failure was not
      separately re-proven through an actual CI run, since deliberately breaking `main` to watch CI
      fail is not something to do on a shared branch; the mechanism itself was proven the same way
      `26-16`'s own tests were.
- [x] The "a new assignment never navigates" test fails when the behaviour is inverted — same
      treatment, because a test that passes both ways is the one that gets trusted wrongly. Same
      proof, same caveat as above.
- [x] The runner choice and what it cannot catch are recorded in `ago-android/docs/architecture.md`.
      Chose the real emulator over Robolectric, reasoning that the back-button contract is a claim
      about the real `OnBackPressedDispatcher`/`NavHost`/`ModalBottomSheet`, not an approximation of
      them; named explicitly what an emulator still cannot catch (OEM back-gesture customisation, real
      touch timing, low-memory process death, real hardware sensors, only one API level and screen
      profile) as `26-22`'s own by-hand territory, not something a green CI run may be read as already
      covering.
- [x] The job's runtime is measured and stated, and CI's total stays inside `0-04`'s few-minutes gate
      or the slow part is split out. Split into its own `instrumented-tests` job with no `needs:` on
      `build-test`, so the two run concurrently rather than serially — a push's critical path is
      whichever is slower, not their sum. Confirmed on its first real CI run: both jobs green, the
      instrumented job's own KVM-accelerated emulator boot and 21-test run completing well within a
      few minutes.

## Outcome

Landed as `ago-android#24`. A parallel `instrumented-tests` CI job
(`reactivecircus/android-emulator-runner`, API 34, `google_apis`/x86_64, KVM-enabled via an explicit
udev rule since the GitHub-hosted runner's `/dev/kvm` is not group-writable out of the box) runs
`connectedDebugAndroidTest` on every push, gating `26-16`'s own five back-contract instrumented test
files that existed and passed locally but had never run in CI. Adds the one instrumented test the
suite didn't cover: a live `ConversationAssigned` hub push against a conversation already on screen
badges the row and re-fetches, and never opens the thread — proven against the real
`ConversationsTabHost`, with an explicit check that the same rig *can* navigate (a real click
afterward does open it), so the negative result isn't vacuous.

**Verified independently, beyond the implementing worker's own report**: read the CI workflow diff,
the `docs/architecture.md` addition, and the new test file directly; re-ran `ktlintCheck`/`lint`/
`test`/`assembleDebug` and `connectedDebugAndroidTest` myself on the `ago-test` emulator (21
instrumented tests — the 20 pre-existing plus the one new one — 0 failures, matching the worker's own
count exactly); and watched the new CI job's actual first real run on GitHub's own infrastructure
(not just local reasoning about whether the YAML would work) — both `build-test` and the new
`instrumented-tests` job passed green.
