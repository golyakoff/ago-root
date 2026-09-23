# 26-63 · Every inbound message re-fetches the whole queue, one request per message

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, tracing `ConversationListViewModel`'s hub handlers against `ago-android`
  `main` at `b099282`.

## Found

Two hub handlers on the conversation list each end in an unconditional `refresh()`, and `refresh()`
is a full `GET /api/v1/conversations/queue`. There is no coalescing, no debounce, and no in-flight
guard anywhere on that path.

So a busy shop — three visitors typing, an operator answering, a walk-in being assigned — produces one
whole-queue fetch **per push**, on a device that is frequently on a metered connection. Ten messages
across the operator's own conversations in a few seconds is ten identical requests, nine of which are
answered by a response the tenth supersedes.

This is not a theoretical throughput worry. It is the exact cost the same class already reasoned
about carefully — and then only for the poll.

## What is actually true today, confirmed against real code

- `ConversationListViewModel.kt:240` — `onAssigned` ends in `refresh()`.
- `ConversationListViewModel.kt:263` — `onMessage` ends in `refresh()`, for **every** message on a
  conversation assigned to this operator, including the operator's own echoed-back send. `26-30`
  widened it from visitor-only to all-authors on purpose (the snippet has to move for any new
  message) and the comment at `:250-259` explains that correctly — the widening is right; the
  un-coalesced fetch behind it is what this item is about.
- Both are `viewModelScope.launch`es with no guard: `refresh()` (`:155-188`) checks nothing before
  calling `api.fetchQueue()`.
- Each of those fetches also **writes the cache** on success
  (`:177`, `withContext(ioDispatcher) { cache.write(result.queue) }`), so a burst is N HTTP round
  trips *and* N Room writes.
- The class already holds the argument against exactly this. `startWaitingPollIfNeeded`'s doc comment
  (`:295-314`) spends nineteen lines establishing that "a phone is not the same machine" as a desktop
  browser, that it "is frequently on a metered connection", and that the console's own always-on timer
  is therefore deliberately narrowed here. That reasoning applies to a push-driven fetch storm at
  least as strongly as to a 15-second timer — it was simply never applied to this path.
- There is no ordering hazard being protected against: `refresh()` overwrites `lastQueue` wholesale
  and re-renders, so a slow response landing after a fast one can currently move the list *backwards*.
  Coalescing removes that too, as a side effect rather than as the point.

## Scope

One promise: **a burst of pushes produces one queue read, not one per push.**

1. Both handlers stop calling `refresh()` directly and instead request a refresh through one
   coalescing path — a conflated channel, a `MutableSharedFlow` with `debounce`, or a plain
   "already-scheduled" flag; any is fine. Say which and why in the report.
2. **A small window, chosen and stated, not guessed.** Long enough that a conversational burst
   collapses; short enough that a single arriving message still moves the row promptly — an operator
   watching the list must not see a noticeable lag appear where there is none today. If the chosen
   number is argued from anything other than "this is what feels right", say so; if it is not
   measured, do not claim it is (`CLAUDE.md` rule 7: this item makes no throughput claim, only a
   request-count one, which is countable without a load test).
3. **The last request always wins.** Whatever coalescing is used, a push arriving *during* an
   in-flight fetch must still produce one more fetch afterwards — collapsing it into the response
   already on the wire would lose the very message that triggered it.
4. The unread-bump bookkeeping (`unreadBumps`, `:260-262`) and the newly-assigned overlay
   (`newlyAssignedIds`, `:232`) stay immediate and per-push — they are local state, they cost
   nothing, and they are what makes the badge feel live while the fetch is being debounced.

## Out of scope

- **The 15-second «Ожидают» poll.** Argued for at length in the code and unchanged here. If the
  coalescing path happens to make the poll's own call site tidier, that is a bonus, not the promise.
- **Not re-fetching at all** — assembling a row from the push payload instead. The class's own doc
  comment (`:32-42`) explains why that is wrong: a push carries no visitor, no emoji pair and no name,
  and synthesising a row from three GUIDs is the defect `ago-console`'s `WorkspaceLayout.tsx` found
  first. Re-asking for the truth stays the mechanism; only how often is in question.
- **The foreground refresh** — `26-61` — and **the in-flight guard for the manual retry** — `26-60`.
  Both touch `refresh()`; neither is this promise, and this item should not try to be the one that
  unifies all three.

## Done when

- [ ] Ten messages arriving across assigned conversations within a few seconds produce one queue
      fetch, not ten — counted, not asserted (the request count is observable with a proxy or a
      counting fake in a view-model test).
- [ ] A single message arriving on its own still updates the row without a perceptible delay on a real
      device.
- [ ] A push arriving while a fetch is in flight still results in a subsequent fetch.
- [ ] The unread badge and the «Новый» pill still change the instant the push arrives.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
