# 26-17 · Settings: theme, active site, О приложении, and sign-out

- **Stage**: 26
- **Status**: done — `ago-android#25`
- **Found**: 2026-09-21. Three other items in this wave lean on this screen and none of them owns it:
  `26-09` stamps a commit into the APK that nothing displays, `26-12` implements a sign-out with no
  control, and `26-06` needs that control to exist before it can hang device revocation off it.
- **Verified**: 2026-09-21 — `scope-inventory.md` §10 records `/appearance` as folded into an
  app-level Settings screen rather than standing alone; §11 records the active-site switcher as a
  screen with no console equivalent; `navigation.md` records that the sign-in screen deliberately
  names no deployment and that the build variant's name lives here instead.
- **Depends on**: `26-16` (the Ещё list this hangs from), `26-12` (the session and the sign-out
  mechanism).

## What this item is

The Settings screen and the four rows it carries in this wave. One promise: **an operator can see and
change what the app itself does.**

## Scope

- **The Settings screen**, reached from the foot of Ещё.
- **Тема** — the three-state system / light / dark choice `/appearance` already is, folded in rather
  than given its own destination (`scope-inventory.md` §10), sitting beside whatever `26-10` decided
  about Android 12+ dynamic colour.
- **Текущий сайт** — the active-site switcher. `GET /api/v1/me/tenancies` feeds it; switching
  re-points the single source of truth `26-12`'s header plugin reads and the hub's own query-string
  parameter, then returns to Диалоги. It exists because one identity can hold operator seats at
  several sites (`adr/0068`), and `26-12` only ever *picks* one at sign-in.
- **О приложении** — the build variant's name and the commit `26-09` stamped into `versionName`. This
  is deliberately where the deployment is named, because the sign-in screen deliberately is not: the
  debugging need is real and it is served better where a tester looks and an operator does not
  (`navigation.md`).
- **Выход** — the control for the sign-out `26-12` implements. Once `26-06` lands it also revokes this
  device's push registration, and the ordering (revoke while the token is still valid, *then* discard
  it) belongs to that item.

## Out of scope

- **Уведомления** — `26-19`. It needs push to exist first, and a settings screen whose switches
  control nothing is the dishonesty `26-19` exists to remove.
- **Удалить аккаунт.** It belongs at the foot of Settings and nowhere else (`scope-inventory.md` §9 —
  a deliberate friction, and the honest alternative to excluding a capability the operator legitimately
  holds), but it destroys a whole tenant irreversibly and it is not this wave's to build.
- Every other Ещё row — channels, automation, administration.
- Presence and the Away control.

## Done when

- [x] All three theme states apply immediately and survive a process restart. Immediate apply is
      architectural, not tested-and-hoped: `MainActivity` and `SettingsScreen` collect the identical
      `DataStore<Preferences>` singleton, so a write from one is visible to the other with no event
      bus. Restart survival is proven for real — two independently-constructed `DataStore`s over the
      same on-disk file, modelling process death, not an in-memory cache surviving by accident.
- [~] An operator with seats at **two** sites switches between them and the conversation list changes
      accordingly — proven against two real tenancies, since a switcher tested with one tenancy tests
      nothing. **Carried to `26-22`** — no real multi-tenancy identity exists in this environment; the
      mechanism itself (REST header + hub reconnect, both awaited) is unit-tested against fakes.
- [x] Switching the active site re-points **both** the REST header and the hub connection, not just
      the header. Proven by a test asserting both a fake's REST call and its hub-reconnect call fire
      (an implementation stopping at the REST-only easy case fails it) — confirmed correct by reading
      `OperatorHubConnection`'s new `reconnectToActiveSite`/`discardConnection` directly against the
      existing `disconnect()`/`connect()`/`stopRequested` mechanics, not merely trusting the test.
- [x] О приложении names the exact commit the installed APK was built from — checked against the
      release `26-09` published, not against a local build where the value is easy to fake.
      **Verified 2026-09-22**: downloaded the real `ago-android` GitHub Release published from this
      item's own merge commit (`debug-62aef98`), confirmed via `aapt2 dump badging` that
      `versionName='62aef98'` — the exact commit — and confirmed by reading `SettingsScreen.kt`
      directly that it reads this same `BuildConfig.VERSION_NAME` value, not a separate one.
- [x] Sign-out returns to the launch screen and leaves no token behind — proven by inspecting the
      encrypted store afterwards, not by the UI having navigated away. A real, on-device
      `EncryptedSharedPreferences` file, seeded then cleared — with a real nuance found running it:
      `clear()` deliberately leaves its own two Tink keyset entries behind, so the test asserts the
      raw file's key set equals exactly those two reserved keys, not zero.
- [x] `./gradlew ktlintCheck lint test` green; counts reported. 163 tests (65 `:core:network`, 44
      `:core:domain`, 54 `:app`), 0 failures; ktlint clean. Plus 28 instrumented tests, 0 failures, run
      on a real emulator.

## Outcome

Landed as `ago-android#25`. A persisted three-state theme choice over `androidx.datastore-preferences`
(chosen over Room or plain `SharedPreferences` specifically because it is provably testable on a plain
JVM with a real temp file and no Android `Context`, unlike either alternative); an active-site switcher
that re-points the REST header and forces the hub connection to drop and rebuild against the freshly
selected site before returning to Диалоги, hidden entirely for a single-tenancy (or not-yet-known)
identity; О приложении reading `BuildConfig` directly as its first in-app consumer; Выход wired to the
existing sign-out flow unchanged.

**A real finding along the way**: `EncryptedSharedPreferences.clear()` deliberately leaves its own two
Tink keyset entries behind rather than truly emptying the file — confirmed by decompiling the library
class directly rather than guessing, after the first real on-device run of the sign-out test failed
against a naive "zero keys" assumption. The test now asserts the exact reserved-key set instead.

**Verified independently, beyond the implementing worker's own report**: read every load-bearing file
directly (`DataStoreThemePreferences`, `SettingsViewModel`, `OperatorHubConnection`'s new methods),
confirmed the hub-reconnect sequencing is correct and non-redundant against the pre-existing
disconnect/connect/`stopRequested` mechanics; re-ran the full suite myself (163 unit + 28 instrumented
tests, matching the worker's own counts exactly); and, beyond what the worker's own worktree could
do, downloaded the actual published release built from this item's own merge commit and confirmed its
real `versionName` live, rather than trusting a local build where the value is easy to fake.

**One box carried to `26-22`**: the two-real-tenancies site-switch proof, the identical real-identity
precondition every other Phase-0-adjacent item's remainder already carries there.
