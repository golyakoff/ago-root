# ADR-0033: A capacity claim is a receipt on the conversation, not an assumption about assignment

- **Status**: Accepted
- **Date**: 2026-08-25
- **Stage**: 6 (`6-09`)

## Context

`operators.active_chats` is the counter the automatic assignment engine reads inside its own
transaction to decide whether an operator can take another conversation. `4-01` built its claim half
as an atomic compare-and-set — `UPDATE operators SET active_chats = active_chats + 1 WHERE id = @id
AND active_chats < capacity` — and proved it correct under contention. `concurrency.md` described a
"symmetric release" next to it. There was none in any ordinary path: the only caller of
`IOperatorCapacity.ReleaseAsync` was `4-04`'s bulk sweep, which runs when an operator's last
connection anywhere drops. Closing a conversation released nothing, so `active_chats` only ever went
up under exactly the traffic pattern the product exists for — an operator finishing conversations one
at a time. `7-04`'s `assignment-contention` run measured the consequence
(`load/reports/2026-08-24-assignment-contention.md`): 51 of 150 conversations assigned, then a flat
plateau for 210 seconds while 49 closes succeeded and freed nothing.

Adding the release exposes a fact the counter's design had quietly assumed away: **the two ways a
conversation becomes `Assigned` are not symmetric.**

- The automatic engine (`SkipLockedAssignmentClaimer`, `RedisLockAssignmentClaimer`,
  `Ago.Chat.Worker`) calls `TryClaimAsync` first and assigns second, both in one transaction. That
  assignment is backed by a real slot.
- `AssignConversationHandler` — the operator picking a conversation up by hand, behind
  `OperatorHub.JoinConversationAsync` — never touches `IOperatorCapacity` at all. That assignment is
  backed by nothing.

So "release the operator's claim when the conversation closes" is not a well-formed instruction until
something says *whether there is a claim*. Releasing unconditionally would decrement, for every
hand-picked conversation ever closed, a slot that some other conversation is holding — an under-count
that lets the engine over-subscribe an operator. `ReleaseAsync`'s floor at zero prevents a negative
number, not a wrong one.

## Decision

**A capacity claim is recorded on the conversation that holds it**, as
`Conversation.HoldsCapacityClaim` (`conversations.holds_capacity_claim`, migration
`Stage6AddConversationCapacityClaim`).

1. `AssignTo(operatorId, now, holdsCapacityClaim: false)` — the default is "no slot behind this
   assignment", the direction that can only ever under-release. Only a caller that has just seen
   `TryClaimAsync` return `true`, in the same transaction as the save, passes `true`.
2. `Close` and `ReleaseToQueue` **consume** the receipt and return whether they did. The consumption
   is part of the same `SaveChangesAsync` as the state transition, under the conversation row's own
   `xmin`.
3. `CloseConversationHandler` and `OperatorConversationReleaser` call `ReleaseAsync` exactly when that
   consumption happened.
4. The release is issued **after** the close commits, never before.

The invariant this maintains, and the one any future change is checked against: **`active_chats`
equals the number of conversations currently `Assigned` to that operator whose `holds_capacity_claim`
is true.**

Idempotency falls out of the state machine rather than out of a "have I released yet?" flag. Two
concurrent closes: one wins on `xmin`, the other reloads, finds the conversation `Closed`, and is
rejected before reaching a release. `6-08`'s retry-once: the first attempt's save rolled back with its
receipt intact, so the retry consumes it exactly once. A client replaying the whole request: rejected
as already closed.

The migration also repairs existing rows — declaring every currently-`Assigned` conversation to hold a
claim and resetting each operator's `active_chats` to that count. See Consequences.

## Consequences

- The counter has a checkable meaning for the first time. Before this, "what should `active_chats` be
  right now?" had no answer that could be computed from anything else; now it is a `count(*)`, which
  is what let the repair migration be written at all and what
  `CloseConversationCapacityConcurrencyTests` asserts exactly rather than as a range.
- **Manual assignment stays capacity-blind, deliberately and now consistently** — no claim on the way
  in, no release on the way out. This is honest accounting, not a fix: an operator who picks up five
  conversations by hand still consumes five conversations' worth of attention while the engine
  believes they are idle, and the engine will keep assigning to them. That is a real defect, it is
  older than this ADR, and it is not this one's to fix — making manual assignment claim is a product
  decision (an operator at capacity would be refused a conversation they explicitly chose), and it
  needs a transaction boundary the Application layer does not currently have. Filed as follow-up.
- **A leak window remains, bounded and one-sided.** A process death between the close's commit and the
  decrement leaks one slot — the pre-`6-09` behaviour, for one conversation. The alternative ordering
  is worse: releasing first means a save that then loses on `xmin` leaves the conversation assigned
  with its slot handed back, and the operator over-subscribable for the rest of that slot's life. A
  leak is recovered when the operator eventually goes offline; an over-release is not recovered at
  all.
- **`Conversation.Close`/`ReleaseToQueue` now return a value callers must not ignore.** That is a
  deliberate cost: a caller that drops the result silently reintroduces the leak. It was still
  preferred to the caller reading `HoldsCapacityClaim` before calling, which is a check-then-act on a
  value the call is about to change, and which reads as true on an aggregate whose close then threw.
- **A data-repair migration is now part of the schema history.** Normally out of bounds. It runs here
  because every deployed database already carries the leak and nothing in the new code path revisits
  an already-closed conversation, so the fix alone would leave every existing environment exactly as
  jammed as it is — including the public demo, where the waiting queue is stopped.
- One more column on `conversations`, on the write path's hottest aggregate. No index: it is read only
  as part of an aggregate already located by primary key.

## Alternatives considered

**Make `AssignConversationHandler` claim capacity too, and release unconditionally on close.** The
cleanest invariant — `active_chats` would equal the count of assigned conversations, full stop, with no
new column and no receipt to keep honest. It also fixes the over-subscription described above rather
than documenting it. Rejected for this item on three counts: it changes user-visible behaviour (an
operator at capacity is refused a conversation they deliberately picked from the queue, which is a
product call, not a bug fix); `AssignTo`'s reconnect no-op means the handler would have to distinguish
a real transition from a repeat join before claiming; and the claim would need to commit atomically
with the conversation save, which in `Ago.Chat.Api` means introducing a transaction port into the
Application layer — a larger architectural addition than the defect warrants. Worth revisiting as its
own item, at which point the receipt column becomes redundant and can be dropped.

**Release from a `ConversationEnded` consumer in `Ago.Chat.Worker`.** The outbox already commits that
event with the close (adr/0005), so the release would survive a crash in the window this decision
leaves open, and idempotency could come from the same receipt consumed by a conditional `UPDATE`.
Rejected because it buys crash-safety for a single `UPDATE` at the price of a new consumer, queue
binding and redelivery argument — and because it frees the slot only after the dispatcher poll and a
broker hop, when the entire user-visible point is that an operator who just finished a chat can be
handed the next one now.

**Recompute `active_chats` from `conversations` on every release** (`SET active_chats = (SELECT
count(*) ...)`). Self-correcting and needs no new column. Rejected as unsafe: the engine increments
speculatively *before* the assignment row is written, inside its own transaction, so a recompute from
another transaction can read a count that does not yet include a claim in flight and clobber it. The
same reasoning rules out having the disconnect sweep zero the counter outright.

**Release unconditionally on close and accept the hand-picked case as noise.** Rejected: the error
does not stay noise. Each hand-picked close eats a slot a live conversation is holding, and the floor
at zero converts that into "the engine believes this operator is free" — over-subscription, which is
strictly worse than the leak being fixed.
