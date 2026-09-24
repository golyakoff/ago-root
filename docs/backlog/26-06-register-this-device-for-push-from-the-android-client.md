# 26-06 · Register this device for push from the Android client

- **Stage**: 26
- **Status**: done — [ago-android#67](https://github.com/golyakoff/ago-android/pull/67), independently
  verified by the managing session (`ktlintCheck`/`lint`/`test`/`assembleDebug`/`assembleDebugAndroidTest`
  all green, fresh re-run; 342 unit tests, 0 failures, counted from the JUnit XML per module — `:app`
  143, `:core:network` 112, `:core:domain` 87; the wire DTO was cross-checked against the real server-side
  `Ago.Chat.Api.Me.MeDeviceEndpoints.RegisterDeviceRequest` and `PushProvider` enum in `ago-chat`, not
  just the client's own tests). A real CI Android emulator ran the full instrumented suite green
  (`build-test` 6m25s, `instrumented-tests` 8m55s). Uses the real RuStore Console project id
  (`1Q8iLXwwBZViuznG6eCTHgkzrTE9Bto6`, `25-216`), confirmed against real files before the worker used it
  — not the placeholder this item originally expected to need.
- **Found**: 2026-09-21, the fourth of the four implementation items
  `docs/architecture/push-notifications.md` names at its foot ("The Android client half"). That
  fourth item makes two distinct promises — *the server knows about this device*, and *the phone
  buzzes correctly* — so it is filed as two, per rule 15. **This is the first.** `26-18` is the
  second. `26-03`'s and `26-05`'s own Out-of-scope lines both point at `26-06` for the Android half;
  they were written before that split, and between them they describe this item plus `26-18`.
- **Verified**: 2026-09-21 — the endpoint shapes, the three call sites, the revocation ordering and
  the "a token is a routing address, not a credential" ruling are read from
  `docs/architecture/push-notifications.md` §"Device registration" and `adr/0179`. `26-03`'s own
  Scope names the same two routes, so the contract this item calls is the contract that item builds.
  The RuStore SDK names below are read from RuStore's own Kotlin/Java Push SDK documentation, same
  date.
- **Provider changed**: 2026-09-21. `adr/0180` replaced FCM with **RuStore Push**. This item's
  promise, its two endpoints and its three call sites are unchanged; the SDK behind them is not.
- **Depends on**: `26-03` (the two `Api` routes), `26-12` (a signed-in session and the authenticated
  Ktor client), `26-07`. The client code can be written and tested against a Ktor `MockEngine`
  standing in for the endpoints before `26-03` merges — only the end-to-end proof needs the real
  routes, exactly as `26-05` says for its own fake `IPushSender`.

## What this item is

A signed-in operator's device appears as a live row the fan-out can find, stays correct across token
rotation, and goes silent on sign-out. **Nothing receives or renders anything yet** — that is `26-18`.

## Scope

- **The RuStore Push SDK, wired up.** Concretely, and these are real names rather than a plausible
  shape:
  - repository `https://nexus-external.rustore.ru/repository/maven-rustore-exposed/` — **only this
    address.** RuStore's docs say the older `artifactory-external.vkpartner.ru` *"may stop working at
    some point"*. Its reachability from CI is unestablished and a green local build proves nothing
    about a GitHub Actions runner: **prove it on CI in this item.**
  - dependency `ru.rustore.sdk:pushclient` — 7.4.0 is the newest in the published release history as
    of 2026-09-21; pin whatever is current and say which.
  - `RuStorePushClient.init(application, projectId, logger)` in `Application`, **main process only**
    (the SDK does not support multi-process), or the automatic path via the
    `ru.rustore.sdk.pushclient.project_id` manifest meta-data.
  - a service extending `RuStoreMessagingService`, declared `android:exported="true"` with an intent
    filter on `ru.rustore.sdk.pushclient.MESSAGING_EVENT`.
- **There is no `google-services.json` equivalent, and that removes a whole decision this item used
  to carry.** RuStore initialisation takes a **project-ID string**, nothing more — no credentials
  file to keep out of the repository, no `.example` shape, no CI secret for the build job. The
  project ID is not a secret either: it ships inside the APK's own manifest, readable by anyone with
  a copy. It is still supplied as configuration rather than hard-coded across build types, because of
  the next point.
- **A RuStore Console push project per build type.** RuStore requires the installed build's
  **signature fingerprint** to match the one registered under Push notifications → Projects, and
  notes that debug and release signatures and package names differ — so debug and release each need
  their own console project and therefore their own project ID. This is a real setup chore with no
  FCM equivalent in this item's old scope; budget for it and write it down in
  `ago-android/docs/architecture.md`.
- **A stable `installationId`**, generated once per install and stored. It is **not** the push token:
  the row's identity is `(operator_id, installation_id)`, and that single decision is what makes token
  rotation work at all rather than accumulating one dead row per rotation for ever.
- **`PUT /api/v1/me/devices/{installationId}` called in all three places the design names**, because
  each covers a case the others do not:
  - on **every sign-in**, with the token from `RuStorePushClient.getToken()` (which mints one if the
    device has none);
  - from **`RuStoreMessagingService.onNewToken(token)`** — the provider's own rotation callback, and
    the only event that can tell the app its token changed. RuStore's documentation says in so many
    words that after it fires the app is responsible for delivering the new token to its own server.
    Tokens do rotate: the SDK's release history records two versions (6.8.0, 6.9.1) that changed the
    reissue logic so they rotate *less* often, which is a statement that they rotate;
  - from **a periodic `WorkManager` job**, because `onNewToken` cannot fire for an app that was not
    running when the rotation happened. This third one is what turns the server's
    `last_seen_at` into a liveness signal rather than a record of the last sign-in. State the
    interval chosen and why.
- **Report what `RuStorePushClient.checkPushAvailability()` actually returns, and do not hide an
  `Unavailable`.** RuStore Push needs a *distributor* app (RuStore, or an undisclosed VK fallback) on
  the device, RuStore un-restricted in the background, and **the operator signed in to a RuStore
  account** — a longer prerequisite list than FCM's Play Services, and `26-01`'s own
  §"What the operator's phone has to satisfy" has it in full. This item does not have to solve it;
  it has to make it **visible** rather than letting registration look successful on a phone that can
  never receive anything. `onError` also surfaces `HostAppNotInstalledException`,
  `HostAppBackgroundWorkPermissionNotGranted` and `UnauthorizedException` — handle all three, noting
  that RuStore says the last may not be raised even when it applies.
- **Answer, from the real console: does push work for an app registered under Push notifications →
  Projects but never published through RuStore?** The condition list asks for uploaded app data and a
  matching fingerprint, not for a published listing, but does not say the two are independent, and
  RuStore's documentation does not settle it. It decides whether the operator app can be distributed
  as a direct APK, so it is a real finding and not a detail. Record it in
  `docs/architecture/push-notifications.md`.
- **`DELETE /api/v1/me/devices/{installationId}` on sign-out, *before* the access token is
  discarded** — after that the call cannot authenticate. The console has no equivalent step (its
  sign-out makes no backend call at all), so this ordering is new here and easy to get backwards.
  Call `RuStorePushClient.deleteToken()` alongside it — an affordance the FCM design never named, and
  the device's own half of the same act. It is the device discarding its token, not a claim about
  what RuStore's server retains, which `26-01` records as unestablished.
- **One row per tenancy, not per identity.** A Keycloak identity may hold several `Operator` rows, so
  signing into a second site registers again and one physical phone legitimately holds two rows. The
  alternative would mean a notification about tenant A reaching a device registered while working for
  tenant B, and `tenant-isolation.md`'s whole claim is that every piece of data is scoped by
  `site_id` — a notification is a piece of data.
- **The token is a routing address, not a credential**: not encrypted on the device beyond ordinary
  app-private storage, and never written to a log at any level. Note the SDK takes an optional
  `logger` and defaults to logcat — make sure whatever is wired there does not print a token.

## Out of scope

- Receiving, rendering or suppressing a push (`26-18`), including any latency measurement.
- The notification settings screen (`26-19`).
- Everything server-side — `26-03` (the rows and routes), `26-04` (the RuStore adapter), `26-05` (the
  fan-out).

## Done when

- [x] A fresh install plus sign-in produces exactly one registration call; a second sign-in on the
      same install **updates** that row rather than creating a second one. Proven against a Ktor
      `MockEngine`, not the real `26-03` endpoints — the DTO shape was independently cross-checked
      against the real server-side handler instead.
- [x] `onNewToken` re-registers with the same `installationId` and the new token. Unit tested.
- [x] The periodic job re-registers, and its interval is stated in the item and in
      `ago-android/docs/architecture.md` — 24h, `NetworkType.CONNECTED`.
- [x] Sign-out calls `DELETE` **before** the token is discarded — proven by a fails-before/works-after
      test with the order deliberately reversed and restored at the `DeviceRegistrationCoordinator`
      level; the `AgoAuthSession`-level instrumented assertion of the same property compiles but could
      not run on a real emulator in this sandbox.
- [x] Signing into a second tenancy produces a second row rather than overwriting the first — true by
      construction (`installationId` never varies, `X-Ago-Active-Site` does; `ActiveSiteHeaderPluginTest`
      already proves the header behaviour generically).
- [x] No push token appears in logcat at any level or in any committed file, from this app's own code —
      grepped, exactly two log calls exist and neither touches a token variable. **Not settled**: whether
      RuStore's own bundled `DefaultLogger()` itself ever prints a token — unverifiable without a real
      device, and the SDK's own logger is used deliberately (not a filtering wrapper) so a real-device
      check of this box means something when someone runs it.
- [~] CI resolves `ru.rustore.sdk:pushclient` from `nexus-external.rustore.ru` — **now proven**: PR #67's
      own `build-test` and `instrumented-tests` jobs both ran green on a real GitHub Actions runner,
      which could not have happened without that resolution succeeding. Pinned version: **7.5.0** (not
      the 7.4.0 this item originally recorded — the newest at the time this item was actually built).
- [~] `checkPushAvailability()`'s result on the test device — **not recorded**, no physical device with
      a RuStore account available in this sandbox. The mechanism is wired and surfaced, not hidden; the
      actual reading is a real-device task.
- [x] Whether push works without publishing the app through RuStore — **answered, 2026-09-24: yes.**
      The author installed the unpublished `v0.14.1` release APK directly on a real phone, signed in,
      and received real RuStore push notifications against the live demo backend.
      `docs/architecture/push-notifications.md` records the finding.
- [x] `./gradlew ktlintCheck lint test` green — 342 tests, 0 failures (`:app` 143, `:core:network` 112,
      `:core:domain` 87), independently re-run by the managing session, not just the worker's report.
