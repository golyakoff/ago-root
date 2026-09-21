# 26-14 · The conversation list

- **Stage**: 26
- **Status**: ready
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

- [ ] Both segments render against the live API on a real phone.
- [ ] A conversation assigned while the list is open appears **without the screen navigating**, proven
      by a test as well as observed.
- [ ] Killing the network still renders the cached list, visibly marked stale, with no spinner
      blocking it.
- [ ] Claiming a waiting conversation moves it to «Мои»; a claim of one another operator already took
      renders the server's refusal and does not retry.
- [ ] The list survives rotation and returning from the background with its scroll position intact.
- [ ] `./gradlew ktlintCheck lint test` green; counts reported.
