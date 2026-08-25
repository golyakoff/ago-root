# Transfer a conversation to another operator

- **Stage**: 18
- **Status**: ready
- **Depends on**: nothing new — it is `4-02`'s assignment machinery used a second way, and that is the
  point

## Goal

An operator can hand a conversation to a named colleague: the visitor keeps talking in the same
thread, the receiving operator's capacity is charged, the transferring operator's is released, and
nothing is lost in between.

## Why this is the second real one

Like `18-01`, this is not CRUD. It is a **contended state change on exactly the shared state
`4-02` was built to protect**: `operators.active_chats` is only ever moved by an atomic compare-and-set
(`UPDATE ... WHERE active_chats < capacity`), and a transfer is two of those that must agree — a claim
on the target and a release on the source. Getting it wrong produces either an operator over capacity
or a conversation belonging to nobody, which are the two failures `concurrency.md` spends its length
preventing.

`6-09` and `6-10` are the evidence that this area punishes carelessness: both were live defects in the
same lifecycle, one leaking capacity and one deadlocking against the assignment engine.

## Context to read first

`docs/architecture/concurrency.md`'s assignment section — the compare-and-set, and why the release is
the half that historically went wrong (`6-09`). `adr/0037` and `6-10` — the lock order against the
assignment engine, which a transfer must respect or reproduce that deadlock. `4-02`'s handler and
`OperatorCapacityStore`. `docs/backlog/13-01-operator-invitations-and-seat-entitlement.md` — a transfer
target must hold a seat, which is a state that item introduces. `docs/architecture/messaging.md` — the
transfer is a state change plus an integration event, so it goes through the outbox like every other.

## Scope

- A transfer use case: source operator, target operator, one transaction, capacity released on one
  side and claimed on the other, or neither.
- Refuse rather than queue when the target is at capacity, and say so in the interface — a transfer
  that silently becomes a queue entry is a worse answer than a refusal.
- Respect `adr/0037`'s lock order. A transfer touching two operator rows is exactly the shape that
  deadlocks against the assignment job if ordered carelessly.
- Both participants are told: the receiving operator's queue updates live, and the visitor sees
  whatever the product decides they should — which is a real choice, not an implementation detail.
  State it.
- Concurrency tests in `Ago.Chat.Concurrency.Tests`: a transfer racing the assignment engine, two
  transfers of the same conversation, and a transfer to an operator who reaches capacity in between.

## Out of scope

- Transferring to a *team* or a queue rather than a named operator. Different concept, and nothing
  asks for it.
- Transfer across sites. `17-01`'s boundary, and it should be impossible rather than merely refused.
- Any change to how automatic assignment picks an operator (`4-02`).

## Done when

- [ ] A conversation moves between two operators with capacity correct on both sides afterwards.
- [ ] A transfer to a full operator is refused visibly.
- [ ] Concurrency tests cover the race against the assignment engine and the double transfer, and pass
      repeatedly rather than usually.
- [ ] What the visitor sees is a stated decision.

## Open questions

None. What the visitor is shown is this item's own call, provided it is recorded.
