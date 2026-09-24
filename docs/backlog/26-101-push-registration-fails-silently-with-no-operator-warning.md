# 26-101 · Push registration fails silently — the operator is never told push won't work

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-24, live debugging with the author. On a device with no RuStore/VK push host,
  `RuStorePushClient.getToken()` fails (`Host push app is not installed`, `No available hosts found`),
  the client classifies it as a quiet `false` (per `KtorDeviceRegistrationApi`'s catch-all), no device
  row is ever created, and **the operator sees nothing** — the app looks signed-in and normal while it
  can receive no pushes at all. This silence is what made the real problem take a whole session to find.

## What is actually true today

The registration path (sign-in, `onNewToken`, the periodic worker) treats "could not get a push token"
and "registered successfully" as indistinguishable to the operator. There is no surface — no banner, no
settings indicator — that says "push notifications will not arrive on this device." `26-82` fixed the
*server* race that dropped registrations; this is the *client* side of the same silent-failure family:
the operator has no signal that their device is unregistered or its token stale.

## Scope

- `ago-android`: when push-token acquisition or device registration fails (no host, IPC failure,
  non-2xx from the server), show the operator a clear, persistent-until-resolved indication that push
  is not working on this device, with a short reason (e.g. "the RuStore app is required for
  notifications"). Exact copy/placement is a small design call inside this item.
- Distinguish "no push host installed" (actionable by the operator) from a transient network failure
  (retry quietly) — do not nag on a blip.

## Out of scope

- Changing the transport itself — that is `26-100` (FCM primary + RuStore fallback). This item is about
  *telling the operator the truth* whatever transport is in play; it stays relevant after `26-100`
  (e.g. a de-Googled device that also lacks a RuStore host).
- The periodic worker not instantiating in release — that is `26-102`.

## Done when

- [ ] A device that cannot obtain a push token (no host / IPC failure) shows the operator a clear,
      non-transient warning instead of silently succeeding — asserted in a test.
- [ ] A transient network failure does not raise that warning (retried quietly).
- [ ] `./gradlew ktlintCheck lint test` green.
