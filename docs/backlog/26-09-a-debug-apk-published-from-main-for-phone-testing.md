# 26-09 · A debug APK published from `main` for phone testing

- **Stage**: 26
- **Status**: done — `ago-android#14`
- **Found**: 2026-09-21, the author's own instruction, verbatim: "выпуск apk-артефактов в github для
  тестирования на телефоне". The whole point of Stage 26 is an app in a pocket; a build nobody can
  install is not evidence of one.
- **Verified**: 2026-09-21 — `ago-console`'s `publish-images` job read in full for the precedent this
  follows (`needs: build-test`, `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`,
  a check that the artifact can name its own commit, and a `$GITHUB_STEP_SUMMARY` block saying what
  was published). Also checked: **no workflow in any repository in this workspace publishes a GitHub
  Release today** — every publish is either a GHCR image (`adr/0047`, `adr/0051`) or an
  `actions/upload-artifact` upload (`ago-platform`'s `.nupkg`, `ago-console`'s UX-gate screenshots).
  This item therefore diverges deliberately, and §"Why a Release" says why.
- **Depends on**: `26-08` (the job this one hangs off).

## What this item is

A push to `main` leaves an APK somewhere the author can reach from a phone's browser and install. One
promise: **the latest `main` is installable on a real phone without a build machine.**

## Why a Release rather than only a workflow artifact

Both are built here; only one of them is reachable from a phone.

- An **Actions artifact** is a login-gated `.zip`. A phone browser downloads an archive it cannot
  install, from a page that first demands a GitHub session. It stays, as the no-credential fallback
  for a reviewer — the same role `0-04` gave the `.nupkg` upload it kept beside the real feed.
- A **Release asset** on a public repository has a direct URL, no session, no archive: the browser
  downloads `.apk` and Android offers to install it. That is the difference that decides this, and it
  is the only reason to diverge from the artifact-only pattern every other repository here uses.

## Scope

- A second job in `ci.yml` — `publish-apk`, `needs: build-test`, and `if: github.event_name ==
  'push' && github.ref == 'refs/heads/main'`. A pull request never publishes, so a fork or a draft
  branch cannot put an installable build where a tester might reach for it. That gate is copied from
  `publish-images`, not re-derived.
- **A pre-release, named by the commit**, carrying the APK as its single asset, plus the debug APK
  uploaded as a workflow artifact in the same job.
- **`versionName` carries the short commit sha; `versionCode` derives from the run number.**
  `adr/0051`'s rule ported to this artifact: the build is a function of the commit alone, so the
  commit is the only truthful name for it.
- **A step that reads the commit back out of the built APK** (`aapt2 dump badging`, or the merged
  manifest) and fails if it does not match `github.sha`. This is `ago-console`'s "Check the image can
  name its own commit" step, and it exists because a tag that names a commit the artifact does not
  carry is the 2026-08-25 failure with extra steps.
- **A `$GITHUB_STEP_SUMMARY` block** naming the release and its URL.
- **What "for testing on a phone" actually requires, written in the release body rather than learned
  by failure**: a debug-signed APK, installed by granting "install unknown apps" to the browser or
  file manager that opened it. No Play Store, no account, no upload key.
- **The signing key is per-run, and that has a consequence a tester will otherwise meet as an
  error.** A fresh runner generates its own debug keystore, so consecutive builds are signed by
  different keys and Android refuses to install a newer APK over an older one. This item takes that
  cost deliberately — it introduces no secret — and **states the uninstall-first instruction in the
  release body**. The upgrade path is named below.

## Out of scope

- **A stable signing key.** The fix for uninstall-first is one keystore held as a repository secret
  (`secrets.md` §C's own shape — a base64 blob plus its password, never a committed file: everything
  in these repositories is public) and decoded into the job. It is a real improvement and it is not
  needed to test; it becomes worth its own item the moment reinstalling stops being acceptable.
