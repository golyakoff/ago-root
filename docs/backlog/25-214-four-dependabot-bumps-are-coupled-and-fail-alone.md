# 25-214 · Four Dependabot bumps in `ago-android` are coupled, and each fails CI alone

- **Stage**: 25
- **Status**: needs a decision — see Scope below
- **Found**: 2026-09-22, checking every open Dependabot PR against `ago-android`'s own real
  `build-test` gate (the required check the author configured directly, per this stage's own record).
  One of seven merged clean (`androidx.test.ext:junit` 1.2.1 → 1.3.0); two more (`gradle/actions`,
  `actions/setup-java`) pass but had gone stale against `main` and were sent a `@dependabot rebase`.
  The remaining four all fail, and not for four separate reasons — for one.

## What is actually true today, confirmed against real CI logs

Two independent coupled pairs, neither of which Dependabot's own per-dependency PRs can see across:

**Kotlin ↔ KSP.** `gradle/libs.versions.toml` pins `kotlin = "2.0.21"` and, separately,
`ksp = "2.0.21-1.0.28"` — KSP's own version string is `<kotlin-version>-<ksp-release>`, a hard
coupling this project's own comments do not currently state. Dependabot's `kotlin` bump
(`dependabot/gradle/kotlin-2.4.20`, PR `#17`) touches only the `kotlin` key, leaving `ksp` pinned to a
release that does not exist for Kotlin 2.4.20. Real failure, read from the CI log directly:

```
Plugin [id: 'com.google.devtools.ksp', version: '2.0.21-1.0.28', apply: false] was not found
```

**AGP ↔ Gradle wrapper ↔ `compileSdk`.** Three separate Dependabot PRs each hit one edge of the same
triangle:
- `dependabot/gradle/agp-9.4.1` (PR `#12`): AGP 9.4.1 requires **Gradle 9.6.0**; the wrapper
  (`gradle/wrapper/gradle-wrapper.properties`) is still 8.9.
  `Minimum supported Gradle version is 9.6.0. Current version is 8.9.`
- `dependabot/gradle/androidx.core-core-ktx-1.19.0` (PR `#8`): `core-ktx` 1.19.0 requires **AGP
  ≥ 9.1.0** and **`compileSdk` ≥ 37**; this build is still on AGP 8.7.3 and `compileSdk = 34`
  (`app/build.gradle.kts:28`).
- `dependabot/gradle/androidx.compose-compose-bom-2026.09.00` (PR `#13`): the new BOM's own
  `androidx.compose.ui:ui-android:1.12.1` hits the identical `compileSdk ≥ 37`/AGP `≥ 9.1.0`
  requirement as the `core-ktx` bump — same wall, different dependency.

None of the four is a defect in the dependency being bumped, and none is wrong to want — they are four
correct, independent observations that this project is due for a coordinated toolchain bump, arriving
as four PRs because that is how Dependabot files things, not because the work splits four ways.

## Scope

**This item does not decide the bump itself — it names the real decision the author's own review
should make, per this project's own rule for a found item that would decide something.** Two honest
shapes, with real different costs:

- **(a) One coordinated bump**: Gradle wrapper → 9.6.0+, AGP → 9.4.1, `compileSdk` (and plausibly
  `targetSdk`) → 37, then `core-ktx` → 1.19.0 and the Compose BOM → 2026.09.00 land as one slice, with
  the full suite (including the instrumented back-contract tests `26-16` just added, and the Room
  instrumented tests from `26-14`) re-run on a real device, not merely `assembleDebug`. AGP major-version
  bumps have a real history of silently changing default lint/R8/manifest-merge behaviour — this is not
  a rubber-stamp merge even once the version numbers line up.
- **(b) The Kotlin/KSP pair only**, landed now (smaller, contained — bump `ksp` to whatever release
  track pairs with Kotlin 2.4.20, confirm the KSP-generated Hilt/Room code still compiles), with the
  AGP/Gradle/compileSdk triangle explicitly deferred to its own later item, on the reasoning that a
  Kotlin compiler bump and an AGP major bump are two different risk profiles and gain nothing from
  being forced into the same slice.

Whichever shape is chosen, closing this item includes closing (as superseded, not as merged)
Dependabot's own PRs `#8`, `#12`, `#13`, `#17` and letting Dependabot re-file against the new pinned
versions if anything remains outdated afterward.

## Out of scope

- The three PRs that already merged or are en route to merging clean (`#7`, `#9`, `#11`) — unrelated,
  already handled.
- Any other Dependabot PR not yet opened.

## Done when

- [ ] The author has picked (a) or (b) above, or a different shape, and this item's own scope reflects
      the choice actually made — not both left standing as options.
- [ ] The chosen bump lands, with the full test suite (unit **and** instrumented, on a real device)
      green, and `docs/backlog/`/`gradle/libs.versions.toml`'s own comments state the Kotlin↔KSP and
      AGP↔Gradle↔compileSdk couplings explicitly, so the next Dependabot PR that hits one of them is
      recognised on sight rather than re-diagnosed from a CI log.
- [ ] Dependabot PRs `#8`, `#12`, `#13`, `#17` are each closed with the reason stated (superseded by
      this item, or landed as part of it).
