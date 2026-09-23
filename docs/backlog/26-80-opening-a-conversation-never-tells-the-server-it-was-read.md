# 26-80 · Opening a conversation never tells the server it was read

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, by the author, asking a plain question — "по какому принципу рисуются цифры в
  синих кружочках рядом с диалогами?" — while looking at the real app.

## What is actually true today, confirmed against real code

`Conversation.cs` (`ago-chat`) is unambiguous about the two halves of this counter:

- **`IncrementUnreadCount`** (`:813-828`): every visitor message (and system auto-reply,
  `MessageAuthorKind.System` included on purpose per `14-04`'s own remarks) adds `+1` to
  `OperatorUnreadCount`. An operator's own message never touches it.
- **`MarkReadByOperator`** (`:871-897`): the *only* thing that ever lowers it. Clears up to a
  `upToSequence` watermark, not to zero — deliberately, so a visitor message arriving in the same
  instant as the read is still counted rather than silently swallowed by a load-reset-save race
  (`5-15`'s own reasoning, quoted in full in the method's doc comment).

**Nothing in `ago-android` ever calls the endpoint behind `MarkReadByOperator`.** Grepped the whole
app — `core/domain`, `core/network`, `app` — for `markRead`/`MarkRead`: the only hit is a stray doc
comment in `OperatorHubEvents.kt` that *mentions* `ago-console`'s own `markRead` in passing while
explaining something else. There is no method on the Android `ConversationsApi` port, no call from
`ThreadViewModel`, nothing.

**Consequence, confirmed by reading `ConversationListViewModel.onRowOpened`**: opening a thread on
Android only clears the local `isNewlyAssigned` flag (the «Новое» pill). The unread badge itself
(`operatorUnreadCount`, fetched from the server) is never told the operator read anything, so it never
goes down inside this app — an operator can read every message in a conversation and its badge stays
exactly where it was until a *different* mechanism (another client, or nothing at all) happens to lower
it server-side.

## The reference implementation already exists — `ago-console`

`ConversationPage.tsx:466-497` is the exact behavior to port:

- **The read position is "the newest message actually rendered", not the server's own `lastSequence`
  from the queue row** — the console's own doc comment states why: the server value can already be
  ahead of what is on screen, and claiming it would mute a message the operator never saw. The console
  can treat "newest loaded" and "newest on screen" as the same fact only because `Thread` auto-scrolls
  to the bottom on open — confirm `ago-android`'s own `ThreadScreen` does the identical thing before
  reusing this exact reasoning; if it does not always land at the bottom, the read position has to be
  computed differently.
- **Fires on open, and again (debounced) while the conversation stays on screen and new messages
  arrive** — a `useEffect` keyed on `conversationId`/`newestSequence`/tab-visibility, guarded against
  re-sending a watermark already sent (`lastMarked` ref).
- **`POST /api/v1/conversations/{id}/read` with `{ upToSequence }`** (`conversationsApi.ts:115-134`) —
  REST, not the hub, even though a live connection is already open; that function's own doc comment
  states why (real status codes for `403`/`409`, and this is nowhere near hot enough to need the hub).
- **Fire-and-forget.** A failed mark-read is swallowed (`console.warn` on the console's side) rather
  than shown to the operator — reading is not an action the operator is waiting on confirmation for,
  and retrying automatically would just be the next natural mark-read call anyway.

## Scope

One promise: **opening a conversation in the Android app, and staying on it while new messages arrive,
tells the server what was actually read — the same way `ago-console` already does.**

1. Add the mark-read call to the Android `ConversationsApi` port (`core/domain`) and its Ktor
   implementation (`core/network`), calling the same `POST /api/v1/conversations/{id}/read` endpoint
   with `{ upToSequence }` — no backend change, the endpoint already exists and already serves the
   console.
2. Wire it from `ThreadViewModel`/`ThreadScreen`: on opening a conversation and on the newest-loaded
   message changing while the screen is visible, call mark-read with that message's own sequence —
   port the console's "newest rendered, not the server's own claimed sequence" reasoning, after
   confirming `ThreadScreen` really does always auto-scroll to the newest message on open (state this
   explicitly in the report either way).
3. Debounce and de-duplicate the same way the console does (a `lastMarked`-shaped guard) — this is a
   real network call, not a local state update, and firing it on every recomposition would be wrong.
4. Fire-and-forget: a failed mark-read is logged/ignored, never shown to the operator as an error.
5. Confirm the row's own `unreadCount` (`ConversationListViewModel.toRowUi`) actually reflects the
   server's lowered `operatorUnreadCount` on the next `refresh()` — it already reads that field
   correctly; this item only has to make the field itself change server-side.

## Out of scope

- `VisitorUnreadCount`/a widget-side read receipt — `MarkReadByOperator`'s own doc comment states this
  is deliberately one-sided; nothing here touches the visitor half.
- Any change to the backend endpoint itself — it already exists, already serves the console, and this
  item is a pure Android-client gap.
- Team chat's own unread mechanism (`TeamChatUnreadContext.tsx`'s own comment notes it has no mark-read
  call of its own either, on the console side) — a separate surface, not this item's promise.

## Done when

- [ ] Opening a conversation on a real device, reading its messages, then returning to «Мои» shows the
      badge lowered (or gone) without restarting the app or waiting for an unrelated refresh.
- [ ] A new visitor message arriving while the conversation is already open and read gets counted
      correctly once it is itself read (i.e., the watermark-based clear, not a zero-reset, is
      preserved end to end) — unit tested against the same race `MarkReadByOperator`'s own doc comment
      describes, not just the happy path.
- [ ] The mark-read call is debounced/de-duplicated — a test proves it is not re-sent for a sequence
      already confirmed sent.
- [ ] A failed mark-read call does not surface any error UI to the operator.
- [ ] `./gradlew ktlintCheck lint test assembleDebug assembleDebugAndroidTest` green.
