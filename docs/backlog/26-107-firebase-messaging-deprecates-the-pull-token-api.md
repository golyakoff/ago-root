# 26-107 · firebase-messaging deprecates the pull token API the FCM gateway uses

- **Stage**: 26
- **Status**: ready — low priority (the deprecated API still ships and works; this is a forward risk).
- **Found**: 2026-09-25, implementing `26-100`'s Android FCM client. Flagged by the worker, not worked
  around silently.

## What is actually true today

`26-100`'s `FcmPushGateway` (ago-android) uses `FirebaseMessaging.getToken()` / `.deleteToken()` and
`FirebaseMessagingService.onNewToken(String)` — a **pull-based** token model that fits the app's
`PushRegistrationGateway.currentToken(): PushTokenResult` seam (the same shape RuStore's gateway uses).
As of `firebase-messaging 25.1.3` (the pinned version), those three are **deprecated** in favour of a new
opt-in `register()`/`unregister()` + `onRegistered(String)`/`onUnregistered(String)` model that requires
a manifest meta-data flag and delivers the token **asynchronously via callback** rather than returning it.
The client kept the deprecated-but-shipping API with narrow `@Suppress("DEPRECATION")` /
`@Suppress("OVERRIDE_DEPRECATION")` and a doc comment, rather than a redesign the seam does not need yet.

## Scope

- Only becomes real work **if/when Google removes the deprecated `getToken`/`deleteToken`/`onNewToken`**
  (a firebase-messaging major bump that drops them). At that point: migrate `FcmPushGateway` +
  `AgoFcmMessagingService` to the callback-based `register()`/`onRegistered` model, which means teaching
  `PushRegistrationGateway`'s pull seam to accept an async-delivered token (a real seam change affecting
  the RuStore gateway too), and adding the required manifest meta-data flag.
- Until then: keep the pinned version and the `@Suppress`; watch firebase-messaging release notes on each
  bump.

## Out of scope

- Any change while the deprecated API still works — a redesign now would be churn for no behaviour gain.

## Done when

- [ ] Either the deprecated API is confirmed still present on the next firebase-messaging bump (close as
      not-yet-needed, re-file on the bump after), or the callback-based registration model is adopted
      across both push gateways with the pull seam updated and the manifest flag added, tests green.
