# 25-117 · The operator disconnect grace period was too tight for real use

- **Stage**: 25
- **Depends on**: nothing
- **Status**: ready — config written, not yet applied live.
- **Found**: 2026-09-17, the author's own live use of the console after `25-115`/`25-116`.

## What this item covers, and what it does not

Originally scoped as two separate timeout widenings. The second one - extending
`AutoCloseInactiveConversationsJob.WidgetInactivityWindow` so a widget visitor's *conversation* stays
resumable as long as their *identity* does - was pulled back out mid-investigation, at the author's own
objection: "бизнесово это разные вещи - 'помнить клиента' и 'держать оператора в состоянии
загруженности'" (these are different business concerns - "remembering the client" and "keeping the
operator's load down"). Widening that single shared window conflates the two, and `Conversation.Close`
releasing operator capacity only at that same window means a longer window directly narrows how many
concurrent conversations an operator can be given. That half is refiled as its own item, `25-118`,
once investigation found the real fix is not a timeout at all - see that item for why.

**This item covers only the first, genuinely independent fix**: `OperatorDisconnectGraceConsumer`'s
`GracePeriod`.

## What is actually true today

The author's own browser tab went idle long enough for its SignalR connection to the operator hub to
drop, and the 30-second default (`4-04`'s own doc comment already calls it "a starting point, not
measured or load-tested") was not enough slack for an ordinary reconnect - every conversation assigned
to that operator was released back to `Waiting` (`OperatorConversationReleaser.ReleaseAllAsync`), with
no other operator online to pick them up. The console then correctly, if confusingly, reported "This
operator is not assigned to this conversation" for a conversation the author had been actively working
a few minutes earlier.

## Fix

`OperatorDisconnectGraceConsumer__GracePeriod`: `00:00:30` → `00:03:00`, deployment configuration only,
no code change - the option was already bound from configuration.

## Where this is likely to go wrong

- **Still not a measurement.** Both the old and new figures are "starting point" defaults - CLAUDE.md's
  "measure or stay silent" applies to any future claim about *why* three minutes specifically is
  correct, not just the original thirty seconds.
- **A genuinely disconnected operator (not just an idle tab) still releases after three minutes, not
  never** - this widens the window, it does not remove the mechanism `4-04` built it for.

## Done when

- [ ] A browser tab idle long enough to drop its SignalR connection, then reconnecting within 3
      minutes, does not release the operator's conversations.
- [ ] The change is deployment configuration only - no code change.
