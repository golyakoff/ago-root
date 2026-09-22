# 25-218 · Signing in does not reliably connect the hub on a real device

- **Stage**: 25
- **Status**: done — `ago-android#29`
- **Found**: 2026-09-22, live, on a real physical device — the second time this exact symptom
  appeared this session. The first time (during `26-17`'s own live phone verification), it
  self-resolved within a few seconds and was read at the time as ordinary connection-establishment
  latency. The second time, immediately after installing the first real `release`-signed build
  (`25-215`), it did not resolve: the conversation list showed **Соединение: Отключено**
  indefinitely, and opening the one real conversation threw `IllegalStateException:
  OperatorHubConnection: connect() has not been called yet`. Neither the retry control nor a full
  sign-out/sign-in cycle changed it.

## What is actually true today, confirmed against real code

`OperatorHubConnectionLifecycle` (`26-13`) is the **only** place `OperatorHubConnection.connect()` was
ever called, and it is wired exclusively to `ProcessLifecycleOwner.onStart` — the process entering the
foreground — gated on `SignInSession.hasSession()`. `SignInViewModel`'s own doc comment stated this
explicitly: *"this view model neither connects nor disconnects it."*

That design assumes finishing the Custom Tab OAuth round trip produces a fresh
`ProcessLifecycleOwner.onStart` — the natural moment `hasSession()` would flip from `false` to `true`
inside an already-running foreground session. **On at least one real device, it does not reliably
produce that transition.** The app's own process never genuinely left the foreground from Android's
point of view during the Custom Tab flow, so `onStart` never fires again after the very first, cold-launch
one (at which point `hasSession()` was still `false`) — and nothing else was wired to ask the question a
second time. Every subsequent action (opening the app, retrying, signing out and back in) also produces
no fresh process-foreground transition, so the hub stayed permanently unconnected until an operator
happened to background the app for real (e.g. pressing Home) and reopen it.

This gap was invisible to every existing test: `26-13`'s own suite proves the lifecycle binding itself
correct in isolation, and nothing in this stage's test suites drives a real OAuth Custom Tab round trip
on a real device — the exact class of gap this stage's own `26-22` exists to name and carry forward.
This one, unusually, was cheap enough to fix immediately rather than carry.

## Fix

`SignInViewModel.routeNow()` — the one function every sign-in path (`onAuthorizationResult`,
`chooseSite`, and `resumeSession`'s cold-start path) already funnels through — now also calls
`hubConnection.connect()` the moment routing resolves to `SignInDestination.Operator`. Fire-and-forget,
on its own `viewModelScope` child, wrapped in `runCatching`: a transient network failure connecting
must never fail sign-in itself, and must never surface as an uncaught exception from a best-effort
attempt. `OperatorHubConnection.connect()` is already documented idempotent, so this costs nothing on
whichever path already worked (the process-foreground trigger still exists and still matters for
backgrounding/reconnect) and fixes the path that did not.

## Out of scope

- Removing or restructuring `OperatorHubConnectionLifecycle` itself — its process-foreground binding
  remains the correct mechanism for reconnecting after a real background/foreground cycle or a network
  drop; this item only adds the missing connect-on-sign-in trigger alongside it.
- A real device proof that this specific fix resolves the symptom on the exact device that reported
  it — genuinely useful but not performed in this item; the unit-level proof (a real code path now
  provably calls `connect()`, where before it provably did not) is what a session without a phone in
  hand can offer. Worth a quick live confirmation whenever a phone is next in hand.

## Done when

- [x] `SignInViewModel.routeNow()` calls `hubConnection.connect()` when routing resolves to `Operator`,
      on all three of its call sites (verified by reading the single shared function, not three
      separate call sites).
- [x] A transient connect failure cannot fail sign-in itself or crash — `runCatching`, fire-and-forget.
- [x] A new test proves the connect attempt actually happens (observing the hub's own connection-state
      flow transition through `Connecting`), confirmed failing before the fix and passing after by an
      actual revert-and-rerun, not by inspection alone.
- [x] `./gradlew ktlintCheck lint test assembleDebug` green.

## Outcome

Landed as `ago-android#29`. Confirmed unit-level: the shared `routeNow()` function now provably
attempts a hub connection on every path that reaches the signed-in screen, where before this fix it
provably did not (a temporary revert reproduced the exact real-device symptom's own root cause in the
test suite). Not yet re-confirmed live, on the real device that reported the symptom — the author was
only able to test the published release build at the time this was found, not a local debug install;
worth a quick live confirmation once a phone is in hand alongside the next release.
