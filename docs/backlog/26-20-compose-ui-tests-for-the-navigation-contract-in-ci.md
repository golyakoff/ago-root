# 26-20 · Compose UI tests for the navigation contract, running in CI

- **Stage**: 26
- **Status**: ready
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

- [ ] A deliberately broken back-navigation clause **fails CI** — proven by breaking one, watching the
      job go red, and reverting.
- [ ] The "a new assignment never navigates" test fails when the behaviour is inverted — same
      treatment, because a test that passes both ways is the one that gets trusted wrongly.
- [ ] The runner choice and what it cannot catch are recorded in `ago-android/docs/architecture.md`.
- [ ] The job's runtime is measured and stated, and CI's total stays inside `0-04`'s few-minutes gate
      or the slow part is split out.
