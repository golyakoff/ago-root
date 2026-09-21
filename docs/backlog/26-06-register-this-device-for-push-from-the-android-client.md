# 26-06 · Register this device for push from the Android client

- **Stage**: 26
- **Status**: ready
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
- **Depends on**: `26-03` (the two `Api` routes), `26-12` (a signed-in session and the authenticated
  Ktor client), `26-07`. The client code can be written and tested against a Ktor `MockEngine`
  standing in for the endpoints before `26-03` merges — only the end-to-end proof needs the real
  routes, exactly as `26-05` says for its own fake `IPushSender`.

## What this item is

A signed-in operator's device appears as a live row the fan-out can find, stays correct across token
rotation, and goes silent on sign-out. **Nothing receives or renders anything yet** — that is `26-18`.

## Scope

- **The Firebase SDK, and `google-services.json` kept out of the repository.** It is not a credential
  in Google's own model, but everything in these repositories is public and this project's rule admits
  no "it is probably fine" — so it is supplied from a CI secret for the build job and from an
  untracked local file for a developer, with a `google-services.json.example` carrying **the shape and
  no values**, which is the same treatment `secrets.md` gives an `.env.example`. `26-07` already
  gitignores the real file. *If the author would rather commit it, that is a one-line change here and
  a sentence in `ago-android/docs/architecture.md` — but it should be a decision, not a default.*
- **A stable `installationId`**, generated once per install and stored. It is **not** the FCM token:
  the row's identity is `(operator_id, installation_id)`, and that single decision is what makes token
  rotation work at all rather than accumulating one dead row per rotation for ever.
- **`PUT /api/v1/me/devices/{installationId}` called in all three places the design names**, because
  each covers a case the others do not:
  - on **every sign-in**;
  - from **`FirebaseMessagingService.onNewToken`** — Google's own rotation callback, and the only
    event that can tell the app its token changed;
  - from **a periodic `WorkManager` job**, because `onNewToken` is not guaranteed to fire if the app
    was not running when the rotation happened. This third one is what turns the server's
    `last_seen_at` into a liveness signal rather than a record of the last sign-in. State the
    interval chosen and why.
- **`DELETE /api/v1/me/devices/{installationId}` on sign-out, *before* the access token is
  discarded** — after that the call cannot authenticate. The console has no equivalent step (its
  sign-out makes no backend call at all), so this ordering is new here and easy to get backwards.
- **One row per tenancy, not per identity.** A Keycloak identity may hold several `Operator` rows, so
  signing into a second site registers again and one physical phone legitimately holds two rows. The
  alternative would mean a notification about tenant A reaching a device registered while working for
  tenant B, and `tenant-isolation.md`'s whole claim is that every piece of data is scoped by
  `site_id` — a notification is a piece of data.
- **The token is a routing address, not a credential**: not encrypted on the device beyond ordinary
  app-private storage, and never written to a log at any level.

## Out of scope

- Receiving, rendering or suppressing a push (`26-18`).
- The notification settings screen (`26-19`).
- Everything server-side — `26-03` (the rows and routes), `26-04` (the FCM adapter), `26-05` (the
  fan-out).

## Done when

- [ ] A fresh install plus sign-in produces exactly one registration call; a second sign-in on the
      same install **updates** that row rather than creating a second one. Say whether this was proven
      against the real `26-03` endpoints or against a `MockEngine` recording.
- [ ] `onNewToken` re-registers with the same `installationId` and the new token.
- [ ] The periodic job re-registers, and its interval is stated in the item and in
      `ago-android/docs/architecture.md`.
- [ ] Sign-out calls `DELETE` **before** the token is discarded — proven by asserting the call order,
      not by the absence of a symptom.
- [ ] Signing into a second tenancy produces a second row rather than overwriting the first.
- [ ] No FCM token, and no `google-services.json` value, appears in logcat at any level or in any
      committed file.
- [ ] `./gradlew ktlintCheck lint test` green; counts reported.
