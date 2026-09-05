# an operator can take a waiting conversation, and the system records that they chose to

- **Stage**: 23
- **Status**: done (2026-09-05), `ago-chat#179`, `ago-console#112`, `adr/0105`. The schema gap
  this item found — `23-03`’s CHECK constraint not admitting `Taken` — was closed by a second
  migration once `23-02` released the wave’s slot, and closing it exposed a unique-index race the
  constraint failure had been masking.
- **Depends on**: `23-03` — the interval store and its `source` column; this item adds the `Taken`
  value and a fifth writer
- **Decision**: `docs/design/decisions.md` §2, first three bullets

## Goal

An operator looking at a waiting conversation can take it, deliberately, and the system records that
this is what happened. Today `Waiting` conversations are visible in three places and actionable in
none (`ui-inventory.md` §13.13): the rail's Waiting section is `.ago-list__row--static` with a note
saying conversations "are assigned automatically, never claimed here"; `/admin` rows are not links;
`/search` tells the reader to "assign it from the queue", which has no assign action.

The mechanism is half-built and mis-wired rather than absent. `OperatorHub.JoinConversationAsync`
already calls `AssignConversationHandler` on every join, so navigating to `/conversations/{id}` of a
`Waiting` conversation *does* assign it — with `holdsCapacityClaim: false`, because `adr/0033`
deliberately preserved that asymmetry and filed its reversal as follow-up. Nothing links there, so
the path exists and cannot be reached.

After this: a take is a real, reachable act, and it **increments `active_chats` without checking it**.

## Why the counter rises past capacity

§2's model, and it is the author's: capacity's meaning is now exactly *how many the system will hand
you without asking*. A manual claim that did not increment would leave the eager operator looking
freest to `SkipLockedAssignmentClaimer`'s least-active-first ordering, so they would keep receiving
automatic assignments on top of what they took — double-loaded by their own initiative.

## Context to read first

- `docs/design/decisions.md` §2 in full
- `docs/design/flows.md` 2.1; `docs/design/ui-inventory.md` §3.1, §4.1, §4.2, §13.13
- `docs/architecture/concurrency.md` — "Operator assignment: the contended path"
- `docs/adr/0033-*` — the asymmetry this item reverses — and `docs/backlog/6-09`, `6-10`
- `Ago.Chat.Domain/Conversation.cs`'s `AssignTo` remarks on `holdsCapacityClaim`, and
  `Ago.Chat.Application/Abstractions/IOperatorCapacity.cs`, whose own doc comment states why the
  claim is one `UPDATE ... WHERE active_chats < capacity` rather than an aggregate load

## Scope

- `IOperatorCapacity` gains a second write — a compare-free increment
  (`UPDATE operators SET active_chats = active_chats + 1 WHERE id = @id`) beside the existing
  `TryClaimAsync`. **Two methods, not a boolean parameter**: one of them can fail and the other
  cannot, and a caller must not be able to confuse them.
- `AssignConversationHandler` takes the increment in the same transaction as the save and passes
  `holdsCapacityClaim: true`, so `CloseConversationHandler`'s release stays exact (`6-09`).
  `Conversation.AssignTo`'s same-operator reconnect no-op returns *before* touching the flag — a
  reconnect must not increment a second time; assert it.
- **A reachable act**: `POST /api/v1/conversations/{conversationId}/claim`, beside the hub, so
  `/admin` and `/search` can offer it without opening a hub connection first. It dispatches the same
  `AssignConversationHandler` and is gated on the same `Permission.ConversationAssign` that handler
  already checks, with the same belongs-to-site guard (`17-01`) it already carries.
- `source = Taken` on the interval `23-03` opens for this path.
- `ago-console`: the rail's Waiting rows and `/search`'s `Waiting` rows become actionable, and the
  three notes that currently say claiming is impossible are corrected — including `/`'s empty-state
  paragraph, which says in words that "nothing here needs claiming".
- **An ADR** (number to be assigned) recording that capacity now gates the auto-assigner only,
  superseding `adr/0033`'s asymmetry rather than adjusting it, and stating plainly that
  `active_chats` may legitimately exceed `capacity` — because every existing reader of that pair was
  written when it could not.

## Out of scope

- The penalty period and the assignment nobody chose — `23-05`, which adds the fourth `source` value.
- Changing `capacity` from a constant. §2 records that it is an `int` nothing recomputes and no
  screen changes; making it editable is a separate want nobody has asked for.
- Any weighting of the recorded provenance into a judgement. §2: **the product counts.**
- The word "forced" appearing anywhere a person can read it (`23-03`'s naming note).

## Done when

- [x] An operator takes a `Waiting` conversation from the rail and it becomes theirs.
- [x] A take when `active_chats >= capacity` succeeds and `active_chats` ends one higher — asserted,
      because this is the invariant the previous design forbade.
- [x] Closing a taken conversation releases exactly one slot (`6-09`'s existing test, extended).
- [x] A reconnect join of an already-held conversation does not increment — a concurrency test.
- [x] Two operators racing to take one conversation: one wins, the other gets
      `Conversation.InvalidState`, and `active_chats` rose by exactly one.
- [x] An operator of another tenant cannot claim by id — the `17-01` guard, asserted through the new
      route as well as through the hub.
- [x] Every interval opened by this path carries `Taken`; every interval opened by a claimer still
      carries `Assigned`.
- [x] `data-model.md`'s `operators` section and `concurrency.md`'s assignment section state the new
      rule; the ADR exists.

## Open questions

None.
