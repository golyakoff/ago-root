# 26-60 · A failed queue load leaves the conversation list with no way to retry — and, on a cold start, spinning forever

- **Stage**: 26
- **Status**: done — merged as [ago-android#90](https://github.com/golyakoff/ago-android/pull/90).
- **Found**: 2026-09-23, tracing `ConversationListViewModel`/`ConversationListScreen` against
  `ago-android` `main` at `b099282`.

## Found

The conversation list has exactly one refresh control, and it is only drawn in a state that a failure
cannot produce. So the two states a failure *does* produce are both dead ends:

- **Cold start, no cache, no network.** A spinner, forever, with a small red line above it. The
  spinner is not lying about work in progress — there is none; the fetch already finished and failed.
  Nothing on the screen can start another one. Backgrounding and returning does not help (`26-61`).
  The only way out is to kill the app.
- **Warm, with rows on screen, and a failed refresh.** The rows stay — which is right, and
  deliberate — but a small red line appears and there is still no control that retries. The list is
  as stale as it will ever be and says so in a way nothing can act on.

## What is actually true today, confirmed against real code

- The only refresh affordance in the app is inside `StaleBanner`
  (`ConversationListScreen.kt:277-293`), and it is drawn only `if (state.isStale)`
  (`ConversationListScreen.kt:201-203`).
- `isStale` is true in exactly one situation: a cached queue was read and no fresh one has arrived
  yet. `ConversationListViewModel.kt:78-85` sets it on the cache read; `refresh()`'s success arm sets
  `render(stale = false)` (`:175`). **The failure arm never touches it** (`:180-186`) — it sets
  `loadError` and nothing else, by design ("the cache stays on screen exactly as it was — only the
  error banner changes").
- So a first-ever launch with no cache row never sets `isStale`, never renders the banner, and never
  offers a refresh.
- The permanent spinner: `render()` is what sets `hasData = true`, and it returns immediately when
  there is no queue at all — `ConversationListViewModel.kt:267`, `val queue = lastQueue ?: return`.
  With no cache and a failed fetch, `lastQueue` stays `null`, `hasData` stays `false`, and
  `ConversationListScreen.kt:213-214` renders `LoadingBody()` — a bare `CircularProgressIndicator`
  (`:296-300`) — indefinitely.
- `loadError` is drawn as a bare `Text` with no action of any kind
  (`ConversationListScreen.kt:204-211`).
- The app already knows the right shape twice over, on less important screens:
  `PermissionsLoadFailedScreen` (`AppShellScreen.kt:361-389`) and `JoinErrorBody`
  (`ThreadScreen.kt:270-288`) are both title-plus-detail-plus-Retry. The busiest screen in the app is
  the one that has neither.

## Scope

One promise: **a failed queue load is always recoverable from the screen it failed on.**

1. **The no-data failure renders as a failure, not as loading.** Replace the indefinite spinner with
   the same title/detail/Retry body the two screens above already use — reuse one of them rather than
   writing a third. The state to branch on is `!hasData && loadError != null`, which is precisely
   "the first load failed and there is nothing to show".
2. **The has-data failure gains a retry.** Whatever `loadError` is drawn as, it carries an action
   that calls `refresh()` — the same `TextButton`-beside-the-message shape `WaitingRow`'s claim error
   (`ConversationListScreen.kt:632-647`) and `ThreadScreen.DismissibleBanner`
   (`ThreadScreen.kt:290-309`) already use.
3. **Retrying is idempotent and shows it is working.** A second tap while a refresh is in flight does
   nothing; the control says it is trying. `refresh()` today has no in-flight guard at all
   (`ConversationListViewModel.kt:155-188`) — one belongs here, and it is the same guard `claim`
   already has (`:196`).
4. `isStale` keeps its current meaning — "this came from the cache" — and is not overloaded to also
   mean "the last refresh failed". Two facts, two fields.

## Out of scope

- **What the error text says.** `26-59` is the item that stops it being a Java class name. This item
  puts an action beside whatever it says; the two are independent and either landing alone is an
  improvement.
- **Pull-to-refresh.** A real gesture worth having, and a different promise — it is about how a
  *successful* list is refreshed on demand, not about recovering a failure. File it separately if
  wanted.
- **Re-reading on foreground** — `26-61`. Same file, different promise: that one is about an app that
  succeeded and then went stale, this one about one that failed.

## Done when

- [x] Launching on a device with no network and no cached queue shows a stated failure with a Retry,
      never an indefinite spinner.
- [x] Restoring the network and tapping Retry loads the queue with no restart.
- [x] A refresh that fails while rows are on screen leaves the rows and offers a Retry.
- [x] Tapping Retry twice quickly issues one request.
- [x] `isStale` still means only "read from cache".
- [x] `./gradlew ktlintCheck lint test assembleDebug` green.
- [~] Both states are covered by JVM unit tests (cold-start failure distinguishable from loading; retry
      loads; refresh-fail keeps rows + Retry; double-tap = one request) and CI is green. **Reproduction
      on a real device with airplane mode is pending — the phone was disconnected 2026-09-24; verify
      when reconnected.**
