# Fix: `operatorUnreadCount` only ever increments — nothing marks a conversation read

- **Stage**: 5
- **Status**: done
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

- [x] An assigned operator can clear a conversation's unread count through a real server-side write,
      and the count stays cleared across a reload — verified live against the local cluster, not just
      unit-tested. Verified live at the API level against the compose stack (real Keycloak token for
      the seeded `demo-operator`, real Postgres): a conversation sitting at `28` unread went to `18`
      on a mark-read up to sequence `10`, then to `0` on a full one, and `psql` — a different client
      than the one that wrote it — reads back `last_sequence=28, operator_unread_count=0,
      operator_last_read_sequence=28`. The **browser** half of "across a reload" was not verified: it
      needs an interactive Keycloak login, which the implementing session cannot perform. Everything
      it would have shown is proven a layer down, by that live check plus
      `MarkConversationReadEndpointTests.TheAssignedOperator_ClearsTheCount_AndItStaysClearedOnReload`.
- [x] An operator who is not assigned to the conversation cannot clear its count (real `403`,
      integration-tested alongside the existing operator-authorization tests).
      `MarkConversationReadEndpointTests` drives the production endpoint mapping over a `TestServer`
      against real Postgres; also confirmed live, where the seeded `demo-admin`'s token against
      another operator's conversation returns `403` with
      `{"type":"Conversation.Forbidden", ...}` and leaves the count untouched.
- [x] Marking an already-read conversation read is a no-op, proven by a test — at three levels,
      because "no-op" means something different at each: the domain method returns `false` and
      mutates nothing (`ConversationTests`), the handler therefore skips `SaveAsync` entirely rather
      than writing the same values and bumping `xmin` (`MarkConversationReadHandlerTests`), and three
      identical `POST`s in a row all return `200` with the same body (`MarkConversationReadEndpointTests`).
- [x] A concurrent `IncrementUnreadCount` and mark-read on the same conversation leave a correct
      count — proven by a real concurrency test against Postgres, in `Ago.Chat.Concurrency.Tests`
      alongside the existing capacity/assignment ones, not reasoned about. "Correct" means the item's
      own stated rule from Scope: a message that arrived and was never seen must still be counted.
      `MarkConversationReadConcurrencyTests`, 4 tests. The load-bearing one is
      `MarkRead_RacedMidSaveByAMessageTheOperatorHasNotSeen_StillCountsIt`, which injects a real
      committed increment at the instant the handler is inside `SaveAsync` and then asserts the exact
      final number — it fails outright for a load-reset-save implementation.
- [x] The visitor-side decision is stated either way, in code and in this item.
      **Deliberately not fixed** — see "Decisions" below.
- [x] `ago-console`'s session-local read state is reduced to whatever remains genuinely useful, and
      `11-06`'s documented reload limitation is removed rather than left describing behaviour that no
      longer exists.

## Decisions

Each of the four choices this item left open, with the reasoning it asked for.

**Transport: REST, not a hub method** — `POST /api/v1/conversations/{id}/read`, a sibling of `/close`.
The item leaned hub and the deciding argument went the other way: this write's failure modes have to
be *visible*. A non-assigned operator gets a real `403` with an RFC 7807 body here (`api-design.md`,
`ErrorExtensions`); over SignalR that would be a `HubException` carrying a string, indistinguishable
at the client from a transport fault — and the item's own Done-when asks for a real `403`. The same
goes for the `409` a doubly-raced write returns. The "high-frequency, low-value" premise also turned
out not to hold under the semantics below: mark-read fires once per conversation *open* plus a
500 ms-debounced call while one is on screen, which is a handful of requests a minute per operator,
not per-message traffic. An HTTP call also does not silently vanish while the hub is mid-reconnect,
which is exactly when an operator is catching up on a backlog. Moving it to the hub later is a
transport change with no handler change.

**Semantics: opening clears it, up to the newest message the console actually has.** The console
passes `upToSequence` = the highest sequence it has rendered, not a "clear it" flag and not the
conversation's `last_sequence` from the queue row (which may already be ahead of what is on screen).
"Opened" and "saw the newest message" collapse into the same thing here for a real reason rather than
by assumption: `Thread` auto-scrolls to the newest arrival whenever the operator is at the bottom,
which they are on open. So scroll tracking would add machinery and change nothing. One refinement the
simple rule needed: a conversation left open in a **backgrounded tab** stops marking itself read
(`document.visibilityState`), because `11-06`'s document-title count exists precisely to tell a
backgrounded tab the truth, and silently clearing it would kill that feature.

