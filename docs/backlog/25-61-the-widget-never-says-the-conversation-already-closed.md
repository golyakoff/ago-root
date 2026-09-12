# 25-61 · The widget never says the conversation already closed

- **Stage**: 25
- **Status**: ready — **blocked on a small `ago-chat` addition, not filed yet**. Investigated in
  `ago-widget-25-61` (`fix/25-61-widget-never-says-conversation-already-closed`); no widget-side code
  changed. See Investigation below for exactly what `ago-chat` needs to expose before this item's
  Done-when can be met honestly rather than by guessing at a wording match.
- **Depends on**: nothing
- **Found**: 2026-09-12, `feedback.md`

## What is actually true

After a conversation's hold-timeout expires and it closes, a visitor who still has the widget open
and tries to send another message sees the generic "Не удалось отправить." — indistinguishable from
a real network/server failure. The visitor has no way to know the actual reason is that the
conversation itself already ended.

## Scope

- When a send fails specifically because the conversation is closed (not a genuine network/server
  failure), show the visitor a distinct message saying so — the conversation has ended, rather than
  the generic send-failure note.
- If the widget can detect the closure proactively (e.g., a real-time signal it already receives)
  rather than only failing on the next send attempt, prefer surfacing it at the moment of closure —
  but at minimum, the send-failure path must distinguish "closed" from "actually failed to send."

## Where this is likely to go wrong

- **Don't collapse this into the same generic error path it's replacing.** The whole point is telling
  these two failure reasons apart; reusing one catch-all message for both would leave the bug in place
  under a different label.

## Investigation (2026-09-12)

Traced both the reactive path (widget sends into an already-closed conversation) and the proactive
path (widget already connected when the conversation closes server-side). **Neither carries a
distinguishable signal today** — this is a genuine two-repo item, not a widget-only fix.

**Reactive path.** `VisitorConnection.sendMessage` (`ago-widget/src/connection.ts`) invokes
`SendMessageAsync`/`SendStructuredMessageAsync`/`SendMessageWithAutoGreetingAsync` on `VisitorHub`.
Server-side, `SendVisitorMessageHandler` → `MessageBatchWriter` calls `Conversation.AddVisitorMessage`,
which throws `InvalidConversationStateException` for exactly one reason (the closed-conversation
check — the only other throw in that method is a participant mismatch, mapped separately to
`Conversation.Forbidden`). `MessageBatchWriter` catches it and resolves the send's `Result` with
`ConversationErrors.InvalidState(ex.Message)` — code `"Conversation.InvalidState"`. **That code never
reaches the client.** `VisitorHub.SendAsync` throws it onward as `throw new
HubException(sent.Error!.Value.Message)` — the free-text message only; `Error.Code` is dropped. SignalR
delivers that message string to the widget's `catch` in `sendMessage`, indistinguishable there from
every other hub-side rejection (rate-limited, invalid body, etc.) — all of them currently fall into
`ui/widget.ts`'s `completeSend` "else" branch and render the same generic `sendFailedNote`.
`AddSignalR(...).EnableDetailedErrors` is only true in Development (`Ago.Chat.Api/Program.cs`), and
even then it adds the .NET exception's own detail, never `Error.Code` — so there is no configuration
that already exposes it in production.

**This exact gap is already on record on the other side of this same codebase.** `ago-console`'s
`strings.ts` (`conversationOpenFailed`) states it in so many words: *"`HubException` carries only a
string, no error code (`ConversationsEndpoints.cs`'s REST calls get RFC 7807 `type`s; `OperatorHub`'s
hub methods do not), and guessing from that string's wording would be more likely to mislead than one
honest sentence."* `ConversationsEndpoints.cs` makes the same point from the other direction: it chose
REST over a hub method specifically so a failure could carry a real RFC 7807 `type`. Matching on
`AddVisitorMessage`'s exact English wording (`"Cannot add a message to closed conversation {id}."`) in
the widget would work today but is exactly the workaround this item's own brief warns against
inferring from an ambiguous signal — a future reword or localisation of that message in `ago-chat`
would silently break detection with nothing in `ago-widget`'s own test suite able to catch it, across
a repository boundary.

**Proactive path.** Checked whether the widget already receives anything it could use instead: it does
not. `VisitorJoinResult` (`Ago.Chat.Contracts`) carries `ConversationId`, `IsNew`, `History`,
`HasAttachmentUploadGrant` — no state/closed flag. Closing a conversation (`CloseConversationHandler`,
`AutoCloseConversationHandler`) raises the domain event `ConversationClosed`, mapped to the outbox
contract `ConversationEnded` — but that only feeds `Ago.Chat.Webhooks`' dispatcher (the tenant's own
webhook integration). Nothing pushes a hub event to the visitor's own SignalR connection when their
conversation closes, and no system message is appended to the conversation history either. The widget's
`VisitorConnection` only listens for `MessageReceived` and the informational `Reconnect` hint — there is
no third event to subscribe to yet.

**What `ago-chat` would need to add** (either is sufficient for the reactive Done-when; the second is
needed for the "prefer proactive" stretch goal):

1. A stable, wire-visible code for this one rejection reaching `VisitorHub`'s callers — e.g. `SendAsync`
   throwing something a client can branch on structurally rather than by wording (a `HubException`
   whose message is a small structured/prefixed token, or a second, typed exception the widget's own
   SignalR client can distinguish) — scoped to the `Conversation.InvalidState` code specifically, since
   on the visitor-send path that code is unambiguously "this conversation is closed" (confirmed above:
   `AddVisitorMessage` has no other state check).
2. A live push to the visitor's own connection when their conversation closes (a new
   `VisitorHub`/`SignalRConnectionDispatcher` message, mirroring `ConversationEnded`'s own outbox
   consumer but targeting the visitor's connection instead of a webhook), so the widget can show the
   ended-conversation state at the moment it happens rather than only on the visitor's next send
   attempt.

Filing this as its own numbered `ago-chat` item is the coordinator's call, per this task's own
instructions — not done here.

## Done when

- [ ] A visitor who tries to send into a conversation that has already closed sees a message saying
      the conversation ended, not the generic "не удалось отправить" note.
- [ ] A genuine send failure (real network/server problem) still shows its own, correctly distinct
      message.
