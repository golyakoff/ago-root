# 26-283 · «Записать» from the client-detail hub deep-links into manual booking, pre-filled

- **Stage**: 26. Kind: implementation (Android). The **deferred** B4 item from the 26-269
  clients-vs-mockup gap analysis (commit `3f43742`). Filed 2026-09-29 so nothing from the analysis is
  untracked.
- **Status**: planned. Depends on the manual-booking entry flow (26-268) exposing an entry point that can
  be opened pre-filled for a known person.
- **Repos touched**: `ago-android` (the client-detail hub + manual-booking wizard entry).

## The gap (from the analysis)

The mockup's client-detail hub carries a «Записать» action that starts a **new booking for this client**.
The manual-booking wizard (26-268) already recognises a client and can reuse a `PersonId`
(`ReusePersonId`), so this is a navigation/deep-link into that flow with the client pre-selected — the
operator skips the phone/recognition step and lands on service selection.

## The one promise

From a client's detail hub, «Записать» opens the manual-booking wizard already bound to that client
(reusing its `PersonId`), skipping phone entry and recognition.

## Done-when

- [ ] The client-detail hub shows «Записать»; tapping it opens the manual-booking wizard pre-bound to the
      client's `PersonId` (reuse path), starting at service selection rather than phone entry.
- [ ] Strings both languages; `ktlintCheck`/`testDebugUnitTest`/`assembleDebug`/`compileDebugAndroidTestKotlin` green.
