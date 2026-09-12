# 25-68 · One open conversation per visitor

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-12, live - the author's own operator account on `reserve-me.ru` listed the same
  visitor twice: two `Conversation` rows, `site_id`/`visitor_id`/`operator_id` identical, `state`
  both `Assigned`, `created_at` **19 microseconds apart** (not milliseconds), zero messages in
  either. The visitor's own `last_seen_at` matched the first row's `created_at` exactly, and
  `first_seen_at` was three days earlier - a returning visitor, not a first contact.

## What is actually true

`StartConversationHandler.HandleAsync` (`Ago.Chat.Application`) decides whether a visitor already has
an open conversation with a plain read (`IConversationRepository.GetActiveForVisitorAsync`, no lock)
and, if not, creates one. Two concurrent callers for the same visitor - two browser tabs sharing one
persisted `visitor_id` (the widget's own token, per-browser not per-tab), or a widget reconnect racing
its own prior connection before it has finished joining - both run the read before either has
committed, both see nothing, and both insert. Nothing in the schema stops it: `conversations` carries
no unique constraint narrower than its own primary key.

Traced end to end: `ago-widget` → SignalR `VisitorHub.JoinAsync`/`JoinWithTrafficSourceAsync`, called
"once, right after connecting" per that method's own doc comment → `StartConversationHandler`. The
identical handler is also the one `ReceiveChannelMessageHandler` calls for a message arriving over a
non-widget channel, so the race is reachable from there too, not only from the hub.

Confirmed this is not a systemic, frequent failure: a scan of every `(site_id, visitor_id)` pair with
more than one `Conversation` row found exactly one pair created within the same sub-millisecond
window - this incident. Every other repeat-visitor pair the scan found spans days, which is ordinary
(a visitor returns, their prior conversation is closed, they start a new one).

## Scope

- A partial unique index on `conversations(visitor_id)`, filtered to the same predicate
  `GetActiveForVisitorAsync` already reads (`state <> 'Closed'`) - a visitor may still open a fresh
  conversation once their last one is actually closed, but never two open ones at once.
- `ConversationRepository.SaveAsync` translates the resulting Postgres unique-violation into
  `ConversationConcurrencyConflictException`, the identical shape `23-04`'s
  `ix_conversation_assignments_open` and `25-34`'s message-sequence index already use.
- `StartConversationHandler` catches it once: the loser's own copy lost the race, but the winner's row
  is already committed and visible to a fresh read, so the loser simply returns it - `IsNew: false`,
  not a retry-and-reapply (there is nothing to reapply; "start a conversation" has no decision left
  once one already exists).
- Cleanup of the one live duplicate this item's own report names - closed without touching the
  winner, since neither row carries any message or assignment history worth reconciling.

## Out of scope

- `25-67` - the sibling race on `PK_visitors` for two concurrent *first* contacts by a brand-new
  visitor, found while writing this item's own concurrency test and deliberately split out (a
  different constraint, a different repository, no ambiguity about which row to keep).
- Preventing two browser tabs from sharing one `visitor_id` in the first place, or changing when the
  widget calls `JoinAsync` - both are legitimate, and the fix belongs at the layer that actually
  decides "how many conversations", not at either of its callers.

## Done when

- [ ] Two concurrent `StartConversation` calls for the same visitor, raced deterministically mid-save
      (not merely hoped to collide), settle on exactly one `Conversation` row - proven by a
      concurrency test against a real Postgres, fails-before against the unpatched handler.
- [ ] Many concurrent calls (not just two) for the same already-existing visitor agree on the same
      single conversation.
- [ ] Two different visitors racing at the same instant are unaffected - each gets its own
      conversation.
- [ ] The live duplicate this item's own report names is resolved on the real deployment.