- **Play Store distribution.** It needs an upload key, which is **Breaking** in `secrets.md`'s own
  rotation vocabulary: an app signed with a new key cannot update one signed with the old, on any
  device that already holds it. That is a distribution decision with a store-listing and policy tail
  (`plan.md`'s own Google Play payments section), not a testing one.
- **A `release` build type, R8/minification, or an unsigned release APK.** An unsigned APK will not
  install at all, which is the trap worth naming rather than discovering.
- Rendering the build's name on screen — that is Settings → О приложении (`26-17`). This item only
  makes the value exist and be true.

## Done when

- [~] A push to `main` produces a release whose APK **installs and launches on a real phone**. A real
      push to `main` (`4f6fc79`) produced `debug-4f6fc79` for real; its APK, downloaded from the
      public release URL (not rebuilt locally), installs cleanly and launches on this machine's Android
      emulator (Pixel 6, API 34) with `versionCode='16'`/`versionName='4f6fc79'` read back matching the
      real commit exactly. **The ticket's own words are explicit that an emulator does not tick this
      box** - stated honestly rather than claimed. Not yet tried on a literal physical phone.
- [x] A pull request produces no release and no installable asset - proven live: `ago-android#14`
      showed `publish-apk` as `skipping` for the PR event, and the same workflow's own real push-to-
      `main` run (once merged) shows `publish-apk` completing successfully - the `if:` gate fires
      correctly in both directions, not merely read and trusted.
- [~] The installed app's version string names the commit it was built from - **proven**, above. The
      CI step failing on a deliberate mismatch was proven **locally** (the implementing worker's own
      fails-before test: correct sha passes, a deliberately wrong expected sha fails the same grep
      check) but **not fired for real in a live CI run** - doing so honestly would need pushing a
      genuinely broken commit to `main` and reverting it, which this project's own rule 9 reserves
      for a PR-mediated change, not a direct push even a temporary one. The check's own logic (a
      literal string match) is simple enough that the local proof is treated as sufficient; revisit if
      that judgment turns out wrong.
- [x] The release body states the install path and the uninstall-before-update consequence - read
      directly off the real, live release page.
- [x] The workflow artifact upload is present too, and downloads - confirmed live on the real run:
      `debug-apk-4f6fc79` (9,038,621 bytes) alongside `test-reports`.

## Outcome

Landed as `ago-android#14`. `publish-apk` job, `needs: build-test`, gated `push` to `main` only
(copied verbatim from `ago-console`'s own `publish-images` gate). `app/build.gradle.kts` reads
`agoVersionName`/`agoVersionCode` as Gradle properties (`0.1.0-dev`/`1` locally); CI passes the short
commit sha and `github.run_number`. A step reads the commit back out of the built APK via `aapt2 dump
badging` and fails on mismatch. The APK publishes as both a workflow artifact and a GitHub pre-release
asset, with a release body stating the install path and the real, deliberate uninstall-first
consequence of a per-run debug signing key.

**Verified live, against the real thing, not only reasoned about**: merging the PR onto `main`
triggered a real `push` event - `publish-apk` ran and succeeded, producing `debug-4f6fc79`
(`versionCode=16`, `versionName=4f6fc79`, matching the real commit). Downloaded the actual release
asset (not a local rebuild) and installed/launched it on this machine's Android emulator, confirming
its own baked-in version matches exactly. Confirmed the release asset is reachable with a plain,
unauthenticated `curl` - a `302` straight from `github.com` to a presigned, no-login asset URL, never
a login redirect. Confirmed the earlier PR (`#14` itself, before merging) showed `publish-apk` as
`skipping` - the gate fires correctly in both directions. Confirmed the workflow artifact
(`debug-apk-4f6fc79`) is present on the same real run.

**Two things stay honestly short of the ticket's own literal wording**: the install/launch proof used
an emulator, and the ticket's own words say that does not count; and the commit-mismatch check's
failure path was proven locally (a fails-before test) rather than fired for real in a live CI run,
since doing so honestly would mean pushing a genuinely broken commit straight to `main` outside a PR -
this project's own rule 9 territory, not taken lightly for a check this simple (a literal string
match) to re-prove live.
