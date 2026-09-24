# 26-67 · Switching between «Мои» and «Ожидают» loses the other tab's scroll position

- **Stage**: 26
- **Status**: done — merged as [ago-android#104](https://github.com/golyakoff/ago-android/pull/104).
- **Found**: 2026-09-23, reading `ConversationListScreen`'s two list composables against
  `ago-android` `main` at `b099282`.

## Found

Scroll down «Мои». Tap «Ожидают» to check whether anybody is waiting. Tap «Мои» again — you are back
at the top.

The two lists are two different composables in two branches of the same `when`, and each calls
`rememberLazyListState()` for itself. Switching tabs disposes one branch's composition and creates the
other's, so the departing list's scroll offset is discarded rather than kept. `rememberSaveable`'s own
`Bundle` round trip — which is what makes the position survive a rotation and a process death — does
**not** retain a value across a sibling's disposal; only a `SaveableStateHolder` does.

This is a small thing that is annoying every single time: the segmented control is on screen
precisely so that flicking between the two halves is cheap, and it is cheap in one direction only.

## What is actually true today, confirmed against real code

- The branch:

  ```kotlin
  // ConversationListScreen.kt:213-225
  when {
      !state.hasData -> LoadingBody()
      state.selectedTab == ConversationListTab.Mine -> MineList(...)
      else -> WaitingList(...)
  }
  ```

- `MineList` creates its own state at `ConversationListScreen.kt:321`; `WaitingList` creates its own
  at `:587`. Neither is hoisted and neither is keyed.
- **The rotation guarantee is real and is not what this item breaks.** `MineList`'s doc comment
  (`:302-309`) is correct that `rememberLazyListState` restores across a configuration change and a
  process death; `26-14`'s Done-when asked for exactly that and got it. The tab-switch case is simply
  a different one, and nobody looked at it.
- Both lists early-return before creating the state when they are empty (`:316-319`, `:582-585`), so
  a tab that loads empty and later fills starts at the top legitimately — that case is correct and
  must stay.
- **The fix pattern is already in this repository, one file away.** `ConversationsTabHost`
  (`shell/ConversationsTabHost.kt:52-82`) uses `rememberSaveableStateHolder()` with a
  `SaveableStateProvider` per key, precisely so that backing out of a thread returns to the list with
  its scroll position intact (`26-15`'s own Done-when, back-contract clause 1). The segmented control
  needs the same thing one level down, keyed by tab.

## Scope

One promise: **each tab keeps its own scroll position across a tab switch.**

1. A `rememberSaveableStateHolder` around the two lists, one `SaveableStateProvider` key per
   `ConversationListTab`, exactly the shape `ConversationsTabHost.kt:52-67` already uses — not a pair
   of hoisted `LazyListState`s, which would have to be created eagerly for a tab that may never be
   opened and would not survive process death without extra work.
2. Both lists keep their empty-state early return. A tab that has no rows has no position to keep.
3. The rotation and process-death behaviour `26-14` proved stays proven — this adds a case, it does
   not replace one.

## Out of scope

- **Remembering which tab was selected across process death.** `selectedTab` lives in
  `ConversationListUiState` (`ConversationListViewModel.kt:103-106`), which is a plain `ViewModel`
  field with no `SavedStateHandle` behind it — so it survives a rotation and not a process death.
  That is a real, separate gap; if this change makes it obvious, file it rather than folding it in.
- **The tab counts** — `26-39`.
- **Scroll position across a bottom-bar tab switch.** Already handled for free: Диалоги is the
  graph's start destination and its back stack entry is never popped
  (`AppShellScreen.kt:81-88`), so nothing is disposed when the operator visits Записи and returns.

## Done when

- [x] Scrolling «Мои», switching to «Ожидают» and back returns to the same position — checked on a
      real device with enough conversations to scroll.
- [x] The same in the other direction.
- [x] Rotating the device still preserves the visible tab's position.
- [x] A tab that has no rows still opens at the top once rows arrive.
- [x] `./gradlew ktlintCheck lint test assembleDebug` green.
