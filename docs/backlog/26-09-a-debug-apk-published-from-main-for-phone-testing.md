# 26-09 · A debug APK published from `main` for phone testing

- **Stage**: 26
- **Status**: ready
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

- [ ] A push to `main` produces a release whose APK **installs and launches on a real phone** — done
      once, for real, with the device named in the report. An emulator does not tick this box.
- [ ] A pull request produces no release and no installable asset — proven by opening one, not assumed
      from the `if:` expression.
- [ ] The installed app's version string names the commit it was built from, and the CI step that
      verifies the same value from the APK fails when given a mismatched sha (proven by breaking it
      once).
- [ ] The release body states the install path and the uninstall-before-update consequence.
- [ ] The workflow artifact upload is present too, and downloads.
