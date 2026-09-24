# 26-62 · A thread whose join failed does not recover when the hub comes back

- **Stage**: 26
- **Status**: done — merged as [ago-android#79](https://github.com/golyakoff/ago-android/pull/79)
- **Found**: 2026-09-23, tracing `ThreadViewModel` against `OperatorHubConnection` on `ago-android`
  `main` at `b099282`.

## Found

Open a conversation with a bad connection. The join fails and the thread shows "не удалось", a detail
line, and a Retry button. Now the signal comes back: the connection dot in the app bar — on this very
screen, two lines above the error — turns green and says «Подключено».

The thread stays broken. It sits on its error body until a human taps Retry.

The view model is *watching* the connection state. It just does not act on it: the collector exists
solely to paint the dot. So the screen ends up showing two contradictory things at once — "the link is
healthy" and "this conversation could not be loaded" — and the operator has to work out that the
second one is stale.

## What is actually true today, confirmed against real code

- The collector, and its whole body:

  ```kotlin
  // ThreadViewModel.kt:92-96
  viewModelScope.launch {
      hubEvents.state.collect { connectionState ->
          mutableState.update { it.copy(hubConnectionState = connectionState) }
      }
  }
  ```

  Its own comment says why it exists — so that "seeing the connection flap while a `pendingRetry`
  banner is up is not a coincidence an operator should have to guess at". That reasoning is right and
  is exactly the argument for going one step further.
- The failed-join state: `launchJoin`'s catch sets `joining = false, historyError = ...`
  (`ThreadViewModel.kt:152-157`), and `retryJoin()` (`:137-142`) is the only thing that ever clears
  it. Nothing calls `retryJoin` but the button.
- **The connection is not what is broken, and that is the subtle part.** `joinConversation` calls
  `subscription.join(conversationId)` **first** (`OperatorHubConnection.kt:176`), before the invoke
  that fails. So the connection's own `resumeSubscription` (`:389-398`) *will* re-join this
  conversation on the next successful reconnect and *will* push the delta into `messages`. The result
  is a second, stranger state: messages start arriving into a screen still rendering its join error.
  `ThreadScreen.kt:240-241` only draws `JoinErrorBody` while `state.messages.isEmpty()`, so the error
  body silently vanishes the moment the first delta message lands — the screen repairs itself by
  accident, at an unpredictable moment, and not at all in a quiet conversation where no new message
  arrives.
- The send path is already better than this: a failed send sets `pendingRetry` and the banner offers
  a retry (`ThreadScreen.kt:220-226`), and `retrySend` is careful about which client message id is
  safe to reuse (`ThreadViewModel.kt:258-262`). The join path got none of that care because nobody
  had hit it.

## Scope

One promise: **a thread that failed to load loads itself when the connection comes back.**

1. The existing `hubEvents.state` collector gains one behaviour: a transition **into**
   `Connected` while `historyError != null` and this instance still has a conversation open re-drives
   the join, through `retryJoin()` — the same function the button calls, not a second path.
2. **A transition, not a state.** `Connected` is a `StateFlow` value that is re-emitted on every
   collection start; re-joining on "is currently connected" rather than "just became connected" would
   fire on every rotation. Prove the rotation case.
3. **It never fights the connection's own resume.** `resumeSubscription` re-joins from
   `lastKnownSequence`; this re-join is the full `joinConversation` and asks from nothing. Both are
   idempotent at the screen (`mergeAndRender` is insert-or-replace by id,
   `ThreadViewModel.kt:306-310`), so the cost of both happening is a duplicate fetch, not a duplicate
   message — but the item should say which one it let win and why.
4. **The error body does not disappear by accident.** Clearing `historyError` becomes something this
   class does deliberately, not something `ThreadScreen.kt:240`'s `messages.isEmpty()` guard does as a
   side effect.

## Out of scope

- **Automatic retry of a failed send.** `pendingRetry` is deliberately manual
  (`ThreadViewModel.kt:284-295`), because "nothing was sent" and "an invoke was genuinely in flight"
  need different client message ids, and guessing wrong duplicates a message in front of a customer.
  Nothing here touches it.
- **A failed "load older" page.** Same `historyError` field, different situation: the operator asked
  for it explicitly and there is already a retry banner in the list (`ThreadScreen.kt:355-359`). Only
  the *initial join* recovers automatically.
- **The conversation list's own foreground refresh** — `26-61`.
- **What the error text says** — `26-59`.

## Done when

- [~] Opening a thread with the network off shows the join error; restoring the network loads the
      thread with no tap — not checked on a real device by the managing session yet; proven at the
      `ThreadViewModelTest` level with a real reconnect transition.
- [x] Rotating the device on a healthy thread issues no extra join, proven by a test.
- [x] The dot and the thread body never simultaneously claim connected-and-failed — proven by a test
      collecting every state emission during recovery.
- [x] `retryJoin` remains the one entry point; there is no second join path.
- [x] `./gradlew ktlintCheck lint test assembleDebug` green — 440 tests, 0 failures, independently
      re-verified with `--rerun-tasks`.
