# 26-14 · The conversation list

- **Stage**: 26
- **Status**: done — `ago-android#19`; remainder carried out to `26-22`
- **Found**: 2026-09-21, the third of `plan.md`'s Phase 0 screens and the first thing an operator
  actually sees after signing in.
- **Verified**: 2026-09-21 — the waiting queue's own refresh is a poll, not a broadcast:
  `ago-console/src/workspace/WorkspaceLayout.tsx:33` sets `WAITING_REFRESH_INTERVAL_MS = 15_000`.
  **Note this corrects the approved documents**, which call it "a 10-second poll"
  (`docs/architecture/push-notifications.md`, §"The server-side signals that already exist"): the
  mechanism is right, the number is not. The underlying finding stands — nothing broadcasts "a new
  conversation started waiting", so the list is refreshed by asking.
- **Depends on**: `26-13`, `26-10`.

## What this item is

The list an operator opens the app to, live over the hub, readable offline, with waiting conversations
claimable from it. One promise: **an operator sees their work.**

## Scope

- **One screen with a segmented control, not two screens** — «Мои» and «Ожидают». `navigation.md`'s
  own reasoning: splitting them into sibling destinations would make claiming a waiting conversation a
  navigation act rather than a decision.
- **Rows rendering `VisitorDisplayPrefix`** (`26-10`) — the emoji pair at its larger size, the
  optional name, the eight-character short code in monospace — plus unread count and last activity.
- **Live updates over the hub**, ordered by the server-assigned `sequence` and never by a timestamp.
- **Claiming a waiting conversation**, and rendering the server's refusal as a refusal when somebody
  else claimed it first — never retried into a success. That is `architecture.md`'s Offline rule read
  from the write side: the server is the answer.
- **Room, arriving with its first consumer.** The conversation list is cached and rendered **stale
  until proven fresh** — the screen never blocks on the network to show what it already has. Nothing a
  write decision turns on is cached (`CLAUDE.md` rule 8, read from the client side).
- **A new assignment never navigates.** A badge and a count and a live update in place; nothing that
  moves the operator mid-sentence. This is the console's own stated rule and it is exactly the kind of
  behaviour that regresses silently, so it gets a test (`26-20` runs it in CI).
- **The «Ожидают» refresh is a poll, and the interval is stated on the item's own terms** — the
  console uses 15 seconds because there is no server-side signal to subscribe to. Match it or diverge
  deliberately, and say which; a phone polling on a mobile connection is not free.

## Out of scope

- The thread (`26-15`).
- Search, `/conversations/all` and `/conversations/restricted` — the app-bar overflow, and all three
  are `site:configure`-gated. A later wave.
- Tag filter chips — they need the tag vocabulary, which nothing has loaded yet.
- The bottom navigation bar and its badge host (`26-16`) — this item renders a list, not a shell.

## Done when

- [~] Both segments render against the live API on a real phone. **Carried to `26-22`** - no real
      authenticated session exists in this environment.
- [x] A conversation assigned while the list is open appears **without the screen navigating**, proven
      by a test as well as observed. `ConversationListViewModelTest`'s own "never navigates" case -
      confirmed by reading `ConversationListViewModel` directly: it has no navigation channel of any
      kind, only a badge (`newlyAssignedIds`) and a re-fetch.
- [x] Killing the network still renders the cached list, visibly marked stale, with no spinner
      blocking it. Proven with a `FakeConversationsApi` whose fetch call hangs forever
      (`awaitCancellation()`), confirming the cache render happens with the network call still
      genuinely pending - not merely fast.
- [x] Claiming a waiting conversation moves it to «Мои»; a claim of one another operator already took
      renders the server's refusal and does not retry. Proven with `advanceTimeBy(60_000)` after a
      refusal showing zero further calls.
- [~] The list survives rotation and returning from the background with its scroll position intact.
      Architecturally covered (`rememberLazyListState`'s own `rememberSaveable` mechanism) - **carried
      to `26-22`** for an actual on-device confirmation, since no automated test exercises a real
      Activity recreation here.
- [x] `./gradlew ktlintCheck lint test` green; counts reported. 108 tests (31 `:core:domain`, 56
      `:core:network`, 21 `:app`), 0 failures; ktlint clean.

## Outcome

Landed as `ago-android#19`. One screen, one segmented control - the first real destination after
sign-in. Room's first consumer: the queue is cached and rendered stale-until-proven-fresh, a `null`
cache read kept distinct from a genuinely empty queue (`RoomConversationListCacheTest`, 4 tests, run
live on the `ago-test` emulator by the implementing worker). `OperatorHubConnection` (`26-13`) gains
two new, purely additive flows (`allMessages`, `assignments`) behind a new `OperatorHubEvents`
interface - `MessageSubscription`'s own join-scoped dedup contract is untouched. `assignments` wires
the real, pre-existing `"ConversationAssigned"` hub push nothing in this client had subscribed to
before this item. Claiming a waiting conversation is a real `POST
/api/v1/conversations/{id}/claim` every time; a refusal is shown once, never retried. The «Ожидают»
poll matches the console's real 15-second interval (correcting the approved docs' stale "10-second"
claim) but runs only while that tab is selected and the screen is foregrounded - narrower than the
console's own always-on timer, since a phone pays real metered-data cost a browser tab does not.

**Verified independently, beyond the implementing worker's own report, against the real backend
source**: confirmed `OperatorHubConnection`'s extension is purely additive (read the diff line by
line); confirmed `"ConversationAssigned"` is a real, pre-existing hub method
(`ResolveConversationAssignmentTargetsHandler.cs`'s own `const string Method`), not invented, and its
DTO field names match `Ago.Chat.Contracts.ConversationAssignedDto` exactly; confirmed both REST
endpoints (`GET /api/v1/conversations/queue`, `POST /api/v1/conversations/{conversationId:guid}/claim`)
are real, existing routes in `ConversationsEndpoints.cs`; confirmed `"Visitor"` matches the real
`MessageAuthorKind` enum exactly. Re-ran the full build myself, green; confirmed all 108 tests from
the real JUnit XML. The 4 Room instrumented tests were not re-run myself (the emulator had stopped by
review time) - not judged worth relaunching solely for that, given everything else checked out
precisely.

**Two boxes carried to `26-22`** (a real phone/session, and an on-device rotation confirmation) -
the identical real-session precondition that item already exists for.
