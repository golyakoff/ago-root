# Auto-close inactive conversations

- **Stage**: 18
- **Status**: done — merged `ago-chat#108`/`ago-root#234` (2026-08-28), live in production
- **Depends on**: nothing — `Conversation.Close()`, `CloseConversationHandler` and the capacity-release
  path all already exist (`6-02`, `6-09`)

## Goal

An `Assigned` conversation nobody has touched in a while closes itself, freeing the operator's capacity
slot and clearing it from "Assigned to me" — without an operator ever pressing a button, and without
losing anything the visitor or operator said.

Found live 2026-08-28, testing `14-02`'s MAX integration end to end: an operator's queue had four
conversations open since 2026-08-24, none ever closed, still counted against that operator's capacity
days later. Nothing in this codebase currently closes a conversation except an operator's own explicit
action (`CloseConversationHandler`) — and a channel-bot conversation in particular may never get one,
since there is no "closing the tab" signal the way a widget visitor gives one.

## Context to read first

`docs/backlog/15-04-retention-and-pruning-jobs.md` — **this item is not that one.** 15-04 removes rows
nothing reads any more; this item changes `conversations.state`, a state the domain already models and
already treats as terminal (`Conversation.Close()`, `ConversationState.Closed`). No row is deleted,
archived, or made harder to read — a closed conversation's messages stay exactly where `GetHistoryAsync`
already finds them. Say this once, in the item, so nobody reads "auto-close" as "auto-delete."

`Ago.Chat.Infrastructure.Postgres/ConversationRepository.cs`'s `GetActiveForVisitorAsync` — filters on
`State != Closed` and is what `StartConversationHandler` already calls to decide "reuse the visitor's
open conversation, or start a new one." This is the fact that makes closing safe rather than lossy: the
next message from a *known* visitor (a MAX/Telegram/phone `channel_identity`, not an anonymous widget
session) starts a *new* conversation still linked to the *same* `visitor_id` — the history is one query
away by `visitor_id`, just split across conversation rows instead of one that never ends. `18-07` is
what actually surfaces that split history to an operator; this item only has to not break the link.

`Ago.Chat.Worker`'s existing scheduled jobs (`OutboxPruneJob`, `ConversationAssignmentJob`,
`OperatorDisconnectSweepJob`) — the shape a periodic maintenance job takes in this codebase already
exists; this is another one of those, not a new mechanism.

`Ago.Chat.Application.UseCases.CloseConversation.CloseConversationHandler` — reuse `Conversation.Close()`
and the same capacity-release path (`6-09`'s own remarks on why release happens strictly after the save,
and the documented one-slot-leak-on-crash residual). A system-driven close should look identical to an
operator's own close from every other consumer's point of view (outbox event, capacity accounting,
`ConversationClosed` integration event) — the only difference is who triggers it and that no
`OperatorId`/permission check applies, since nobody is acting on anybody's behalf.

**Note found while scoping this item, not this item's to fix:** `CloseConversationHandler` currently
lets an operator close a conversation regardless of whether the visitor's last message has been
answered — there is no guard against closing to duck a customer rather than finish with one. That is a
pre-existing gap in the *manual* close action, orthogonal to this item (which never touches a
conversation an operator is actively working), and is filed as its own suggestion rather than folded in
here.

## Scope

- A scheduled `Worker` job (own file, following the existing jobs' shape) that finds `Assigned`
  conversations with no message (either direction) more recent than a configurable inactivity window,
  and closes each through the same domain path `CloseConversationHandler` uses — `Conversation.Close()`,
  outbox `ConversationClosed`, capacity release.
- The inactivity window is configurable **per channel kind**, not a single global constant — website-
  widget conversations and channel (MAX/Telegram/SMS) conversations have different lifetimes by design
  (see Goal), and the config shape should say so rather than hide two meanings behind one number.
  `14-01`'s `ChannelKind` (or however conversations currently expose which channel they came from — a
  widget conversation has none) is the discriminator.
- `Waiting` conversations are explicitly **not** touched by this item — a conversation nobody has ever
  claimed is a queue-depth problem, not an inactivity one, and closing an unclaimed conversation would
  be answering "does anyone still want this" with "we stopped waiting," which is not this item's call
  to make.
- A log line or metric per auto-close, distinguishable from an operator-initiated close in whatever
  observability already exists for `ConversationClosed` (`architecture/nfr.md`'s conventions) — an
  operator should be able to tell "the system closed this" from "I closed this" if they ever look.

## Out of scope

- Deleting or archiving anything — `15-04`/`16-02`/`16-03` own that, unchanged by this item.
- A visitor-facing notice that their conversation closed. A real UX question (does a MAX user get a
  "closing due to inactivity" message before it happens?) and a separate decision; this item's own
  Done-when does not require one.
- The manual `CloseConversationHandler` reply-guard noted above.
- Any change to `Waiting`-state handling or the assignment engine.

## Done when

- [x] A Worker job closes `Assigned` conversations past their inactivity window, through the same
      domain path a manual close uses (outbox event fires, capacity releases) —
      `AutoCloseInactiveConversationsJob`/`AutoCloseConversationHandler`.
- [x] The window differs by channel kind (widget 1h default, channel 24h default, both configurable) —
      proven by test.
- [x] A conversation auto-closed for a known channel identity, followed by a new inbound message from
      the same identity, opens a **new** conversation still linked to the same `visitor_id` — proven
      end-to-end.
- [x] `docs/architecture/concurrency.md` names this job as a third capacity releaser alongside
      `CloseConversationHandler`/`OperatorConversationReleaser` (`ago-root#234`).

## Open questions

Default inactivity windows (widget vs. channel) are the author's call, not invented here — pick values
when the job is built, state them in the PR, and note that `CLAUDE.md` bans invented "typical" numbers:
whatever ships should be a stated default, not a claimed measurement.
