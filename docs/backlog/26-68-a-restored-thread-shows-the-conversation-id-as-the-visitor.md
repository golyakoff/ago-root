# 26-68 · A thread restored after process death shows the conversation's id as the visitor's

- **Stage**: 26
- **Status**: done — merged as [ago-android#76](https://github.com/golyakoff/ago-android/pull/76). A
  real finding along the way: `26-40` had already retired the app bar's own eight-character code before
  this landed, so the bug's original visible symptom no longer reproduced on `main` — the fabricated
  value was dead data, read by nothing. The defect was still real for any future consumer of
  `visitorId`, and the attachment-grant/permanent-mismatch cases were both fully live; documented in
  `ago-android/docs/architecture.md`.
- **Found**: 2026-09-23, tracing `ConversationsTabHost`'s row lookup against `ago-android` `main` at
  `b099282`.

## Found

Open a conversation. Let Android kill the process (developer options' "don't keep activities", or
simply leave the app alone on a busy phone long enough). Return to the app.

The thread reopens — correctly, `openConversationId` is a `rememberSaveable` — but the row it needs
for the visitor's identity has not been fetched yet. The lookup returns `null`, and the fallback
substitutes **the conversation's own id** into the `visitorId` slot. `VisitorDisplayPrefix` then
renders `shortId` of it: eight monospace hex characters, in exactly the place and exactly the format a
real visitor short code appears in.

Nothing on screen distinguishes it from a real visitor identifier. The operator is shown a
plausible-looking wrong answer as fact — on a screen whose whole job is to say who they are talking
to.

The same lookup also decides whether the paperclip exists, so the attach control silently disappears
for that conversation until the queue lands.

## What is actually true today, confirmed against real code

- The lookup and its four fallbacks, `shell/ConversationsTabHost.kt:66-74`:

  ```kotlin
  val row = (listState.mine + listState.waiting).firstOrNull { it.conversationId == currentlyOpen }
  stateHolder.SaveableStateProvider("$SAVEABLE_KEY_THREAD_PREFIX$currentlyOpen") {
      ThreadRoute(
          conversationId = currentlyOpen,
          visitorId = row?.visitorId ?: currentlyOpen,
          emojiCreature = row?.emojiCreature,
          emojiFood = row?.emojiFood,
          visitorName = row?.visitorName,
          hasAttachmentUploadGrant = row?.hasAttachmentUploadGrant ?: false,
          …
  ```

  Three of the four are honest — `null` means "unknown" and renders as absent. `visitorId` is the one
  that substitutes a different, real value rather than admitting it does not know.
- What that produces: `ThreadScreen`'s title is `VisitorDisplayPrefix`
  (`ThreadScreen.kt:192-200`), whose `parts.visitorId` is always rendered through `IdentifierText`
  (`ui/components/VisitorDisplayPrefix.kt:62`) — `shortId(...)`, eight hex characters, monospace. A
  conversation id and a visitor id are both GUIDs, so the two are indistinguishable by shape.
- `openConversationId` genuinely does survive process death —
  `ConversationsTabHost.kt:51`, `rememberSaveable` — while `ConversationListViewModel` does not, so
  this state is reachable, not hypothetical. It is also reachable, more briefly, on any cold return
  where the thread is restored before the first queue fetch completes.
- It can be **permanent**, not only transient: the row is looked up in `mine + waiting` only. A
  conversation that has since left both halves — closed, or reassigned — never matches, and the wrong
  identifier stays on screen for as long as the thread is open.
- `26-40` touches the same slot but does not cover this: its own scope makes the title the *name*
  alone and states that a thread with no row in hand "renders no subtitle rather than a guessed one".
  That is the right instinct applied to the subtitle; this is the same instinct owed to the identifier
  that is still drawn.

## Scope

One promise: **the thread never presents a substituted value as the visitor's identity.**

1. Remove the `?: currentlyOpen` fallback. `visitorId` becomes genuinely absent when unknown, joining
   the three fields next to it, and the title renders whatever parts are real — the identical
   "absence is absence, never a blank placeholder" rule `VisitorAvatar`
   (`ui/components/VisitorAvatar.kt:28-36`) and `visitorDisplayPrefixParts` already state for every
   other part of this identity.
2. `VisitorDisplayPrefix` has to tolerate an absent `visitorId`. It takes it as a non-null `String`
   today (`VisitorDisplayPrefix.kt:42`) and always renders it; making it optional is a small change to
   one composable and to `:core:domain`'s `visitorDisplayPrefixParts`, whose existing tests already
   cover the other absence combinations.
3. **`hasAttachmentUploadGrant` gets a stated answer rather than an inherited default.** Defaulting to
   `false` hides a control an operator may be entitled to, with no indication. Either the row is
   fetched for a restored thread, or the control is absent until it is known — pick one, and say which
   in the report; do not leave `?: false` unexamined now that it has been noticed.
4. The permanent case is named on screen or fixed: a conversation no longer in either half of the
   queue must not sit forever showing nothing where an identity belongs without the operator being
   able to tell that is what happened.

## Out of scope

- **Fetching a single conversation summary by id.** That would solve (3) and (4) outright and is the
  better long-term answer — but there is no such endpoint in this app's `ConversationsApi` today and
  adding one is a separate promise spanning `ago-chat`. If the item concludes that is the real fix,
  it files it rather than growing to include it.
- **The title's own layout and the subtitle** — `26-40`. Whichever lands second should read the
  other; they share the slot and not the promise.
- The list-to-thread handoff on the ordinary path, which is correct and unchanged.

## Done when

- [~] Killing the process with a thread open and returning never shows a conversation id where a
      visitor identifier belongs — not reproduced on a real device by the managing session yet; the
      fallback itself is removed and covered at the unit level.
- [x] A thread whose conversation is not in either half of the queue does not display a fabricated
      identity — `identityUnavailable`, derived from `listState.isStale`.
- [x] The ordinary path — tapping a row — renders exactly as it does today (unchanged; `row` is always
      found on that path).
- [x] `visitorDisplayPrefixParts`' tests cover the newly-possible absent-id combination — 5 new cases,
      20 total in the file.
- [x] The attachment-grant fallback has a stated answer: `Boolean?`, "absent until known" chosen over a
      silent `false`.
- [x] `./gradlew ktlintCheck lint test assembleDebug` green — 435 tests, 0 failures, independently
      re-verified with `--rerun-tasks`.
