# 25-118 · A returning widget visitor cannot see their own past conversation

- **Stage**: 25
- **Depends on**: nothing
- **Status**: ready — design decided (see "Answered" below), dispatched for implementation.
- **Found**: 2026-09-17, split out of `25-117`: the author compared AGO's widget against Jivo's
  (embedded on `golyakov.net` for the comparison) and asked for widget conversations to stay resumable
  as long as a visitor's own identity does (7 days). Investigation found this needs a real, currently
  entirely missing mechanism - not a wider `AutoCloseInactiveConversationsJob.WidgetInactivityWindow`,
  which the author correctly rejected as conflating two separate business concerns: "remembering the
  client" and "keeping the operator's load down."

## What is actually true today

**A widget conversation always starts over from zero, with no visible history, the moment the
previous one auto-closes** - `StartConversationHandler.HandleAsync` only ever resumes a conversation
found by `IConversationRepository.GetActiveForVisitorAsync` (an *open* one); once
`AutoCloseInactiveConversationsJob` closes it, that read returns nothing and a genuinely new
`Conversation` row is created, with a new id the widget's own `conversation-id` (`storage.ts`) then
overwrites in place. Nothing carries the old conversation's messages forward into the new one.

**The one mechanism that reads a visitor's own past conversations already exists, and it structurally
cannot serve a widget visitor.** `GetVisitorHistoryHandler` (`18-06`/`18-07`) is an *operator-facing*
"has this person talked to us before" panel, gated in two ways that both exclude a widget visitor by
construction:
- It requires `Permission.ConversationRead` on the *requesting operator* - there is no equivalent
  grant for the visitor themselves to read their own history.
- It short-circuits entirely on `IChannelIdentityRepository.FindMostRecentForVisitorAsync` returning
  `null` - and `14-01`'s own domain model states a widget visitor **never** has a `ChannelIdentity` row
  ("identified by a signed token this system issued to a browser... not by an identifier some external
  provider owns"). `HasChannelIdentity: false` is not a bug here, it is the documented, permanent
  answer for every widget visitor there has ever been or will be.

The API route itself says as much: `ConversationsEndpoints.cs`'s own comment on
`GET .../{conversationId}/visitor-history` states plainly "there is nothing here for a visitor caller
to ask for."

**The widget's own `storage.ts` disclosure describes something narrower than cross-conversation
memory**, worth naming so this item is not mistaken for re-fixing something already working: its
`last-sequence:<conversationId>` entry and `23-53`'s own note ("a plain reload... always asks for the
visitor's own history page, so reopening the widget never comes back empty") are about fetching the
*current, still-open* conversation's own full transcript on reload - not about surfacing a *previous,
already-closed* conversation's messages once a new one has started. The two look similar from the
outside (both mean "the widget doesn't come back empty") and are not the same mechanism.

## Why this is a real design question, not a quick fix

The three obvious shapes, none of them free:

1. **Widen the auto-close window itself** (what `25-117` originally tried). Rejected: conflates
   "remember the client" with "keep the operator's capacity turning over" - the two are different
   business questions with different right answers, and `Conversation.Close`'s capacity release is
   wired to the same single timer.
2. **A visitor-facing equivalent of `18-07`'s panel** - a new, visitor-scoped read across all of a
   visitor's own past conversations for this site, gated on the visitor's own token rather than an
   operator's permission. Closest in shape to what Jivo appears to do. Needs: a real access-control
   story (a visitor's own token proving *which* visitor, never another one's history - the
   `ChannelIdentity` gate above cannot be reused, a new widget-specific check is needed), and a look at
   `docs/architecture/personal-data.md` (`16-02`'s erasure guarantees, and `18-07`'s own note that a
   cross-conversation read is "a genuinely new way a message becomes visible" - the identical question
   arises here, for the visitor's own data this time, not an operator's).
3. **Do not auto-close a widget conversation at all until the visitor's identity itself lapses** (7
   days) - functionally close to option 1 but implemented by decoupling *capacity release* from
   *conversation closure* (release the operator's slot on inactivity, the way `25-117`'s `4-04`
   mechanism already does for a disconnected operator, without marking the conversation `Closed` or
   losing its history) - a real domain-model change (`Conversation` would need a state, or a released-
   but-not-closed status, that `GetActiveForVisitorAsync` and the operator's own queue both already
   know how to treat correctly).

None of these is a deployment-config change. Whichever is chosen needs its own scope, and probably its
own ADR given it changes what "the conversation ends" means for a widget - state the choice and the
reasoning explicitly rather than picking the first one that compiles.

