# 26-24 · Semver versioning and a real filename for the release APK

- **Stage**: 26
- **Status**: ready — dispatched to a background worker
- **Found**: 2026-09-22, by the author: the published release APK is literally named `app-release.apk`
  (AGP's own default output name, untouched), and `versionName` is the short commit sha (`26-09`/
  `adr/0051`'s own deliberate choice — see below). The author asked for real semantic versioning and a
  presentable filename, `AGO_Chat_release_v<major>.<minor>.<patch>.apk`.

## What is actually true today, confirmed against real code

- `app/build.gradle.kts`: `versionCode = agoVersionCode ?: 1` (CI passes `github.run_number` — a real,
  monotonically increasing integer, which is what Android *requires* this field to be); `versionName =
  agoVersionName ?: "0.1.0-dev"` (CI passes the short commit sha; the `"0.1.0-dev"` fallback is only
  ever seen on an unversioned local `./gradlew assembleDebug`, never a real build).
- `.github/workflows/ci.yml`'s `publish-apk` job: `assembleRelease` with no `archivesBaseName`/
  `outputFileName` override, so the artifact is AGP's own default, `app-release.apk`. A later step
  (`aapt2 dump badging`) asserts `versionName` equals the build's own short sha, and the release notes/
  tag/title all name the commit — this is `26-09`'s own "the build is a function of the commit alone"
  rule, the same reasoning `adr/0051` gives for a GHCR image tag: *only* the commit should be trusted
  to say what a build is, because nothing else about it is otherwise guaranteed reproducible.
- There is no other place a version number is tracked — no `VERSION` file, no git tag scheme.

**This item genuinely changes that rule, not just cosmetics.** Real semver requires a number someone
decides to bump, which is not a function of the commit — it is the first version number in this
project's four repositories that a human sets by hand rather than derives.

## The proposed shape — implement this unless you find a real problem with it

- **A hand-maintained semver literal**, declared once near `versionCode`/`versionName` in
  `app/build.gradle.kts` (e.g. `private const val AGO_RELEASE_VERSION = "0.1.0"`), bumped by the author
  in its own commit whenever a release is cut — not derived from anything.
- **`versionName` becomes `"$AGO_RELEASE_VERSION+$shortSha"`** — semver's own build-metadata syntax
  (`MAJOR.MINOR.PATCH+build`, valid per the semver spec), not a bare number. This is what keeps
  `26-09`'s own commit-provenance guarantee alive: the CI step that greps `aapt2 dump badging`'s
  `versionName` for the short sha still works, unchanged in spirit, just matching a substring instead
  of the whole field. CI keeps passing `-PagoVersionName` (now built from both pieces), and keeps
  computing the short sha exactly as it does today.
- **`versionCode` is untouched** — still `github.run_number`, still the real Android-required
  monotonic integer, still doubles as "which CI run" provenance the way it already does.
- **The release APK's filename** becomes `AGO_Chat_release_v$AGO_RELEASE_VERSION.apk` (bare semver, no
  build metadata — the filename is what a person reads, the `versionName` inside the manifest is what
  proves provenance). Set via AGP's `applicationVariants.all { outputs... outputFileName = ... }` (the
  standard mechanism — check the exact API surface for AGP 9.x, which this project is on, since the
  `all { }`/`outputFileName` shape changed across AGP major versions).
- **The GitHub release's own tag/title** can keep naming the commit (`release-<shortsha>`) as it does
  today — that identifies *which CI run*, a different question from *which product version*, and nothing
  about this item's own scope asks to change it. Say in your report whether you think it should also
  change, but don't change it without saying why first.
- Update every doc comment this touches that currently states or implies "the build is a function of
  the commit alone" (`app/build.gradle.kts`'s own remarks, `ci.yml`'s own step comments) to state the
  real, now-split rule: **`versionCode` and commit provenance stay a function of the commit; `versionName`
  is now a deliberate, hand-set product version, with the commit carried alongside it as build
  metadata, not standing in for it.** A stale comment asserting the old, now-false rule is worse than no
  comment.

## Out of scope

- Any automated version-bumping (a release script, a `bump` command, CI computing the next semver from
  commit messages). The author bumps the literal by hand — this item does not build tooling for that.
- Play Store / any store listing — this app has none, unchanged by this item.
- The GitHub release tag/title naming scheme (see above — carry it forward unless you find a real
  reason not to, and say so rather than silently changing it).

## Done when

- [ ] `app/build.gradle.kts` declares a single hand-maintained semver literal, starting at `0.1.0`,
      with a comment explaining that it is bumped by hand, in its own commit, when a release is cut.
- [ ] `versionName` reads `<semver>+<shortsha>` on a CI build; a local unversioned `./gradlew
      assembleDebug` still says so honestly rather than claiming a commit it wasn't built from (keep
      the existing "no property set" fallback behaviour, adapted to the new shape).
- [ ] `versionCode` is unchanged.
- [ ] The published release APK's filename is `AGO_Chat_release_v<semver>.apk`, confirmed by actually
      running `assembleRelease` and looking at the real file, not by reading the Gradle config and
      assuming it is correct.
- [ ] `ci.yml`'s "Check the APK can name its own commit" step still proves the same thing it proves
      today — the built APK's `versionName` really does carry the exact commit CI built it from —
      adapted to match on a substring of the new `<semver>+<shortsha>` value rather than the whole
      field.
- [ ] Every doc comment asserting the old "versionName is the commit" rule is corrected to state the
      real, split rule.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green, plus a real local `assembleRelease` run
      (with throwaway signing properties if needed) proving the filename and `versionName`.
