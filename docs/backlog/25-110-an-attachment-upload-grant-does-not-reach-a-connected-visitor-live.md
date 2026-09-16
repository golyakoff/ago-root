# 25-110 · An attachment-upload grant does not reach a connected visitor live

- **Stage**: 25
- **Depends on**: nothing
- **Status**: done — `ago-chat#314`, `ago-widget#89`. Built in a background-worker session, resumed
  once mid-task after it stopped waiting on its own background test run, then independently
  re-verified by the managing session (its own `dotnet build`/`test`/`npm` runs against the worker's
  own worktrees, matching counts exactly) before merging.
- **Found**: 2026-09-16, the author testing 23-78's per-conversation toggle live on a real tenant: an
  operator ticks "разрешаю пользователю отправлять файлы" and the visitor's own widget, held open the
  whole time, does not show the attach icon until the page is reloaded - unlike an operator's ordinary
  reply text, which the same visitor sees arrive with no reload at all.

## What is actually true today

This is not a surprise regression - `ago-widget`'s own `connection.ts` already documents it as an
accepted trade-off, made when `23-78` shipped:

> This is *not* a live push from the server the moment an operator toggles the grant mid-session -
> there still is none, the same gap this widget already accepts for a block/unblock. It is a
> free-of-extra-cost refresh riding a network event (an automatic reconnect) this connection was
> already going to make for an unrelated reason... a visitor whose connection drops and recovers, or
> whose laptop sleeps and wakes, sees the icon catch up to the operator's latest decision without a
> full page reload; one who stays connected the whole time still does not, until this method's own
> `onreconnected` fires or the page is reloaded.

Confirmed on the server side too: `GrantAttachmentUploadHandler`/`RevokeAttachmentUploadHandler`
(`Ago.Chat.Application`) write the grant through `IConversationAttachmentUploadGrantRepository`'s own
raw-SQL bypass (the same xmin-avoidance shape `BlockConversationHandler` uses) and enqueue **no
outbox event at all** - nothing for anything to fan out. Compare `CloseConversationHandler`, which
enqueues `ConversationClosed` through the same `IOutboxWriter` every other conversation-state change
in this codebase uses to reach a live connection.

## Scope

- `GrantAttachmentUploadHandler`/`RevokeAttachmentUploadHandler` each enqueue an integration event
  through `IOutboxWriter` when the grant actually changes (not on `AlreadyInState` - nothing changed,
  nothing to tell anyone).
- A consumer resolves the event to the one visitor connection holding that conversation open and pushes
  it live - reuse `Ago.Platform.Realtime`'s own per-node delivery primitive
  (`NodeDeliveryConsumer`/`NodeFanoutPublisher`, the same one `ConnectionFanoutConsumer` sits on top of
  for `MessageAccepted`) rather than inventing a second delivery mechanism. This is not a chat message,
  so it does not need `ResolveMessageDeliveryTargetsHandler`'s own participant-resolution logic - the
  one connection to reach is already named by `ConversationId`.
- `ago-widget`'s `connection.ts` gains a real hub client method (a `.on("AttachmentUploadGrantChanged",
  ...)` alongside the existing `MessageReceived`/`Reconnect`), and `onAttachmentUploadGrantChange`'s own
  listener fires from it directly - the reconnect-riding fallback stays as a backstop for the case a
  push is missed (a reconnect happening at the same moment, a dropped delivery), not removed.
- A visitor holding the conversation open the whole time sees the attach icon appear or disappear
  within a normal message-delivery latency of the operator's own click - no reload, no reconnect
  needed.

## Where this is likely to go wrong

- **`GrantAttachmentUploadHandler`/`RevokeAttachmentUploadHandler` never call
  `IConversationRepository.SaveAsync`** (the read-only-for-the-permission-check shape their own doc
  comments state) - the new outbox enqueue needs a real transaction of its own (`IUnitOfWork`, the same
  seam `RecordUnreadMessageHandler` uses for its own atomic-update-plus-outbox-row shape) rather than
  assuming an ambient `SaveChangesAsync` will carry it, since there no longer is one.
- **Both handlers live in `Ago.Chat.Api`** (an operator's own HTTP call) - CLAUDE.md rule 4 forbids
  publishing directly from a request handler, so this must go through the outbox and a Worker consumer
  like every other cross-process notification in this codebase, not a same-process shortcut.
- **The identical gap exists for block/unblock** (`connection.ts`'s own comment names it explicitly).
  Out of scope here on purpose - one ticket, one thing. If the fix below produces a reusable shape (a
  generic "push this conversation-scoped fact to its one live visitor connection" primitive rather than
  something attachment-grant-specific), name that in the report; a sibling item for block/unblock can
  reuse it rather than rebuilding it, but building it here would be solving a problem nobody asked this
  item to solve yet.
- **Revoke matters as much as grant.** A visitor mid-upload (or about to start one) when an operator
  revokes should lose the icon live too, not just gain it - test both directions.
- **A dropped connection mid-push** should not lose the fact permanently: the existing reconnect-riding
  read (`onreconnected` re-running `JoinAsync`) is the correct backstop and must keep working exactly
  as it does today, so a missed live push still self-heals on the visitor's own next reconnect.

## Done when

- [x] `GrantAttachmentUploadHandler`/`RevokeAttachmentUploadHandler` enqueue an outbox event when (and
      only when) the grant state actually changes. — only on `Applied`, never `AlreadyInState`/`NotFound`.
- [x] A Worker consumer delivers that event live to the one visitor connection holding the affected
      conversation, reusing the platform's existing per-node delivery primitive rather than a new one. —
      `AttachmentUploadGrantFanoutConsumer` sits on the existing `NodeFanoutPublisher`/`NodeDeliveryConsumer`.
- [x] `ago-widget` reacts to the pushed event immediately - a fails-before test proving a visitor whose
      connection never drops still sees the icon change with no reload, for both grant and revoke. —
      `connection.test.ts`'s new cases, and the real-infrastructure proof below.
- [x] The existing reconnect-riding fallback (`onAttachmentUploadGrantChange`'s current behaviour)
      still works unchanged - a dropped-and-recovered connection still catches up correctly. — kept
      verbatim as the backstop; its own test still passes.
- [x] Real end-to-end proof, not just unit-level: real Postgres, real RabbitMQ, real SignalR connection
      held open across the operator's own grant/revoke call (matching this codebase's own
      `WidgetConfigCacheInvalidationEndToEndTests`-style real-infrastructure discipline for a
      live-propagation claim).