**Concurrency: clear up to a watermark, with the increment guarded by it; retry once on a conflict.**
`Conversation` gains `OperatorLastReadSequence`. `MarkReadByOperator` clamps the requested sequence to
`LastSequence`, subtracts the visitor messages inside the newly-read range (floored at zero), and
moves the watermark. `IncrementUnreadCount` gains the message's `sequence` — already on the wire as
`MessageAccepted.Sequence`, so no contract change — and skips a message at or below the watermark.
That pair is what makes the two writers compose instead of fight: whichever commits first, the other
re-decides correctly against fresh data on reload, and **anything above the watermark is still counted
whenever its increment lands**, which is the item's own definition of correct. An unconditional zero
was rejected exactly here: reload-and-reapply would re-zero on top of the concurrent increment and the
arriving message would be lost from the badge permanently. On a losing save the handler takes `6-08`'s
retry-once (a second conflict becomes `Conversation.ConcurrencyConflict` → `409`); "do nothing", which
this item names as defensible, was rejected because the console leaves a conversation on screen for
minutes, so "the next open" can be a long way off and the badge would sit visibly wrong the whole time
for a race the server can settle in one extra round trip.

The one residual, stated rather than discovered later: the subtraction is floored at zero because the
counter is maintained asynchronously (the message row commits, its increment lands later), so a range
can contain messages that were never counted. If increments for one conversation ever arrive *out of
order across the read boundary* — a higher sequence counted while a lower one is still in flight — the
count can be one or two low until the operator's next read, which corrects it. It is never an
over-count, and it never drops a message the operator has not seen. Making it exact would mean
deriving the count from the messages table instead of maintaining it, which is a different item.

**Visitor side: deliberately not fixed, and the asymmetry is pinned by a test.** `VisitorUnreadCount`
has the identical never-cleared shape and is left exactly as it was. Nothing reads it: the widget
renders no unread badge, so a `MarkReadByVisitor` would be a write path with no caller, no transport,
and no way to prove end to end — the same reason `messages.read_at` has stayed a column with no
writer, which this item's own Out of scope already names. `ConversationTests.MarkReadByOperator_DoesNotTouchTheVisitorsCount`
holds the line so it cannot drift silently. When the widget grows a badge the shape transfers
unchanged: a `VisitorLastReadSequence` twin plus the mirrored guard in `IncrementUnreadCount`.

## What turned out wrong in this item as written

- The Scope's transport paragraph leaned hub; the Done-when's "real `403`" quietly assumed REST. Those
  two cannot both be satisfied — a hub method has no status codes. REST won, and the Done-when is the
  half that was right.
- "Any change to how the count is incremented (`2-05`'s existing consumer path stays as-is)" is listed
  as out of scope, but the concurrency section's own suggestion — clearing up to a known sequence so a
  concurrent increment can land on top — cannot work unless the increment also consults that sequence.
  The consumer *path* is unchanged (same handler, same inbox dedup, same broker retry); the domain
  method it calls gained a `sequence` parameter and a guard. Without that guard the badge would flicker
  back on for every message read while its increment was still in flight, which is the common case, not
  an exotic one.

## Shipped in

`feat/5-15-mark-conversation-read` in `ago-chat` and `ago-console`.

New in `ago-chat`: `Conversation.OperatorLastReadSequence` + `MarkReadByOperator`, the sequence-guarded
`IncrementUnreadCount`, `MarkConversationReadHandler`, `POST /api/v1/conversations/{id}/read`, and
migration `Stage5AddOperatorLastReadSequence` (`operator_last_read_sequence integer not null default 0`
— additive, reversible, no backfill: zero is the truthful value for every existing row, which is why
the first open after this ships clears the whole accumulated backlog). Permission is the existing
`conversation:read`, not a new one — marking read is a side effect of reading, and "may view
conversations but may not admit to having viewed them" is not a role anyone wants. Full suite:
519/519 green.

In `ago-console`: `markConversationRead` in `api/conversationsApi.ts`, `markRead` on the workspace
outlet context, the debounced visibility-aware call in `ConversationPage`, and `attention.ts` reduced
from a parallel read-state model to a freshness overlay over the server's number. That rewrite also
fixed a latent `11-06` bug it exposed: locally counted arrivals were never retired when a queue
snapshot caught up with them, so a message could be counted twice for up to one poll interval. 85/85
console tests green.

## Open questions

None. Both discretionary choices — hub versus REST, and "opened" versus "saw the newest message" — are
recorded under Decisions above with their reasoning.
