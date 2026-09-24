# 26-37 · Drop "release" from the published APK's filename

- **Stage**: 26
- **Status**: done — shipped (`ago-android` `c8ec1bc`/`a2b4a09`). Found still marked "ready" in the
  queue despite every Done-when box already ticked — a queue-row oversight, not unfinished work; caught
  2026-09-24 while cross-checking the ready queue against real git history before dispatching from it.
- **Found**: 2026-09-23, by the author, after seeing the real published asset name and preferring a
  shorter one.

## What is actually true today, confirmed against the real published release

`v0.1.0`'s real GitHub release (published 2026-09-22, `26-24`/`26-26`'s own work) carries exactly one
asset: `AGO_Chat_release_v0.1.0.apk` — working exactly as `26-24` specified, not broken. The author now
wants `AGO_Chat_v<semver>.apk` instead — a naming preference, not a bug fix.

## Scope

Three real references, all confirmed live in `main`:

- `app/build.gradle.kts:210` — `output.outputFileName.set("AGO_Chat_release_v$agoReleaseVersion.apk")`
- `.github/workflows/ci.yml:248` — the `apk=` path echoed for the upload step
- `.github/workflows/ci.yml:454` — the step-summary text naming the asset

All three become `AGO_Chat_v$agoReleaseVersion.apk` / `AGO_Chat_v$release_version.apk`.

## Done when

- [x] The Gradle `outputFileName` no longer contains "release".
- [x] Both `ci.yml` references (the upload path and the summary text) match.
- [x] `./gradlew assembleRelease` (throwaway signing) produces the real file under the new name.
