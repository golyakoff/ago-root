# 26-87 · The account avatar sits 8dp off in «Ещё», causing a visible shift on tab switch

- **Stage**: 26
- **Status**: done — [ago-android#71](https://github.com/golyakoff/ago-android/pull/71), independently
  verified by the managing session (fresh non-cached re-run: 205 real tests, 0 failures; the worker's
  own claimed 200 was off by 5 — a report error, not a code error). A real CI Android emulator ran the
  full instrumented suite green.
- **Found**: 2026-09-24, by the author, live on a real device — "кружочек пользователя с зелёной точкой
  раздела «Ещё» смещён от правого края на 2 миллиметра влево относительно своего же положения во всех
  других разделах... эффект смещения при переключении между разделами."
- **Verified — root cause already found, not left for the worker to search for**: `MoreScreen.kt`'s own
  `AccountAvatarAction(...)` call passes `modifier = Modifier.padding(end = 12.dp)`
  (`app/src/main/kotlin/ago/chat/android/shell/MoreScreen.kt`); the other four top-level screens
  (`ConversationListScreen.kt`, `BookingsScreen.kt`, `TeamChatScreen.kt`, `AnalyticsScreen.kt`) all pass
  `end = 4.dp`. The 8dp difference is what reads as a ~2mm shift on a real phone.

## Scope

- Change `MoreScreen.kt`'s `AccountAvatarAction` call to `end = 4.dp`, matching the other four screens
  exactly.
- Confirm no other divergent value exists anywhere else `AccountAvatarAction` is placed (grep for the
  call site count — five is the expected number, one per top-level screen).

## Out of scope

- Any other spacing in `MoreScreen`'s own `TopAppBar` — only this one value is wrong.

## Done when

- [x] All five top-level screens pass the identical `end = 4.dp` to `AccountAvatarAction` — confirmed by
      grep across all five call sites.
- [x] `./gradlew ktlintCheck lint test` green — 205 tests, 0 failures, independently re-run and counted
      by the managing session.
