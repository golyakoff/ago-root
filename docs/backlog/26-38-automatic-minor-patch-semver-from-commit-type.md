# 26-38 · MINOR and PATCH compute automatically from commit type; MAJOR stays the author's own call

- **Stage**: 26
- **Status**: done — shipped (`ago-android` `b099282`). Found still marked "ready" in the queue despite
  the code being live; caught 2026-09-24 while cross-checking the ready queue against real git history.
  The one remaining Done-when box is now settled below, against the real release list.
- **Found**: 2026-09-23, by the author, after noticing every push all day landed in the same `v0.1.0`
  release: "мы с тобой говорили про автоматический семвер, сделай" — followed by a correction once the
  first draft (auto-patch only, MAJOR.MINOR hand-set) was shown: "патч - это багфикс без брейкинг
  ченджес, minor - это фича, major - моё решение."

## What was true before this item

`26-24`/`26-26` made `agoReleaseVersion` a single hand-bumped `MAJOR.MINOR.PATCH` literal, deliberately
never incremented automatically — "which product version is this" was treated entirely as a decision.
That meant every push under an unbumped version updated the *same* release in place (`26-26`'s own
delete-and-recreate step) rather than any push earning its own number, which is the reason today's ~15
merges to `ago-android` all produced exactly one release.

## The design, per the author's own semver reading

- **PATCH**: a bugfix with no breaking changes.
- **MINOR**: a feature.
- **MAJOR**: the author's own decision.

`MAJOR` (`agoMajorVersion`) is the only literal left in `app/build.gradle.kts`, bumped by hand in its
own commit. `MINOR`/`PATCH` are computed in CI from the commits since the highest existing
`v<major>.*.*` tag, using this project's own real `feat`/`fix` commit-subject convention: any `feat`
commit in that range bumps `MINOR` (resetting `PATCH` to zero — a fix riding along with a feature is
still "added functionality", the standard semver reading of a mixed release); otherwise `PATCH` alone
increments. No tag under the current major at all means `MINOR`/`PATCH` start at `0.0`, and the
identical rule still applies to history so far.

## Scope

- `app/build.gradle.kts`: `agoMajorVersion` replaces `agoReleaseVersion` as the one hand-set literal.
  `agoReleaseVersion` becomes `(-PagoReleaseVersion property) ?: "$agoMajorVersion.0.0"`.
- `.github/workflows/ci.yml`'s "Compute version inputs" step: finds `previous_tag` (`--sort=-v:refname`
  against `v<major>.*.*`), classifies the range since it by scanning for `^feat[(:]` in commit
  subjects, and computes `release_version` accordingly. Emits `previous_tag` as a new output.
- `-PagoReleaseVersion=<computed version>` added to the `assembleRelease` invocation, so the built
  APK's own filename/`versionName` match the version CI is about to tag — verified locally rather than
  assumed.
- "Build changelog" reuses `steps.version.outputs.previous_tag` instead of re-deriving "the previous
  release" its own way.
- A job-level `concurrency` group on `publish-apk`, since two close-together pushes would otherwise
  both read the same latest tag and race to create the identical version.

## Out of scope

- Any change to the tag/title/changelog *format* itself (`26-26`'s own territory) — untouched.
- Auto-computing `MAJOR` in any way — explicitly the author's own call, never derived.

## Done when

- [x] `agoMajorVersion` is the only hand-set version literal; `MINOR`/`PATCH` compute from commit type.
- [x] A `feat` commit anywhere in the range since the last tag bumps `MINOR` and resets `PATCH`;
      otherwise `PATCH` alone increments.
- [x] The computed version reaches the actual built APK (filename + `versionName`), verified with a
      real local `-PagoReleaseVersion=0.1.1` build producing `AGO_Chat_v0.1.1.apk`.
- [x] `./gradlew ktlintCheck lint test assembleDebug` green.
- [x] A real CI run of `publish-apk` produces a version genuinely computed by this logic — confirmed
      2026-09-24 against the real release list (`gh release list`): patch and minor bumps both observed
      live across today's ~15 merges (e.g. `v0.10.0` → `v0.10.1` on a `fix` commit → `v0.11.0` on the
      next `feat`), not merely reasoned about locally.
