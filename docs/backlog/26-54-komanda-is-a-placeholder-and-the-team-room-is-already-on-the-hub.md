# 26-54 · Команда is a placeholder, and the team room is already on the hub this app is connected to

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, reading `ago-console/src/pages/TeamChatPage.tsx` and
  `ago-console/src/realtime/operatorConnection.ts` against `ago-android` `main` at `b099282`, with the
  approved mockup Artifact ("AGO Chat для Android", `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`)'s own
  navigation graph (`subgraph T["3 · Команда"]`: `TeamChat["Общение"]`, `People["Люди"]`).

## Found

Команда is the cheapest real screen left in this app, and the reason is structural: **the team room
rides the operator hub this app already holds open.** No new base URL, no new REST client, no new
permission — `GetTeamHistoryAsync`, `SendTeamMessageAsync` and the `TeamMessageReceived` push are
methods on `/hubs/operator`, which `OperatorHubConnection` is already connected to for every
signed-in session.

`OperatorHubConnection`'s own doc comment says so, and lists this as one of exactly two things it
deliberately does not do yet (`OperatorHubConnection.kt:81-82`): "`SetAwayAsync`/presence and the team
chat's own hub traffic — no backlog item has reached either yet." This is that item.

It is also ungated. `TeamChatPage.tsx:29-30`: one room per tenant, "every operator in it
unconditionally — this screen carries no permission gate, unlike almost every other screen".

## What is actually true today, confirmed against real code

- `app/src/main/kotlin/ago/chat/android/shell/PlaceholderScreens.kt:57-62` is the whole destination,
  wired at `AppShellScreen.kt:284`.
- The hub methods, verbatim from `ago-console/src/realtime/operatorConnection.ts`:
  - `GetTeamHistoryAsync(beforeSequence, pageSize)` → `TeamHistoryPage` (`:491-492`)
  - `GetTeamDeltaAsync(afterSequence)` → `TeamHistoryPage` (`:500-501`)
  - `SendTeamMessageAsync(body, clientMessageId)` → `number` (`:462-469`)
  - `RemoveTeamMessage` (`:485`), and the two pushes `TeamMessageReceived` / `TeamMessageRemoved`
    (`:216`, `:223`)
- **The arity rule applies.** `OperatorHubConnection.kt:74-79` states it for the three methods it
  already calls: "a hub method's parameter count is a contract" — always send every argument, never
  fewer. The four above inherit that unchanged.
- **Two behaviours from the console are load-bearing and must port, not be re-derived:**
  1. The first load waits for the connection to actually be up. `TeamChatPage.tsx:52-60` records that
     a first cut called `getTeamHistory` on mount and crashed on a reload landing straight on
     `/team/chat`, and that a fake connection in a component test never caught it. Android's own
     equivalent hazard is `OperatorHubConnection.requireConnection()`
     (`OperatorHubConnection.kt:281`), which throws outright before the first `connect()`.
  2. A reconnect catches up by **delta**, not by re-joining. `TeamChatPage.tsx:62-70`: a team room has
     no `JoinConversationAsync` analogue, so the only gap a reconnect opens is pushes missed while the
     socket was down, and the page already knows its last rendered sequence — hence `GetTeamDeltaAsync`.
- **No left/right sides.** `TeamChatPage.tsx:43-50`: every message renders identically regardless of
  author, because the console has no route to the caller's own operator id. Android has the same
  limitation and must make the same choice rather than inventing a "mine" side that would be wrong.

## Scope

One promise: **Команда is the team room, and messages sent from a phone reach the console and back.**

1. `OperatorHubEvents` grows the four team-chat methods and the two pushes, alongside the
   conversation ones it already carries — same file, same arity discipline, same "a screen never sees
   a `com.microsoft.signalr` type" rule.
2. A `TeamChatViewModel` + screen: keyset history upward, live receive, send with a
   `clientMessageId`, and the same send-result trichotomy `ThreadViewModel` already models
   (`SendMessageResult.NotConnected` / `OutcomeUnknown` / `Refused`, `ThreadViewModel.kt:275-302`).
   Reuse that type; do not write a second one.
3. The first history read waits for `OperatorHubConnectionState.Connected` rather than firing on
   composition, and a reconnect fetches the delta after the last rendered sequence rather than
   reloading the room.
4. The admin label the console draws stays — it is the one distinction this screen does make, and it
   comes from the server.

## Out of scope

- **Люди, the operator roster.** `26-55`. It is gated (`site:manage_operators`), it is a different
  read, and it needs the segmented control this item does not add. Команда with one screen and no
  segmented control is the honest shape until then, exactly as `MoreScreen` draws one row today
  (`MoreScreen.kt:138-143`).
- **Removing a team message.** `RemoveTeamMessageButton` is an admin action with its own confirmation
  and its own push; it is a separate promise and worth its own item.
- **The unread badge on the Команда tab.** `26-46` builds the badge mechanism for Диалоги; the team
  room's own count follows it, not this item.
- `SetAwayAsync`/presence, still.

## Done when

- [ ] An operator opens Команда and sees the tenant's real team room with history.
- [ ] A message sent from the phone appears in the console's `/team/chat` and vice versa, live, with
      no restart.
- [ ] Killing the network mid-session and restoring it catches the room up by delta, with no duplicate
      and no gap — checked on a real device.
- [ ] Landing on Команда before the hub has connected shows a loading state and then the room, never
      a crash and never an error.
- [ ] Every hub call sends its method's full argument list.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
