# Wire up conversation closing - a real trigger, not a dead domain method

- **Stage**: 6
- **Status**: ready
- **Depends on**: nothing - unblocks `6-05`'s `Closed` webhook trigger, but stands on its own

## Goal

`Conversation.Close()` (`Ago.Chat.Domain`) has existed since Stage 1, raises `ConversationClosed`,
and has never had a caller - no use case, no integration event, no mapper, no endpoint. After this
item, an operator can actually close a conversation, and the rest of the system (unread counts,
`5-07`'s eventual console view, `6-05`'s webhook dispatch) can react to it as a real event, not a
theoretical one.

## Context to read first

`Ago.Chat.Domain/Conversation.cs`'s `Close()` and `Ago.Chat.Domain/ConversationClosed.cs` (the domain
event, already there). `Ago.Chat.Application/Mapping/ConversationAssignedToOperatorMapper.cs` and
`.../ConversationReleasedToQueueMapper.cs` - the exact pattern this item repeats one more time for
`Closed`. `adr/0016` - closing is a `conversation:assign`-adjacent capability; confirm during this
item whether it warrants its own permission (`conversation:close`) or reuses an existing one - state
the reasoning either way, the same "author's decision, stated as an open question below with a
recommendation" shape `5-06` used for its own framework choice.

## Scope

- `CloseConversation` use case (`Application/UseCases/CloseConversation/`): operator-only (a visitor
  has no reason to close their own conversation - ending a chat session client-side is not the same
  as closing the record), checks the operator is assigned to it (same shape `SendOperatorMessage`
  already uses), calls `Conversation.Close()`, persists, stages the mapped `ConversationClosed`
  integration event in the same transaction (`adr/0005`).
- `ConversationClosed` in `Ago.Chat.Contracts` + its mapper - `conversation_id`, `closed_at`, nothing
  else (no visitor/operator identity needed by a webhook receiver beyond knowing which conversation).
- An endpoint or hub method for an operator to actually call it - `POST /api/v1/conversations/{id}/close`
  matching `api-design.md`'s "actions that are not CRUD become sub-resources" rule (the same shape
  `AttachmentEndpoints`' confirm route already uses), or an `OperatorHub` method if the console (`5-07`)
  is expected to trigger it mid-conversation without a page navigation - author's call, state it.
- `messaging.md`'s Topics table gets `ConversationClosed` as a real row, not the "ConversationAssigned
  / Closed" combined placeholder it currently is.

## Out of scope

- Any UI for closing a conversation - `5-07`'s console, once it exists; this item only makes the
  server-side capability real.
- Reopening a closed conversation - `Conversation.Close()` is terminal by its own existing domain
  invariant (no path back, matching `Attachment.MarkDeleted`'s own terminal-state precedent); if the
  product actually needs reopen, that is new domain design, not a wiring task.
- Auto-closing a conversation on inactivity/timeout - a real, separate feature (needs a policy: how
  long, whose job triggers it) that this item's own "just wire up the existing method" scope does not
  stretch to cover.

## Done when

- [ ] `CloseConversationHandler` unit-tested (happy path, wrong-operator forbidden, already-closed
      rejected - `Conversation.Close()`'s own existing invariant, now actually reachable through a
      real call path for the first time).
- [ ] `ConversationClosedMapper` tested the same way every other mapper in `Mapping/` already is.
- [ ] Integration test: closing a conversation produces a real, durable `outbox` row with the mapped
      contract, verified against real Postgres (`Ago.Chat.Integration.Tests`, matching `2-02`'s own
      "outbox already has a real writer" verification bar).
- [ ] `messaging.md` updated: `ConversationClosed` is its own real row, not folded into a placeholder.

## Open questions

**Needs the author's decision**: a dedicated `conversation:close` permission, or reuse
`conversation:assign` (closing is arguably "removing yourself/ending the assignment," a similar
authority level)? Recommendation: a dedicated `conversation:close` - `adr/0016` chose granular
permissions specifically so a future custom role could grant one without the other (a supervisor role
that can close conversations but not reassign them is a realistic split), and the marginal cost of
one more named permission is small.

**Needs the author's decision**: REST endpoint vs. `OperatorHub` method for triggering the close.
Recommendation: REST (`POST /api/v1/conversations/{id}/close`) - closing is a one-shot action, not
part of the realtime message-exchange protocol `OperatorHub`'s other methods serve, and
`api-design.md`'s own sub-resource-action pattern already fits it exactly.
