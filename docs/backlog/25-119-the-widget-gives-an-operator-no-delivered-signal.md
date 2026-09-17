# 25-119 · The widget gives an operator no "delivered" signal

- **Stage**: 25
- **Depends on**: nothing
- **Status**: ready — design decided, dispatched for implementation.
- **Found**: 2026-09-17, the author comparing the console's own existing "Доставлено"/"Не доставлено"
  badge (shown on an operator's own message in a Telegram/MAX conversation) against the widget, which
  shows nothing at all for the identical case.

## What is actually true today

`ChannelDelivery` (`23-19`) already gives every channel-kind conversation (Telegram/MAX/etc.) a real
delivery signal: `DeliverChannelMessageHandler` records whether the provider's own API accepted an
operator's outbound message, and `Thread.tsx` renders a `Badge` from it, keyed by `messageId`.

**This mechanism structurally cannot cover the widget, and was never meant to** - `ChannelDelivery`
requires a `ChannelIdentityId`/`ChannelKind`, and `14-01`'s own domain model states a widget visitor
never has a `ChannelIdentity` row, exactly the same boundary `25-118`'s own investigation found already
excludes widget visitors from `GetVisitorHistoryHandler`. The widget's own delivery path
(`ConnectionFanoutConsumer` → `Ago.Platform.Realtime`'s fan-out → `VisitorHub`'s `SendAsync("MessageReceived", ...)`)
is, today, pure fire-and-forget: the server confirms the SignalR framework accepted the write to the
transport, never that the visitor's browser actually received or processed it. There is no ack loop at
all, in either direction.

## Answered - the design

**"Delivered" for the widget means the visitor's own live connection actually received the push, not
merely that the server attempted one** - a genuinely stronger, more honest signal than
`ChannelDelivery.Delivered` (which only ever meant "the provider's API accepted the send," never
"the recipient's device got it" - Telegram's own Bot API gives bots no read/delivery receipt at all).
Getting it needs a real ack round trip, modelled closely on `25-110`'s own single-recipient live-push
shape (`AttachmentUploadGrantChanged`/`AttachmentUploadGrantFanoutConsumer`) rather than invented fresh:

1. **`Message` gains `DateTimeOffset? DeliveredAt`** (a new nullable column, additive migration) - not
   a new `ChannelDelivery`-shaped side table, because delivery is a fact about the message itself, and
   `ChannelDelivery`'s own required `ChannelIdentityId`/`ChannelKind` fields do not fit a widget visitor
   by construction (the same reason `25-118` did not try to reuse `GetVisitorHistoryHandler`'s
   `ChannelIdentity` gate for a widget visitor). Scoped, like the console's existing badge, to an
   **operator-authored** message only - a visitor's own message has no equivalent "did the operator see
   it" concept this item is asked to build.
2. **A new `VisitorHub` method, `AcknowledgeDeliveredAsync(Guid conversationId, Guid messageId)`** -
   the widget calls it once its own `MessageReceived` handler (`connection.ts`) has processed an
   incoming operator message. Authorises the same way every other `VisitorHub` method does
   (`Context.User!.GetVisitorId()`), and refuses (or silently no-ops - the item's own implementer
   should decide and say which, matching this codebase's existing precedent for a client raising an id
   it does not own) a `messageId` that does not belong to a conversation this visitor owns.
3. **A new integration event, `MessageDelivered`, and a new fan-out consumer** -
   `MessageDeliveredFanoutConsumer`, the exact shape `AttachmentUploadGrantFanoutConsumer` already is:
   resolves the one operator to notify (the message's own author, read directly off the aggregate - no
   query needed, unlike `ResolveMessageDeliveryTargetsHandler`'s own participant-resolution case) and
   pushes a live update to that operator's own connection(s) via the platform's existing per-principal
   fan-out (`Ago.Platform.Realtime`), so the badge appears live in the console without a reload -
   matching the "backstop is the next page load, not the only path" reasoning `25-110`'s own consumer
   doc comment already gives.
4. **`MessageDto` (the shape `GetConversationHistory` already returns to both operator and visitor
   callers) gains `deliveredAt: string | null`** - the same field, on the same read, every conversation
   kind already uses; no second endpoint, no second round trip, matching `channelDeliveries`'s own
   separate-endpoint shape only because that one is keyed to a structurally different concept
   (`ChannelIdentity`) this item's own signal does not have.
5. **`ago-widget`'s `connection.ts`** calls the new hub method from inside `handleIncoming`, fire-and-
   forget, no idempotency ledger needed (`adr/0020`'s reasoning already covers a duplicate ack: a
   redelivered ack against an already-`DeliveredAt`-set message is a harmless no-op).
6. **`ago-console`'s `Thread.tsx`** renders the identical `Badge tone="success"` /
   `strings.threadDeliveryDeliveredBadge` the channel-kind case already uses, sourced from
   `message.deliveredAt` for a widget conversation instead of the `channelDeliveries` map, and listens
   for the new live push the same way it already listens for other live conversation events.

## Where this is likely to go wrong

- **Do not reuse `ChannelDelivery` or widen its required fields to allow a null `ChannelIdentityId`** -
  that type's own remarks state plainly why the reference shape it chose depends on a real
  `ChannelIdentity` existing; forcing a widget-shaped exception into it is the same anti-pattern
  `25-118` avoided by writing a second, smaller handler instead of widening `AutoCloseConversationHandler`'s
  own guard past what it actually needed.
- **This is a real ack round trip, not a registry check.** Checking `IConnectionRegistry` for "is this
  visitor currently connected" at push time is a weaker, different claim ("we believe a connection
  exists") than "this specific message actually reached that connection's own JS runtime" - do not
  substitute the cheaper check for the real one.
- **Scope the badge to operator-authored messages only**, matching the channel-kind precedent exactly -
  a visitor's own message showing a "delivered to the operator" badge is a different feature nobody
  asked for here.
- **This is the migration lane's own item while it is in flight** - confirm no other `ago-chat`
  migration is open before starting (checked clear 2026-09-17: no open PRs, no migration since `25-115`).

## Done when

- [ ] An operator's message to a widget visitor shows no badge until the visitor's own live connection
      has actually received it, then shows the identical "Доставлено" badge Telegram/MAX conversations
      already show - live, without a reload, when the operator is still looking at the conversation.
- [ ] A visitor reconnecting later (their own client never having acked) still sees the message; a late
      ack still sets `DeliveredAt` and still updates the console if the operator is now looking.
- [ ] Channel-kind delivery (`ChannelDelivery`, `Thread.tsx`'s existing badge) is provably unchanged.
- [ ] The new migration is additive/reversible, and this remains the only migration in flight in
      `ago-chat` for its own duration.
