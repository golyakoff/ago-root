# 25-61 · The widget never says the conversation already closed

- **Stage**: 25
- **Status**: done — `ago-chat#258`, `ago-widget#80`
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

## Outcome (`ago-chat`, 2026-09-12)

Built the investigation's own "option 1" - the reactive minimum this item's Done-when actually
requires. Not built: option 2 (a live push to the visitor's connection at close time) - it needs a
new outbox consumer and a new hub-push mechanism that do not exist today, which is genuinely new
infrastructure, not the "genuinely cheap" stretch this task was scoped to attempt only if free. Left
for a future item if the proactive stretch is ever wanted; the reactive signal below already satisfies
both Done-when boxes.

**The wire shape `ago-widget-25-61` needs to read**, exactly:

`VisitorHub.SendAsync` (`Ago.Chat.Api/Hubs/VisitorHub.cs`, the private method every one of
`SendMessageAsync`/`SendMessageWithAutoGreetingAsync`/`SendStructuredMessageAsync` delegates to) now
special-cases exactly one error code on the failure branch that used to rethrow every rejection as
bare free text:

```csharp
throw error.Code == "Conversation.InvalidState"
    ? new HubException(ConversationClosedHubErrorPrefix + error.Message)  // "Conversation.InvalidState: " + <English sentence>
    : new HubException(error.Message);                                    // unchanged - every other rejection
```

- The prefix is the literal string **`"Conversation.InvalidState: "`** (with the trailing space),
  published as `VisitorHub.ConversationClosedHubErrorPrefix` (`internal`, but `Ago.Chat.Api` already
  grants `InternalsVisibleTo("Ago.Chat.Integration.Tests")` - not visible to `ago-widget`, which is a
  different language/repo anyway; that repo hardcodes the literal, the same way it already hardcodes
  hub method names).
- On the widget side, the check is a plain `string.startsWith` on the caught error's `.message` -
  `ui/widget.ts`'s `completeSend`, the `else` branch at its `.catch` (around line 1274-1285 as of this
  writing): today it picks between `notConnectedRetryNote` and `sendFailedNote`; the fix adds a third
  branch checked first - `error instanceof Error && error.message.startsWith("Conversation.InvalidState: ")`
  → a new, distinct "this conversation has ended" string, never `sendFailedNote`.
- Everything after the prefix is `Conversation.AddVisitorMessage`'s own English sentence
  (`"Cannot add a message to closed conversation {id}."`) - present for a human reading logs, but the
  widget must never match on it; the prefix is the only stable part.
- Scope is exactly this one rejection on exactly this one hub method. Every other failure on
  `VisitorHub` (rate limits, a malformed body, a participant mismatch, a stale attachment) and every
  rejection on `OperatorHub` still arrives as the unprefixed free-text message, unchanged - this is not
  a general "hub errors now carry codes" mechanism, deliberately, per this task's own scoping.

**Why this shape, not the alternatives considered**: a hub method has no RFC 7807 `type` field the way
a REST endpoint's `ErrorExtensions.ToProblem` does (`ConversationsEndpoints.cs`'s own reasoning for
preferring REST specifically so a failure can carry one) - `HubException` carries one string, and
that string is the only channel available. Rather than invent a second error-code vocabulary just for
this one hub method, the prefix reuses the *same* stable code (`Error.Code`, `"Conversation.InvalidState"`)
`ErrorExtensions.ToProblem` already surfaces as this identical error's REST `type` - one vocabulary,
a second transport for one value out of it. A second, typed exception type was considered and rejected:
SignalR's own client always delivers a `HubException` (or, off the SignalR client's happy path, a
plain `Error`) to `.invoke()`'s rejection, so a second .NET exception type would still collapse to the
same one string on the wire - no cheaper than a prefix, and it would need its own new "how do I
serialize a second exception shape over SignalR" answer this codebase has never needed before.

**Verified real, not asserted**: `Ago.Chat.Integration.Tests/VisitorSendIntoClosedConversationTests.cs`
closes a real conversation (`Conversation.Close`, real Postgres), sends into it through the real,
unmodified `VisitorHub.SendMessageAsync` (real `SendVisitorMessageHandler`, real `MessageBatchWriter`),
and asserts the thrown `HubException.Message` carries the prefix. Fails-before was run for real: with
the fix reverted, the assertion failed against the bare English sentence, confirming the test can
catch the exact defect it exists to prevent; the revert was never committed. A second fact
(`SendMessageAsync_ByAVisitorWhoIsNotThisConversationsOwnVisitor_ThrowsAPlainHubExceptionWithNoPrefix`)
proves the sibling rejection (`Conversation.Forbidden`, a participant mismatch) does *not* pick up the
same prefix - this item's own "don't collapse this into the same generic error path" warning, checked
against the new branch itself.

## Outcome (`ago-widget`, 2026-09-12)

Consumed the wire shape above exactly as specified. `ui/widget.ts`'s `ChatWidget.completeSend`, the
same `.catch` branch the Outcome above names, gained a third check ahead of the existing
`NotConnectedError`/generic split: `error instanceof Error && error.message.startsWith("Conversation.InvalidState: ")`
→ a new `conversationEndedNote` string (en/ru), added to `WidgetStrings` alongside the existing
`*Note` fields it's worded to match (`"Not sent - this conversation has ended."` /
`"Не отправлено — диалог завершён."`) rather than `sendFailedNote`'s bare "Failed to send." — the two
existing branches are otherwise untouched. The prefix is hardcoded as a literal in `widget.ts`, never
referencing `VisitorHub.ConversationClosedHubErrorPrefix` directly (different language, different
repository, and `internal` there anyway).

Two new tests in `widget.test.ts`: one drives the exact rejection shape above and asserts
`conversationEndedNote` renders, never `sendFailedNote`; a sibling drives an ordinary, unrelated
`Error` and asserts the *old* `sendFailedNote` behavior is unchanged — the regression guard proving
the new check didn't widen past the one prefix it's meant to catch. Both shown failing against the
change stashed out, passing with it restored.

Verified independently by the managing session: `npm run typecheck`/`lint` clean, `npm test` 35 files /
361 tests (361, matching the worker's own count exactly), `npm run build` 34.4 KB gzipped against the
45 KB budget (10.6 KB headroom left after this and `25-46`'s icon work).

## Done when

- [x] A visitor who tries to send into a conversation that has already closed sees a message saying
      the conversation ended, not the generic "не удалось отправить" note.
- [x] A genuine send failure (real network/server problem) still shows its own, correctly distinct
      message.
