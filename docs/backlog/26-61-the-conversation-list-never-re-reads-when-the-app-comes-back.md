# 26-61 · The conversation list never re-reads when the app comes back to the foreground

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, tracing `ConversationListViewModel` and `OperatorHubConnectionLifecycle`
  against `ago-android` `main` at `b099282`.

## Found

Put the app in the background with «Мои» selected. Leave it an hour. Open it again.

The list is an hour old, it shows no sign of being an hour old, and nothing is going to fix it. Not
the hub — it re-subscribes on foreground, but the pushes sent while the socket was down are gone and
the queue is not re-read. Not the poll — it only runs on «Ожидают». Not the staleness banner — that
only exists for a cache read. An operator looks at a screen that is confidently wrong about who is
waiting for them, which is the single thing this app is for.

This is the mirror image of `26-60`: that one is about a load that *failed* and cannot be retried;
this is about a load that *succeeded* and then quietly expired.

## What is actually true today, confirmed against real code

- The screen does tell the view model about the lifecycle — `ConversationListRoute`'s
  `DisposableEffect`/`LifecycleEventObserver`, `ConversationListScreen.kt:104-115`, firing
  `onScreenStarted()` on `ON_START`.
- And `onScreenStarted()` does exactly one thing:
  `ConversationListViewModel.kt:111-113` → `startWaitingPollIfNeeded()`, whose first line is
  `val shouldPoll = mutableState.value.selectedTab == ConversationListTab.Waiting` (`:316`). On
  «Мои», it cancels the (already absent) job and returns. **There is no refresh on this path at all.**
- `refresh()` is called from exactly four places, and none of them is a foreground transition:
  `init` (`:86`), `onActiveSiteChanged` when the site genuinely changed (`:150`), the claim
  success arm (`:208`), and the two hub handlers (`:240`, `:263`).
- The hub handlers cannot cover this. `OperatorHubConnectionLifecycle.onStop`
  (`realtime/OperatorHubConnectionLifecycle.kt:64-66`) disconnects the socket on background — by
  design, `docs/architecture.md` §Realtime — so every `ConversationAssigned` and `MessageReceived`
  sent during that hour was never delivered and never will be. `onStart` reconnects
  (`:56-62`) and `OperatorHubConnection.connect()` replays only `resumeSubscription`
  (`OperatorHubConnection.kt:389-398`), which re-joins **the open conversation** and nothing else —
  there is no conversation open on the list screen, so it is a no-op.
- The view model's own `init` does not re-run: it is a `@HiltViewModel` scoped to the
  `NavBackStackEntry`, and Диалоги is the graph's start destination, so its entry is **never popped**
  (`AppShellScreen.kt:81-88` says so explicitly). The view model outlives every backgrounding.
- `isStale` cannot warn about it: it is set only by the cache read (`:78-85`) and cleared by every
  successful fetch (`:175`).

## Scope

One promise: **the conversation list is re-read whenever the operator comes back to it.**

1. `onScreenStarted()` refreshes, on both tabs, before it decides anything about the poll. The poll
   stays exactly as narrow as it is (`ConversationListViewModel.kt:295-314` argues that narrowness at
   length and is right — a phone is metered); this is a single read on a transition a human just made,
   not a timer.
2. **Only on a genuine foreground return.** A rotation must not count: `ON_START` fires on an
   `Activity` recreation too, and re-fetching the queue on every rotation is the shape
   `OperatorHubConnectionLifecycle.kt:20-27` already rejected for the connection itself and for the
   same reason. Whatever mechanism is chosen — `ProcessLifecycleOwner`, a last-refresh timestamp, or
   both — say in the report which and why, and prove the rotation case.
3. **A refresh already in flight is not duplicated**, the in-flight guard `26-60` also needs.
4. Coming back after a failed refresh lands on `26-60`'s retry body rather than silently retrying
   forever.

## Out of scope

- **Re-reading the thread.** A thread whose join failed is `26-62`; a thread that is open and healthy
  is already covered by `resumeSubscription`'s delta.
- **A "last updated" line on the list.** The mockup draws none, and an accurate refresh removes the
  need for one.
- **Changing the poll's own gate.** It is argued for in the code and this item does not reopen it.
- **Push.** `26-18` is what makes something arrive while the app is not running; this is what the app
  does the moment it is running again. Neither substitutes for the other.

## Done when

- [ ] Backgrounding the app for several minutes, causing a real change from the console, and
      returning shows the change without any interaction — checked on a real device, on both tabs.
- [ ] Rotating the device does **not** issue a queue fetch, proven by a test.
- [ ] No second fetch is issued if one is already in flight when the app foregrounds.
- [ ] The «Ожидают» poll's gate is unchanged.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
