# Assignment engine: SKIP LOCKED batch claiming

- **Stage**: 4
- **Status**: ready
- **Depends on**: `4-01-waiting-queue-and-capacity-model.md`

## Goal

A waiting conversation gets assigned to a free operator without any human clicking "claim" - the
automated path `docs/vision.md` describes ("No operator assigned -> conversation enters the waiting
queue -> assignment engine picks a free operator respecting their capacity -> both sides are
notified"). Multiple `Ago.Chat.Worker` replicas run this loop at once and never conflict: `SKIP
LOCKED` means two replicas racing for the same waiting conversation is a non-event, not a bug to
avoid by coordination.

## Context to read first

`docs/architecture/concurrency.md`'s "Operator assignment - the contended path" section in full
(mechanism A specifically - this item builds only that; mechanism B is `4-03`), `4-01`'s own file
(the port and query this item consumes), `src/Ago.Chat.Worker/OutboxDispatcher.cs` as the direct
structural precedent (a `BackgroundService` that claims rows with `FOR UPDATE SKIP LOCKED` in a
batch, processes each, and treats "someone else already has it" as unremarkable), `adr/0005`
(outbox - `ConversationAssigned` must reach both participants through it, never a direct hub push
from inside this loop), `docs/architecture/messaging.md` (event contract shape for a new integration
event, if `ConversationAssigned` does not already have one), the `vertical-slice` skill.

## Scope

- `ConversationAssignmentJob` (or similar name - match `PartitionMaintenanceJob`/`OutboxDispatcher`'s
  naming pattern), a `BackgroundService` in `Ago.Chat.Worker`, `PeriodicTimer`-driven
  (`concurrency.md`'s timer rule).
- Per tick, per site with waiting conversations: claim up to `BatchSize` waiting conversations
  (`4-01`'s `FOR UPDATE SKIP LOCKED` query) inside one transaction. For each claimed conversation, in
  the same transaction, find a candidate operator (online, same site, some ordering - "oldest waiting
  conversation first" is already implied by the claim query's `ORDER BY created_at`; operator
  selection order - e.g. least-loaded first - is this item's own decision, not specified upstream,
  so pick one, state the reasoning, and note it is unmeasured) and attempt `IOperatorCapacity.
  TryClaimAsync`. On success: `conversation.AssignTo(operatorId, now)`, save, write
  `ConversationAssigned` to the outbox in the same transaction (`adr/0005` - the write and its event
  are one commit, publishing is `OutboxDispatcher`'s separate concern, already shipped). On failure
  (no operator had capacity): the claimed row's lock releases when the transaction ends without
  assigning it - it goes back to being visible to the next tick, exactly as `concurrency.md`
  describes "a row count of 0... is a normal outcome to retry."
- Both participants notified: confirm the existing fan-out path (`3-02`'s `ConnectionFanoutConsumer`
  reacting to an outboxed event) is suficient for `ConversationAssigned,` or extend it - this event
  type may not have flowed through fan-out before (the existing manual claim path,
  `AssignConversationHandler`, does not currently write it to the outbox at all - confirm this
  during implementation and treat a silent gap there as a real finding to fix, not scope creep to
  avoid, since Stage 4's whole "both sides notified" claim depends on it working for both the manual
  and automatic paths, not just the new one).
- Config: batch size and job interval, following `PartitionMaintenanceJobOptions`'s existing shape
  (`SectionName`, bound and validated at startup). State plainly that these are starting points, not
  measured (`CLAUDE.md`: "measure or stay silent" - Stage 7 gives this a real number, same caveat
  already attached to `MessageSendRateLimitOptions` and `DrainOptions`).
- Multiple `Worker` replicas running this loop concurrently is the actual point - prove it, don't
  just assert it (see Done when).

## Out of scope

- The Redis distributed-lock alternative - `4-03`, behind the same conceptual claim step but not
  literally the same code path (this item does not need to anticipate its shape).
- Releasing an assigned conversation back to the queue on operator disconnect - `4-04`. This item's
  only producer of a requeue is "claimed but no capacity found," which never assigned in the first
  place.
- The in-process message-ingest pipeline (bounded channel, batch writer, `ConversationSequencer`) -
  `4-05`, unrelated hot path.
- Changing operator selection into anything beyond a simple, stated, unmeasured ordering - a real
  scheduling policy (skills-based routing, priority) is not in any roadmap deliverable for this
  project.

## Done when

- [ ] `Ago.Chat.Concurrency.Tests`: N waiting conversations, M operators with limited total capacity,
      **multiple job instances running concurrently against the same Postgres** (not one instance
      called twice sequentially - the actual claim is what needs proving) - every conversation ends
      up assigned to exactly one operator or still waiting, no operator's `active_chats` ever exceeds
      its `capacity`, and re-running the same scenario repeatedly stays green (`concurrency.md`'s own
      test description: "fires K messages from M threads... asserts... repeated under stress" is the
      bar for this test too, applied to claims instead of message sequences).
- [ ] Both the visitor and the operator receive a `ConversationAssigned` notification through the
      existing SignalR fan-out path, proven live or by an integration test exercising the real outbox
      -> dispatcher -> fan-out chain, not asserted from the domain event alone.
- [ ] `Ago.Chat.Architecture.Tests` stay green - the raw-SQL claim query and the job itself live in
      `Ago.Chat.Worker`/`Ago.Chat.Infrastructure.Postgres` exactly as `4-01` and `adr/0004` place them.
- [ ] `docs/architecture/concurrency.md` gets a "Shipped in `4-02`" note under "Operator assignment"
      recording the actual batch size/interval chosen and the operator-selection ordering, with the
      unmeasured caveat stated.
- [ ] `docs/vision.md`'s assignment sequence (lines ~55-59) confirmed still accurate, or corrected.

## Open questions

None - operator-selection ordering is this item's own call to make and document, not something that
blocks starting.