## Where this is likely to go wrong

- **Do not reuse `GetVisitorHistoryHandler`'s existing `ChannelIdentity` gate for a widget visitor** -
  it is the literal mechanism that currently, correctly, excludes them; extending it without redesign
  would either wrongly gate widget visitors the same way (permission-based, operator-only) or wrongly
  bypass a check that exists on purpose.
- **A visitor-facing cross-conversation read is exactly the shape `18-07`'s own remarks call "a
  genuinely new way a message becomes visible"** - `docs/architecture/personal-data.md` needs updating
  in the same change, the identical discipline that item already followed for the operator-facing case.
- **Whatever ships must survive `16-02`'s erasure guarantee** - a visitor's erased conversation must
  not resurface through this new read path.

## Answered, 2026-09-17

**Chosen: a fourth shape, not listed above** - found re-reading `AutoCloseInactiveConversationsJob`'s
own SQL rather than assuming its three named alternatives were exhaustive. `FindStaleAssignedBatchAsync`
only ever selects `state = 'Assigned'` rows - a `Waiting` conversation is never touched by this job at
all today, and `IConversationRepository.GetActiveForVisitorAsync` (`StartConversationHandler`'s own
resume check) already treats `Waiting` as active exactly like `Assigned`. That means the widget side of
this problem needs **no new read mechanism and no new domain state**: a conversation already knows how
to sit in `Waiting`, indefinitely, fully resumable by the same visitor through the exact code path that
exists today.

**The fix is splitting one job's single window into two, for the widget bucket only:**

1. **Release** (short window, unchanged default - the existing `WidgetInactivityWindow`, 1 hour): an
   `Assigned` widget conversation with no message either direction for this long is released back to
   `Waiting` - `Conversation.ReleaseToQueue`, the identical domain method `OperatorConversationReleaser`
   already calls for `4-04`'s disconnect case, generalised to a per-conversation caller instead of a
   per-operator one. Frees the operator's capacity slot immediately, same as today.
2. **Close** (new, long window - `WidgetCloseWindow`, default matched to `JwtTokenService.
   VisitorTokenLifetime`'s 7 days): *any* widget conversation - `Assigned` or `Waiting` - with no
   message for this much longer stretch is actually `Close()`d, through the unchanged
   `AutoCloseConversationHandler` path. This is what keeps a genuinely abandoned conversation from
   sitting in `Waiting` forever once the visitor's own identity has also lapsed.

Channel-kind conversations (MAX/Telegram/etc.) are **untouched** - they keep their existing single-
window, `Assigned`-only auto-close exactly as `18-06` built it. This item is scoped to the widget
bucket alone, the same scope the author's own comparison (against Jivo, a widget product) named.

**Rejected, and why:**
- **A visitor-facing equivalent of `18-07`'s panel** (option 2 above) - would have needed a new
  access-control surface, a `personal-data.md` update and an erasure review for a genuinely new way a
  visitor's own messages become newly readable across conversation boundaries. All of that is
  unnecessary once the real fix turns out to need no new conversation boundary crossed at all.
- **Widening the single existing window** (option 1 / `25-117`'s original attempt) - still conflates
  capacity with memory; the two-window split is what actually separates them.

**Known cost, stated because it is real**: a `Waiting` conversation now sits, visible in whatever the
operator's own queue view considers "waiting," for up to `WidgetCloseWindow` instead of disappearing
after `WidgetInactivityWindow`. Whether the console's own Waiting list needs a "stale" visual
distinction or a recency sort is a real UX question this item does not resolve - named as a follow-up
if it turns out to matter in practice, not solved speculatively here.

## Done when

- [x] A design decision is written down - see "Answered" above.
- [ ] A returning widget visitor whose previous conversation was only *released* (not yet closed) can
      resume it - same conversation id, full prior history, through the existing
      `GetActiveForVisitorAsync`/`StartConversationHandler` path, no widget or API change needed for
      this part.
- [ ] An `Assigned` widget conversation idle past `WidgetInactivityWindow` (unchanged, 1 hour) is
      released back to `Waiting` and frees the operator's capacity slot - not closed.
- [ ] A widget conversation (`Assigned` or `Waiting`) idle past the new `WidgetCloseWindow` (7 days) is
      actually closed.
- [ ] Channel-kind (MAX/Telegram/etc.) auto-close behaviour is provably unchanged - existing tests for
      it still pass unmodified, and new tests do not touch that code path.
- [ ] No new migration, no new read endpoint, no `personal-data.md` change - confirm this stays true
      given the chosen design touches no new data-visibility surface.
