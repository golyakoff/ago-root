# 26-99 · Push notifications never peek because the channels ship at DEFAULT importance

- **Stage**: 26
- **Status**: done — channels ship at `IMPORTANCE_HIGH` (`ago-android` `eae5f9d`); heads-up peek and
  lock-screen display confirmed by the author 2026-09-25 on the crash-fixed fresh install.
- **Found**: 2026-09-24, by the author on a real device — "телефон даже выключенный должен пикать
  уведомлением в шторке, я настроил чтобы было видно", but nothing peeks. Confirmed live over `adb`.

## What is actually true today, confirmed against the real device and code

`ago-android`'s `ensureChannelsCreated` (`app/src/main/kotlin/ago/chat/android/devices/PushNotificationChannels.kt`)
creates all three push channels — `ago.push.assignment`, `ago.push.visitor_message`, `ago.push.waiting` —
at `NotificationManager.IMPORTANCE_DEFAULT`. The code comment there (from `26-18`) claims DEFAULT gives
"a heads-up/lock-screen-visible notification". **That is false on API 26+**: a heads-up *peek* (over the
current screen, and shown on the lock screen) requires `IMPORTANCE_HIGH`. DEFAULT rings but does not peek.

Verified on the author's real device (LineageOS, `ago.chat.android` build `0.24.0+4b4050b`) with
`adb shell dumpsys notification` — all three channels report `mImportance=3` (`IMPORTANCE_DEFAULT`),
`mUserLockedFields=0` (the operator never changed them by hand). Everything else the symptom could have
been was checked the same way and ruled out: `POST_NOTIFICATIONS` granted, the app on the doze
battery-whitelist, and the presence foreground service alive (`isForeground=true`). The *only* gap is the
channel importance.

## Scope

- `ago-android`: create the three **push** channels at `NotificationManager.IMPORTANCE_HIGH` instead of
  `IMPORTANCE_DEFAULT`. The presence channel (`ago.presence.online`, the ongoing foreground-service
  notification) is **not** one of these and stays quiet — it is created separately and must not become a
  heads-up.
- Correct the misleading comment that says DEFAULT already peeks.

## Out of scope

- Per-channel importance the operator can configure — that is `26-19` (the notification settings screen),
  which will let an operator turn any of these *down*. This item only fixes the default they start at.
- `setPriority`/`setCategory` on the notification builder: `minSdk` is 26, so `setPriority` is never read
  (importance comes from the channel on every device this app runs on). No behaviour rides on adding it.
- The separate "a burst of ~10 pushes arrives at once" investigation — that is `26-83`, still open.

## Notes on landing

- A channel's importance cannot be *raised* by re-creating it with the same id — Android only lets the
  user raise it, or the app create it higher on first install. So the fix reaches an existing install only
  on a fresh install (or a new channel id). With active development and no real operators yet, a reinstall
  is acceptable; a channel-id bump was considered and declined as unnecessary ceremony (author, 2026-09-24).

## Done when

- [x] All three push channels are created at `IMPORTANCE_HIGH`; the presence channel is unchanged.
      Landed `ago-android` `eae5f9d` (`fix(26-99): create push channels at IMPORTANCE_HIGH so notifications peek`).
- [x] `./gradlew ktlintCheck lint test` green — passed in CI on the merged PR.
- [x] Proven on a real device: a visitor message to a waiting/assigned conversation produces a heads-up
      that peeks over the screen and shows on the lock screen. Confirmed by the author 2026-09-25 on the
      crash-fixed fresh install (the reinstall that the raised-importance constraint above required):
      the heads-up peeks and shows on the lock screen ("оба сработали", alongside 26-100's instant delivery).
