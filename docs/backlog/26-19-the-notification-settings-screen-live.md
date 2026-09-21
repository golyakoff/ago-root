# 26-19 · The notification settings screen, live

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-21. `scope-inventory.md` §11 designs this screen with **every control disabled
  behind one banner naming the backend item that has to land first** — a deliberate choice over
  honest-limits copy, because "a screen that only explains what the app cannot do is a screen nobody
  designs the good version of later". This item is the good version, and by the time it runs the
  banner's condition is satisfied.
- **Verified**: 2026-09-21 — `ago-console/src/workspace/AlertSettings.tsx` exists and is this
  screen's ancestor; the mapping is deliberately not one-to-one, because a browser has no notification
  channels. The Away-is-per-operator fact is `architecture.md` §Realtime, from the Redis registry
  keying presence as a *set* of connection ids per operator.
- **Depends on**: `26-18` (there must be channels that do something), `26-17` (the Settings screen
  this hangs from).

## What this item is

The operator controls which pushes are loud, on the device where they are holding the phone. One
promise: **the switches on this screen are true.**

## Scope

- **A switch per notification channel that actually exists** — the two `26-05` sends and no others.
  The mockup drew five kinds (назначенный диалог, сообщение в открытом диалоге, запись ждёт решения,
  дедлайн подтверждения, сообщение команде) because it was designed against what push *would*
  deliver; rendering a switch for an event nothing emits reintroduces exactly the dishonesty the
  disabled banner existed to avoid. **The screen names no channel nothing sends**, and the ones not
  yet emitted are not drawn.
- **The banner comes off**, and this item is where it does.
- **Channel importance stays the OS's.** Where Android owns a setting, the row deep-links into the
  system channel settings rather than keeping a second, disagreeing copy of it — a mismatch between an
  in-app switch and the OS's own is the classic Android notification bug and it is free to avoid.
- **Quiet hours, client-side only.** Not on the server: the phone already has Do Not Disturb, a
  server-side schedule would be a less capable copy of an OS feature, and it would introduce a
  timezone question (`date-and-time.md`) for a rule nobody has asked for — `adr/0179`'s own "What this
  design deliberately leaves out".
- **The Away note, stated where the control would be.** `SetAwayAsync` is **per operator, not per
  connection**: setting Away on the phone sets Away for the desktop console too. That is the server's
  existing semantics and the app's job is to say so rather than invent a per-device variant
  (`architecture.md`).

## Out of scope

- Per-operator quiet hours on the server.
- An actual Away control — it belongs where presence lands, in a later wave. This screen carries the
  note, not the switch.
- Web Push for the console. `adr/0179` names retiring the browser `Notification` API in favour of a
  service-worker path as genuinely attractive future work and explicitly not this.

## Done when

- [ ] Turning a channel off actually stops that kind of notification on a real phone — proven by
      sending one afterwards, not by the switch's own state.
- [ ] Quiet hours suppress a push, and the screen is honest about what happens to it (whether it still
      lands silently in the tray or not — either is fine, but the copy must match the behaviour).
- [ ] The screen names no channel that nothing sends.
- [ ] Changing channel importance in the OS settings and returning shows the app agreeing with it
      rather than contradicting it.
- [ ] The Away note is on screen and nothing beside it implies a per-device setting.
- [ ] `./gradlew ktlintCheck lint test` green; counts reported.
