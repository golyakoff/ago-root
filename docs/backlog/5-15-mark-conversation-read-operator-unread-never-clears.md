# Fix: `operatorUnreadCount` only ever increments — nothing marks a conversation read

- **Stage**: 5
- **Status**: ready
- **Depends on**: nothing — `ago-chat` only. `ago-console` picks the fix up for free once the write
  exists (`11-06`'s workspace already knows which conversation is open and when it was read).

## Goal

An operator opening a conversation clears its unread count for real, server-side, so the count means
"messages this operator has not seen" rather than "messages ever received." After this item,
`11-06`'s unread badge and document-title count survive a page reload instead of being a
session-local approximation layered over a number that never goes down.

## Context to read first

`Ago.Chat.Domain/Conversation.cs` — `OperatorUnreadCount` is a private-set property with exactly one
writer, `OperatorUnreadCount++` inside `AddVisitorMessage` (line ~185 as of this writing). There is no
decrement, no reset, and no `MarkRead`-shaped method anywhere in the aggregate. Confirmed by grepping
the whole `src/` tree: every other reference is a read (`ConversationSummaryItem`,
`GetOperatorQueueHandler`, `GetAllConversationsForSiteHandler`, the Dapper read store, the EF mapping).
`docs/backlog/2-05-unread-counters.md` — where the counter came from, and note what it says about the
*visitor* side, which has the same shape and should be considered here rather than fixed twice.
`ago-console/src/workspace/attention.ts` (`11-06`) — the session-local read state the console layers
over the server value today, and its own doc comment on the residual defect this item removes: after a
hard reload, an already-read conversation over-reports.

## How this was found

Found while implementing `11-06` (2026-08-25). The workspace needed a real unread badge, `2-05`'s
`operatorUnreadCount` was already on the wire, and building against it surfaced that a badge fed from
that field alone would never clear — so the console had to invent a session-local read state to be
usable at all. Verified directly against the source rather than inferred, and observed live: the
seeded demo operator's queue rendered counts like `195` accumulated across every past session.

## Scope

- A real write path: a `MarkConversationRead`-shaped use case plus the domain method it calls
  (`Conversation.MarkReadByOperator(...)` or equivalent), resetting `OperatorUnreadCount` to zero for
  the assigned operator. Follows the same handler/repository/`Result<T>` shape as every other write in
  `Ago.Chat.Application/UseCases`, and the same authorization check the conversation's other operator
  actions already use (assigned-operator-only — an operator must not clear another operator's count).
- The transport: a hub method on `OperatorHub` rather than a REST endpoint is the likely fit, since
  the console already holds an open hub connection and marking-read is a high-frequency, low-value
  write — but that is this item's own call to make and state, not a foregone conclusion.
- Decide and state the semantics: does opening a conversation clear it, or does the operator have to
  actually see the newest message? Simplest defensible rule wins; write down which was chosen.
- **Concurrency with the counter's other writer — the part most likely to be got wrong.** This is not
  a fresh aggregate: `RecordUnreadMessageHandler` (`2-05`, consumer name `unread-counter`) already
  loads the same `Conversation` and calls `IncrementUnreadCount` from `Ago.Chat.Worker`, and
  `ConversationConfiguration` maps Postgres's `xmin` as a row version, so both writers are under
  optimistic concurrency by construction. Two consequences this item has to handle deliberately
  rather than discover:
  - **A losing save must not be an error the operator sees.** `RecordUnreadMessageHandler`'s own doc
    comment already states its side of this: a losing concurrent save throws, the broker retries, and
    a later attempt reloads the fresh count. Mark-read has no broker behind it, so it needs its own
    answer — retry-once-then-succeed is the obvious candidate (`6-08` already established that shape
    for conversation writes and is worth reading first), and doing nothing is defensible too if the
    next open re-issues it anyway. Whichever is chosen, say why.
  - **The genuine logical race, not just the technical one**: a visitor message arriving in the same
    instant as a mark-read can leave the count at zero for a message the operator never saw. Reading
    the conversation, resetting to zero and saving is exactly the load-mutate-save that loses here.
    Consider clearing *up to a known sequence* (the newest message the operator actually has) rather
    than to an unconditional zero — that turns the operation into something a concurrent increment
    can safely land on top of, and it composes with the "reached the bottom of the thread" semantics
    above rather than fighting them. If an unconditional zero is chosen instead, state what happens
    to a message that arrives mid-write and why that is acceptable.
- Idempotency: marking an already-read conversation read again must be a no-op, not an error — the
  console will call this on every open, including re-opens.
- The **visitor** side (`VisitorUnreadCount`) has the identical never-cleared shape. Either fix both
  here and say so, or state plainly why the visitor side is deliberately left alone (the widget shows
  no unread badge today, so it may genuinely not matter yet) — do not silently fix only half.
- `ago-console`: once the write exists, `attention.ts`'s session-local layer either goes away or
  becomes a thin optimistic-update over the real value. Its doc comment about the reload limitation
  goes with it.

## Out of scope

- Per-message read receipts, or showing the *visitor* whether an operator has read their message.
  That is a product feature with its own privacy and UX questions, not this fix.
- Any change to how the count is incremented (`2-05`'s existing consumer path stays as-is).
- The `messages.read_at` column, which exists in `data-model.md`'s shape but is a different concern
  (per-message, not per-conversation) and has no writer either — worth its own item if it is ever
  wanted rather than being absorbed here.

## Done when

- [ ] An assigned operator can clear a conversation's unread count through a real server-side write,
      and the count stays cleared across a reload — verified live against the local cluster, not just
      unit-tested.
- [ ] An operator who is not assigned to the conversation cannot clear its count (real `403`,
      integration-tested alongside the existing operator-authorization tests).
- [ ] Marking an already-read conversation read is a no-op, proven by a test.
- [ ] A concurrent `IncrementUnreadCount` and mark-read on the same conversation leave a correct
      count — proven by a real concurrency test against Postgres, in `Ago.Chat.Concurrency.Tests`
      alongside the existing capacity/assignment ones, not reasoned about. "Correct" means the item's
      own stated rule from Scope: a message that arrived and was never seen must still be counted.
- [ ] The visitor-side decision is stated either way, in code and in this item.
- [ ] `ago-console`'s session-local read state is reduced to whatever remains genuinely useful, and
      `11-06`'s documented reload limitation is removed rather than left describing behaviour that no
      longer exists.

## Open questions

None blocking. The two real choices — hub method versus REST, and "opened" versus "saw the newest
message" — are both small enough for the implementing session to decide, provided each is stated with
its reasoning rather than left to be rediscovered from the code.
