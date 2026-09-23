# 26-46 · The bottom bar's Диалоги tab carries no unread badge

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, reading the approved mockup Artifact ("AGO Chat для Android",
  `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`) against `ago-android` `main` at `ad2859b`.

## Found

Every frame in the mockup that draws the bottom bar — the conversation list's and the Ещё screen's
alike — puts a small count on the Диалоги icon, and it is drawn in the palette's alarm colour, not the
brand one:

```html
<div class="on"><span class="ind"><svg class="i"><use href="#i-chat"/></svg><span class="nb">3</span></span><span>Диалоги</span></div>
<div><span class="ind"><svg class="i"><use href="#i-cal"/></svg><span class="nb">2</span></span><span>Записи</span></div>
```

```css
.bnav .nb{
  position:absolute; top:1px; right:9px; min-width:16px; height:16px; padding:0 4px; border-radius:8px;
  background:var(--danger); color:var(--on-danger); font-size:10px; font-weight:700; display:grid; place-items:center;
}
```

The number is the one the rows themselves add up to: the drawn list carries unread badges of `2` and
`1`, and the tab badge reads `3`. It is an unread count, not a list length — which is also why it is
`--danger` here while the row's own `.badge` is `--brand`: on a tab you are not looking at, "somebody
is waiting on you" is the message.

The app's bottom bar draws no badge on any tab.

This is the one thing in the app that survives leaving the Диалоги screen, and the reason the app
exists at all is that an operator is not looking at it. Until push lands (`26-18`), it is the *only*
thing that tells an operator, while they are on Ещё or Настройки, that something arrived.

## What is actually true today, confirmed against real code

- `app/src/main/kotlin/ago/chat/android/shell/AppShellScreen.kt:246-269` builds every tab identically
  and passes no `badge` to any of them:

  ```kotlin
  destinations.forEach { destination ->
      val route = destination.route()
      NavigationBarItem(
          selected = currentRoute == route,
          onClick = { … },
          icon = {
              Icon(
                  imageVector = destination.icon(),
                  contentDescription = stringResource(destination.labelRes()),
              )
          },
          label = { Text(text = stringResource(destination.labelRes())) },
          colors = itemColors,
      )
  }
  ```

  Material 3's `NavigationBarItem` has no badge parameter of its own — the ordinary recipe is
  `BadgedBox` wrapping the `icon` slot, which is where the count goes.
- **The number exists per row already.** `ConversationSummary.operatorUnreadCount`
  (`core/domain/.../conversations/ConversationSummary.kt`) comes straight off
  `ConversationSummaryDto.OperatorUnreadCount`
  (`ago-chat/src/Ago.Chat.Contracts/ConversationSummaryDto.cs:84`), and
  `ConversationRowUi.unreadCount` (`conversations/ConversationListUiState.kt:20`) is what the row's
  own `UnreadBadge` already renders (`ConversationListScreen.kt:454-456`). Nothing new is needed from
  the backend.
- **It is not reachable from the shell today, and that is the real work in this item.**
  `AppShellContent` has no conversation state at all; the rows live behind
  `ConversationListViewModel`, whose `ViewModelStore` is scoped to the `conversations`
  `NavBackStackEntry` (`AppShellScreen.kt:81-88` explains that scoping deliberately). Reading it from
  the shell by hoisting that view model up would undo the property that whole doc comment defends.
  There is already a process-wide source of the same rows — `RoomConversationListCache`
  (`data/conversations/RoomConversationListCache.kt`), backed by `ConversationRowDao` — and a
  process-wide singleton is the shape the hub connection already uses
  (`realtime/OperatorHubConnectionLifecycle`).
- The colour exists: `--danger` is `colorScheme.error` in this scheme.

## Scope

One promise: **the Диалоги tab shows how many messages are waiting unread, wherever the operator is
in the app.**

1. A single source of "total unread across my assigned conversations", observable from
   `AppShellContent` without hoisting `ConversationListViewModel` out of its own nav entry — the
   `Room`-backed cache is the obvious candidate, since it already holds every row and already survives
   a tab switch. Whatever it is, it must be the *same* numbers the list's own per-row badges render,
   never a second count computed a second way, or the two will disagree in front of the author.
2. The count is drawn on the Диалоги tab with `BadgedBox`, in the mockup's `.nb` treatment — `error`
   fill, small, bold, at the icon's top-trailing corner. No badge at all when the count is zero, and
   none before the first answer has arrived (the same "never a `0` that really means unknown" rule
   `26-39` states for the tab counts).
3. It updates live. A hub push that bumps a row's unread count while the operator is on Ещё must bump
   this badge without a navigation; opening a conversation must clear its contribution. Both are
   already the list's own behaviour — this must observe the same state, not re-implement the rules.
4. A `contentDescription` that says what the number is. A bare numeral announced after a tab name is
   meaningless; the row badge has the same gap and can be fixed alongside if it falls out naturally.

## Out of scope

- **The Записи badge.** The mockup draws `2` there; there is no bookings feature in this app and
  nothing behind it. It arrives with the screen.
- **Push.** `26-18` is what makes a notification arrive when the app is not running at all; this badge
  is what the app shows once it is. They are complementary and neither substitutes for the other.
- The row's own `UnreadBadge`, which is already correct (`26-23` built it, `26-30` moved it) — except
  for the accessibility note in part 4, if it is genuinely the same fix.

## Done when

- [ ] Диалоги carries an `error`-coloured count matching the sum of the list's own unread badges.
- [ ] No badge when there is nothing unread, and none before the first load answers.
- [ ] The badge changes live while the operator sits on Ещё — verified on a real device with a real
      message arriving, not a fixture.
- [ ] Opening the conversation clears its contribution without a restart.
- [ ] The list's per-row badges and this one never disagree.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
