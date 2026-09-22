# 25-215 · One stable signing key, shared by debug and release

- **Stage**: 25
- **Status**: done — `ago-android#26` + follow-up fix `f6a2433`
- **Found**: 2026-09-22, while scoping `26-06` (RuStore Push device registration). RuStore keys a
  push project to the installed build's exact signature fingerprint, and `26-09`'s own per-run debug
  keystore means that fingerprint is different on every CI run — a RuStore Console project registered
  against one run's fingerprint is useless the moment the next run publishes. `26-09` itself named the
  fix and deliberately deferred it: *"the fix for uninstall-first is one keystore held as a repository
  secret... it becomes worth its own item the moment reinstalling stops being acceptable."* That
  moment is now, for a different reason than uninstall-first — reinstalling isn't the problem RuStore
  raises, a **moving fingerprint** is.

## What this item is

The author's own proposal, adopted as this item's shape: **one persistent keystore, signing both the
local `debug` build type and the CI-published `release` build**, rather than a separate debug and
release identity. `release`'s own `isMinifyEnabled = false` (unchanged by `25-214`) means the two
build types are already near-identical in every way that isn't signing, so sharing a key costs nothing
`26-09`'s original per-run-debug-key design was protecting against — no R8/shrinking migration risk,
no Play Store upload-key question (out of scope, `26-09`'s own words, and unchanged here).

**Consequence for `26-06`/RuStore**: one push project in RuStore Console, not two, since debug and
release now share one fingerprint.

## What already exists, done directly by the managing session — not this item's own worker to redo

- A keystore generated locally (`~/.android/ago-android-release.keystore` on the author's machine),
  RSA 2048, 10 000-day validity, alias `ago-android`. Its own password lives beside it,
  `~/.android/ago-android-release.keystore.password.txt` — **not committed, not this repository's
  concern, per `docs/architecture/secrets.md`'s own "held outside every repository" class** (the
  identical shape as the deployment's own SSH private key).
- Two GitHub Actions repository secrets in `ago-android`: `ANDROID_SIGNING_KEYSTORE_BASE64` (the
  keystore file, base64-encoded) and `ANDROID_SIGNING_KEYSTORE_PASSWORD` (one password, used as both
  the store password and the key password — the alias itself, `ago-android`, is not a secret and may
  be a plain value in the build file or workflow).
- `.gitignore` already excludes `local.properties` and `*.keystore` — no change needed there; a
  worker on this item does not need to touch it, only use it.

## Scope

- **`app/build.gradle.kts`**: a `signingConfigs` block reading the keystore path, store password, key
  alias and key password from Gradle properties (the identical `agoProperty`-style pattern
  `app/build.gradle.kts` already uses for `agoVersionName`/`agoApiBaseUrl` etc. — a property when one
  is supplied, a stated local fallback otherwise). Both `debug` and `release` build types reference
  the same `signingConfig`.
- **Local development**: the four values (`agoSigningKeystorePath`, `agoSigningStorePassword`,
  `agoSigningKeyAlias`, `agoSigningKeyPassword`) read from `local.properties` (already gitignored) via
  Gradle's own `Properties().load(...)` idiom for that file, so a developer machine that has the
  keystore at the path above builds real, verifiably-signed debug and release APKs with no CI
  involvement. **A fresh clone with no `local.properties` entry must still build** — fall back to
  AGP's own default debug-signing behaviour for `debug` (exactly what happens today, unchanged) and
  leave `release` genuinely unsigned in that case, the same "says so rather than claiming a commit it
  was not built from" honesty `versionName`'s own default already practises.
- **CI** (`.github/workflows/ci.yml`, the `publish-apk` job `26-09` added): decode
  `secrets.ANDROID_SIGNING_KEYSTORE_BASE64` to a keystore file in the job (a temp path, never written
  to the repository checkout), pass its path and `secrets.ANDROID_SIGNING_KEYSTORE_PASSWORD` as Gradle
  properties, and **switch the published artifact from `assembleDebug`'s output to
  `assembleRelease`'s** — the actual point of this item, since a `release`-type APK is what a
  stable-across-runs fingerprint is for.
- **Remove the per-run debug keystore's own consequence from the release notes** (`26-09`'s
  "uninstall any previous debug build" paragraph) — it no longer applies once every published build
  shares one signing identity, and a stale warning is worse than none.
- **Record the new secrets** in `docs/architecture/secrets.md` §C (CI) — name, where, scope, class
  (**Breaking** — RuStore Console binds to this fingerprint, and any device holding an app signed with
  the old key could not update over one signed with a new key either) — and in §E if the local keystore
  file itself deserves its own row there (it does: the identical shape the node's SSH key already has).

## Out of scope

- Play Store distribution and an upload key — unchanged, still not needed, still not this item's.
- Enabling `isMinifyEnabled` for release — a separate, real decision with its own testing cost; this
  item only changes *who signs* the release build, not what R8 does to it.
- The actual RuStore Console project setup itself (creating the project, registering this
  fingerprint) — `26-06`'s own scope, unblocked by this item rather than performed by it.
- Rotating the key later, if it is ever lost or compromised — `docs/runbooks/secret-rotation.md`'s
  concern when that day comes, not a procedure to write speculatively now.

## Done when

- [x] A local build (`./gradlew assembleDebug assembleRelease` with `local.properties` populated)
      produces two APKs, both signed with the same real certificate — confirmed by comparing each
      APK's own signing certificate fingerprint (`apksigner verify --print-certs` or equivalent), not
      merely that the build succeeded. Proven twice independently — once by the implementing worker
      with its own throwaway keystore, once by the managing session with a second, separately
      generated throwaway keystore — both times both build types carried that keystore's own real
      fingerprint, not a coincidence of the build merely succeeding.
- [x] A fresh checkout with no `local.properties` entry still builds `assembleDebug` successfully
      (AGP's own default debug signing, unchanged from today) and `assembleRelease` completes without
      crashing, producing an honestly-unsigned artifact rather than failing the whole build. Confirmed
      independently: `app-release-unsigned.apk` — the exact filename AGP itself appends when nothing
      signs it.
- [x] CI's `publish-apk` job publishes a `release`-signed APK, and its own signing certificate
      fingerprint matches the keystore's real fingerprint (`SHA256:
      60:96:05:98:D6:9B:5D:16:AB:A3:70:19:A5:C4:B7:3A:3E:F8:7C:AA:2B:68:97:AD:26:CB:6E:CC:46:34:CC:09`)
      — **verified 2026-09-22**: downloaded the real published release (`release-f0d9eca`) and ran
      `apksigner verify --print-certs` — `60960598d69b5d16aba37019a5c4b73a3ef87caa2b6897ad26cb6ecc4634cc09`,
      an exact match. This did not work on the first two real runs — see Outcome for the real bug
      that caused it and how it was found and fixed.
- [~] Installing a newly-published release APK **over a previous one from an earlier CI run succeeds**
      without an uninstall step — the actual proof the moving-fingerprint problem is fixed. **Not yet
      provable**: `release-f0d9eca` is the first release-signed build that has ever existed for this
      app — there is no earlier one to install over. Will be confirmed the next time any change
      reaches `main` and produces a second release; carried forward informally rather than to `26-22`,
      since it needs no real device or real identity, only a second ordinary CI run.
- [x] The release notes' own "uninstall any previous build" paragraph is removed or corrected.
- [x] `docs/architecture/secrets.md` names both new CI secrets under §C, with the **Breaking** class
      and the reason stated, and the local keystore file's own location under §E.
- [x] `./gradlew ktlintCheck lint test` green; counts reported.

## Outcome

Landed as `ago-android#26`, with a real, load-bearing bug found and fixed the same session in a
follow-up commit on `main` directly (`f6a2433`/`f0d9eca`). The first two real `publish-apk` runs
against the real secrets both failed at `:app:validateSigningRelease` with **"Keystore file not set
for signing config ago"** — a misleading message. The actual cause: the CI workflow passed three of
the four `agoSigning*` properties (path, store password, alias) and simply never passed
`agoSigningKeystorePath`'s sibling `agoSigningKeyPassword` at all, so it evaluated to `null` even
though the keystore file itself was present and correct on the runner the whole time.

**Found by**: a temporary diagnostic `println` (path and existence only, never a password) proved the
keystore file genuinely existed at the expected path when AGP still refused it — ruling out a bad
secret or a bad path — and the real cause was then found by reading the CI workflow's own four-property
contract against what it actually passed. **Confirmed by direct local reproduction**: building with a
throwaway keystore and the identical three properties CI was passing reproduced the exact same error;
adding the fourth (`-PagoSigningKeyPassword`, reusing the same password secret value, since the real
keystore was generated with one password serving both roles) fixed it locally before touching CI again.

**Verified independently, beyond the implementing worker's own report**: re-ran the fresh-checkout and
throwaway-keystore proofs myself with a second, separately generated keystore; watched the real CI
runs fail twice, diagnosed the real cause via a live diagnostic rather than guessing, reproduced and
fixed it locally first; and, once fixed, downloaded the actual first-ever release-signed publish and
confirmed its certificate fingerprint against the real keystore's own recorded value — not assumed
from the workflow succeeding.

**One box left open, informally**: proving an upgrade install over a previous release-signed build
needs a second release to exist, which nothing about this item can force — it will be true the next
time any ordinary change reaches `main`.
