# 26-07 · The Gradle project and its three modules

- **Stage**: 26
- **Status**: done — `ago-android#5`
- **Found**: 2026-09-21, the first item of Stage 26's implementation wave. `26-00`'s plan, screen
  inventory, navigation graph and `adr/0178` are approved and merged into `ago-android/docs/`, which
  is the gate that sentence in `ago-android/docs/README.md` names: "Nothing here authorises a
  `settings.gradle.kts`." It does now.
- **Verified**: 2026-09-21 — `C:/git/ago/ago-android` contains `docs/` and `.git/` and **nothing
  else**: no `settings.gradle.kts`, no Gradle wrapper, no `.github/`, no `LICENSE`, no root
  `README.md`. The module layout and the no-Android-plugin rule below are read from
  `ago-android/docs/architecture.md` §"Module layout" and `adr/0178` §1.
- **Depends on**: nothing.

## What this item is

The repository becomes a buildable Android project with the three modules `architecture.md` already
names, and one placeholder screen — enough that `./gradlew assembleDebug` yields an APK that installs
and launches. **No feature, no network call, no screen from the inventory.** Every later item in this
stage drops into a slot that already exists, which is the shape `0-01` gave the backend repositories.

## Scope

- **Gradle wrapper** (committed, with its properties and checksum), `settings.gradle.kts`, and
  `gradle/libs.versions.toml` — the version catalog is this repository's `Directory.Packages.props`:
  one place a version is declared and none declared at a call site.
- **`:app`** — the Android application module. Jetpack Compose + Material 3, one `MainActivity`, a
  single placeholder composable. It is the only module allowed to know about Android *framework* UI
  and, later, the only place DI is wired (`architecture.md`: the same "hosts reference everything and
  are the only place DI wiring lives" rule `CLAUDE.md` states for the backend).
- **`:core:network`** — an Android library module, empty but for its build file. Ktor/SignalR/token
  storage arrive with their first consumer (`26-12`, `26-13`), not now: "an abstraction with one
  caller is a guess about the second" and an empty interface now is the wrong shape later (`0-01`'s
  own Out of scope, for the identical reason).
- **`:core:domain`** — **a plain Kotlin JVM module applying `kotlin("jvm")` and no Android Gradle
  plugin at all.** This is the load-bearing property of `adr/0178` and the reason the KMP door stays
  open at no ongoing cost: a `Context` import does not compile, so the boundary is impossible rather
  than merely forbidden — the same "make it impossible" shape `adr/0012` gives the platform's package
  boundary.
- **Dependency direction** — `:app` → `:core:network` → `:core:domain`; `:core:domain` depends on
  neither of the other two.
- **Compiler strictness in one place**: `allWarningsAsErrors`, explicit API mode where it is free, and
  a JDK toolchain pinned once rather than inherited from whatever the machine has. This is the
  `Directory.Build.props` warnings-as-errors posture, ported.
- **`.gitignore`** covering `build/`, `.gradle/` and `local.properties`. It used to name
  `google-services.json` too; `adr/0180` moved push from FCM to RuStore Push, and **the RuStore SDK
  has no credentials file at all** — it takes a project-ID string — so there is nothing of that shape
  left for `26-06` to leak here.
- **`LICENSE` (MIT)** and a root **`README.md`** pointing at `docs/`. Both are missing today, and
  `0-01`'s own Done-when — "every repository has a `LICENSE` file" — was written because every one of
  them is public from its first commit.

## Out of scope

- **A dependency-injection framework is not wired here**, even though the choice is now decided:
  **Hilt** (the author's own call, 2026-09-21). A placeholder screen has nothing to inject, so adding
  the Gradle plugin/KSP setup and the first `@HiltAndroidApp`/`@AndroidEntryPoint` annotations belongs
  to `26-12`, the first item with something to actually wire — choosing the library here and wiring it
  there keeps this project's own "say what a dependency replaces and why hand-rolling is worse" rule
  answerable at the point it is actually asked.
- Any screen from `scope-inventory.md`, any HTTP call, any SignalR connection, any Room entity.
- CI (`26-08`) and APK publishing (`26-09`).
- The tablet breakpoint — `plan.md`: phone first, tablet last, and no phase is gated on it.

## Done when

- [~] `./gradlew assembleDebug` produces an APK that installs on a real phone and launches to the
      placeholder screen. **The build half is proven** — a real 9.4MB debug APK, `aapt dump badging`
      confirms a well-formed manifest (`minSdk 26`, `targetSdk 34`, a launchable `MainActivity`). The
      install-and-launch half is **not verified** — no Android device or emulator exists in this
      environment (no AVD, no connected device). Stated plainly rather than assumed; the next item
      that touches a real device should close this gap rather than re-open it as new.
- [x] `./gradlew test` runs and passes, with at least one real unit test in `:core:domain` (a JVM
      test, no Android test runner, no Robolectric — `architecture.md`'s own testing rule).
- [x] **A deliberate `import android.content.Context` in a `:core:domain` source file fails the
      build** — proven by adding it, observing the failure, and reverting. Not asserted.
- [x] A deliberate dependency added from `:core:domain` onto `:core:network` fails — same treatment.
- [x] `LICENSE` and a root `README.md` exist.
- [x] No module is named `common`, `shared`, `utils`, or a bare `core` (`0-01`'s own rule; `:core:domain`
      and `:core:network` are qualified names, `:core` on its own is not — and there is no `:core`
      module, only the container path).

## Outcome

Landed as `ago-android#5`. Three modules exactly as scoped: `:app` (Compose + Material 3, one
placeholder screen), `:core:network` (empty Android library), `:core:domain` (plain `kotlin("jvm")`,
no Android Gradle plugin at all). Gradle wrapper pinned to 8.9; AGP 8.7.3, Kotlin 2.0.21, Compose BOM
2024.10.01 — matched to the SDK actually installed on the build machine (`build-tools;34.0.0`, AGP
8.7's own minimum/default) rather than today's newest AGP, whose default build-tools (36.0.0) isn't
provisioned here. `minSdk 26` — notification channels are the shape the app's whole eventual
Notification-settings screen is built around.

**Both deliberate-failure proofs ran live**: `import android.content.Context` in `:core:domain`
produced `Unresolved reference 'android'`; a `:core:domain` → `:core:network` dependency failed
Gradle's own variant resolution (`androidJvm` vs `jvm` platform mismatch — a structural
incompatibility, stronger evidence than a simple dependency cycle). Both reverted after observing the
failure.

**Verified independently, beyond the worker's own report**: re-ran `assembleDebug`/`test` myself
after landing; `:core:domain`'s `ShortIdTest` — 2/2 passing, confirmed from the real JUnit XML report,
not console output. The one real gap: no Android device or emulator exists in this environment, so
the APK's install-and-launch claim is proven only up to a well-formed manifest, not an actual launch —
recorded above as `[~]` rather than silently ticked or silently dropped.
