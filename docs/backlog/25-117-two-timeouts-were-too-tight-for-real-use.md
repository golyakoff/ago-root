# 25-117 · Two timeouts were too tight for real use

- **Stage**: 25
- **Depends on**: nothing
- **Status**: ready — config written, not yet applied live.
- **Found**: 2026-09-17, the author's own live use of the console and widget after `25-115`/`25-116`.

## What was actually true

**`OperatorDisconnectGraceConsumer.GracePeriod` (30s default, `4-04`):** the author's own browser tab
went idle long enough for its SignalR connection to the operator hub to drop, and 30 seconds was not
enough slack for an ordinary reconnect - every conversation assigned to that operator was released
back to `Waiting` (`OperatorConversationReleaser.ReleaseAllAsync`), with no other operator online to
pick them up. The console then correctly, if confusingly, reported "This operator is not assigned to
this conversation" for a conversation the author had been actively working a few minutes earlier. This
value's own doc comment already named it "a starting point, not measured or load-tested."

**`AutoCloseInactiveConversationsJob.WidgetInactivityWindow` (1 hour default, `18-06`):** comparing
against Jivo's widget (embedded on `golyakov.net` for this comparison), the author found AGO's widget
conversation itself is not resumable nearly as long as the visitor's own identity is. Investigation
found the two are governed by two entirely different, and very differently sized, mechanisms:
`JwtTokenService.VisitorTokenLifetime` (7 days, auto-renewing on return - `storage.ts`'s own disclosure
already documents the widget as designed for exactly this) keeps a returning visitor's *identity*
alive effectively indefinitely, but the *conversation* itself auto-closes after just one hour of no
message either direction (`18-06`'s own stated reasoning: "a widget session has no return-visitor
value once the tab is gone" - true for the capacity question that item was scoped to, not for the
product goal the author actually wants).

## Fix

Both are deployment-configured `TimeSpan` values, changed via `ago-deploy` only - no code change in
either case, both options were already bound from configuration.

- `OperatorDisconnectGraceConsumer__GracePeriod`: `00:00:30` → `00:03:00`.
- `AutoCloseInactiveConversationsJob__WidgetInactivityWindow`: `01:00:00` → `7.00:00:00` - matched to
  `VisitorTokenLifetime`'s own 7 days, the author's explicit choice over a shorter 24-hour alternative
  (which would have matched a real channel conversation's own default window instead).

## Where this is likely to go wrong

- **The widget window's own real cost, stated because `AutoCloseConversationHandler`'s own comment
  already names it plainly**: an *assigned* operator's capacity slot stays consumed by an abandoned
  widget conversation until this job actually closes it - `Conversation.Close`'s capacity release only
  fires there. Widening the window from 1 hour to 7 days means an abandoned-but-assigned conversation
  can hold that slot for up to a week instead of an hour, narrowing how many concurrent conversations
  that operator can otherwise be given. Accepted here as the explicit trade-off for Jivo-style long
  resumability, not an oversight - worth revisiting if operator capacity ever becomes the tighter
  constraint in practice, and the per-kind override (`ChannelInactivityWindows`) already gives a way
  to walk this back for the widget specifically without touching the channel defaults.
- **Neither number is a measurement.** Both were "starting point" defaults before this item and are
  now different, still-unmeasured numbers - CLAUDE.md's "measure or stay silent" applies to any future
  claim about *why* these specific figures are correct, not just the originals.

## Done when

- [ ] A browser tab idle long enough to drop its SignalR connection, then reconnecting within 3
      minutes, does not release the operator's conversations.
- [ ] A widget conversation with no messages for up to 7 days remains resumable (not auto-closed)
      when the visitor returns.
- [x] Both changes are deployment configuration only - no code change.
