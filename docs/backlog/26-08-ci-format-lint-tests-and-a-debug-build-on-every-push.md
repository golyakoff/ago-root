# 26-08 · CI: format, lint, tests and a debug build on every push

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-21, the author's own instruction when opening Stage 26's implementation wave:
  "...включая подготовку CI". Filed before any feature item deliberately, the same order `0-04` took
  for the backend repositories — "green" has to be a fact before anything claims it.
- **Verified**: 2026-09-21 — read `ago-console/.github/workflows/ci.yml` end to end for the pattern
  this follows (trigger shape, one `build-test` job on `ubuntu-latest`, format/lint gates before
  build, `actions/upload-artifact` for reports, a `main`-only publish job gated on `build-test`).
  `ago-android` has no `.github/` directory at all.
- **Depends on**: `26-07` (there must be a Gradle project to build).

## What this item is

Every push and every pull request compiles, passes the format gate, passes Android Lint, runs the
unit tests and assembles a debug APK — and a branch that fails any of those cannot show green. One
promise: **a branch is checked automatically**.

## Scope

- **`.github/workflows/ci.yml`** in `ago-android`, one `build-test` job on `ubuntu-latest`, triggered
  on `push` to `main` and on `pull_request` — the exact trigger shape both `ago-console` and
  `ago-chat` use, so a fork or a draft branch behaves the way everything else here does.
- **`gradle/actions/wrapper-validation` as the first step.** The wrapper jar is a committed binary
  that every subsequent step executes; validating it is the same class of supply-chain care that
  makes `ago-console` pin its Trivy image by digest rather than trust a floating tag.
- **`actions/setup-java`** (Temurin, the LTS the Android Gradle Plugin in use requires) with Gradle's
  own caching. Pin the major version in the workflow, not "latest".
- **The format gate runs before the build and fails fast** — the reason both backend repositories put
  `dotnet format --verify-no-changes` ahead of `dotnet build` is that a formatting-only branch should
  cost seconds, not a full compile. The Kotlin equivalent this item adds is **ktlint** via its Gradle
  plugin (`ktlintCheck`).
- **Static analysis: Android Lint, and deliberately not detekt.** Stated per `CLAUDE.md`'s rule that a
  new dependency must say what it replaces and why hand-rolling is worse. Android Lint ships with the
  Android Gradle Plugin — no new dependency at all — and catches the Android-API misuse that actually
  breaks apps. `26-07` already turns compiler warnings into errors. What detekt would add on top is a
  complexity-and-code-smell opinion nobody has asked for, plus a second suppression vocabulary to
  maintain. **Reopen it the first time a real defect reaches `main` that detekt would have caught**;
  until then it is machinery without a finding.
- **`./gradlew test`** across all three modules, and **`./gradlew assembleDebug`** — a repository that
  compiles its libraries but cannot assemble an app is green about the wrong thing.
- **Test reports uploaded** with `actions/upload-artifact` and `if: always()`, which is what makes a
  red run diagnosable — `0-04` established this with `.trx`, and `ago-console` keeps it for the
  screenshots of a *failing* gate for the same reason.
- **`.github/dependabot.yml`** with the `gradle` and `github-actions` ecosystems. Filed here rather
  than as its own item on purpose: Dependabot without CI is worse than nothing — a stream of bump PRs
  that nothing checks — so the two are one promise and land green together.
  `docs/runbooks/vulnerability-response.md` is the procedure those PRs feed into.
- **The `build-test` job is named so a branch-protection rule can require it.** Flipping that rule is
  a GitHub setting rather than a file, and it is the author's to do — exactly as `0-04` recorded.

## Out of scope

- **Publishing an APK anywhere** — `26-09`. This item assembles one and throws it away.
- **Compose UI / instrumented tests** — `26-20`, because where they run (an emulator on the runner, or
  Robolectric on the JVM) is a real decision with a real runtime cost and it deserves to be made
  rather than smuggled in here.
- **A vulnerability scanner for the app's own dependencies.** Dependabot covers the bump path; there
  is no clean `npm audit` analogue for Gradle in this toolchain, and inventing one before it has ever
  caught anything is the same guess `0-04` refused when it declined to wire coverage reporting "until
  a coverage report actually informs a decision".
- Any deployment, store upload, or signing configuration.

## Done when

- [ ] A pull request with a compile error cannot show green — proven by pushing one and observing the
      failure, then reverting.
- [ ] A pull request with a failing unit test cannot show green — same treatment.
- [ ] A pull request with a ktlint violation cannot show green — same treatment.
- [ ] Wrapper validation runs before any step that executes the wrapper.
- [ ] The workflow's total runtime is measured and stated. If it exceeds a few minutes, the slow part
      moves to its own job — `0-04`'s own gate, applied here rather than restated.
- [ ] Test reports are downloadable from a failed run.
- [ ] `.github/dependabot.yml` is accepted by GitHub (visible in the repository's Insights →
      Dependency graph → Dependabot), and the first bump PR it opens runs this workflow.
