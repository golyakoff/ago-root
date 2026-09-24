# 26-88 · The thread screen still shows a bare hub-connection dot, left over from before `26-77`

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-24, by the author, live on a real device — "если выбрать конкретный диалог, то всё
  ещё видно рудиментарную зелёную точку (одну, без кружочка пользователя) справа. Она смущает здесь."
- **Verified — root cause already found**: `ThreadScreen.kt`'s own `TopAppBar` still renders
  `HubConnectionDot(state = state.hubConnectionState, modifier = Modifier.padding(end = 16.dp))` in its
  `actions` block (`app/src/main/kotlin/ago/chat/android/thread/ThreadScreen.kt:247`) — the bare,
  pre-`26-77` component `AccountAvatarAction` replaced everywhere else. `26-77`'s own scope was the five
  *top-level* screens; `ThreadScreen` is a drill-down reached from Диалоги, not one of the five, so it
  was never touched and the old dot survived.

## Scope

- Remove the `HubConnectionDot` from `ThreadScreen`'s `actions` block and its now-unused import. A
  drill-down screen reached from Диалоги has no account-menu context of its own (no sign-out, no
  settings belongs mid-conversation), and the hub's connection state is already visible one screen back
  via `AccountAvatarAction`'s own dot — this screen does not need a second, duplicate indicator.

## Out of scope

- Designing a replacement in-thread connection indicator (e.g. a subtle "reconnecting…" banner while
  reading a specific conversation) — if that turns out to be wanted, it is a new, separate item with its
  own number; this item's own promise is removing what confuses, not designing what might replace it.

## Done when

- [ ] The bare dot is gone from `ThreadScreen`'s app bar; the `HubConnectionDot` import is removed if
      nothing else in this file uses it.
- [ ] `./gradlew ktlintCheck lint test` green; counts reported.
