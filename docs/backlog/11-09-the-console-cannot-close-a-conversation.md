# The console cannot close a conversation, and closing is what releases capacity

- **Stage**: 11
- **Status**: ready
- **Found by**: `18-05`, while deciding what its "close" shortcut should be bound to. The shortcut
  question turned out to be unanswerable because the action does not exist in the console at all.

## The gap

`6-02` shipped `POST /api/v1/conversations/{id}/close` and `Permission.ConversationClose` in Stage 6.
`6-09` then made closing **release the operator's capacity** — the mechanism `4-02`'s assignment
engine depends on to keep handing work out.

**`ago-console` has no close button, no menu item, and no API-client call.** The whole console was
searched to establish this, not sampled. So an operator can be assigned conversations and can never
finish one, and the capacity a closed conversation would return is never returned in practice.

This is not a missing nicety. It is a shipped, tested, permission-gated server capability with no
way for the person it was built for to invoke it, and it silently constrains the engine that the
whole of Stage 4 exists to make correct.

## Why `18-05` did not simply add it

`18-05`'s scope says a shortcut for "close". A shortcut for a button that does not exist is not a
shortcut — it is a new product action wearing a keybinding, and it drags in things a shortcuts item
has no business deciding: a confirmation, the permission gate, and `6-08`'s concurrency-conflict path
when two operators act on the same conversation. So `18-05` bound `Esc` to closing the open *thread*
(returning to the list) and said so in its own header, leaving this item to add the real action.

## Scope

- The close action in the operator workspace, gated on `Permission.ConversationClose` — hidden rather
  than merely disabled for an operator who does not hold it, matching how the console treats every
  other permission-gated control.
- A confirmation. Closing is not reversible from this screen, and it returns a visitor to the queue's
  view of the world.
- **`6-08`'s conflict path surfaced honestly**: when the conversation has already been closed or
  reassigned underneath, the operator is told what happened, not shown a generic failure.
- The list and the open thread both reflect the new state without a reload — the same bar `11-06`
  set for every other state change.

## Out of scope

- Reopening a closed conversation. Nothing in the product spec asks for it, and it is a different
  decision about what a closed conversation *is*.
- Bulk close. One conversation, one action.
- Any change to `6-02`'s or `6-09`'s server behaviour. This item is the missing surface, not a
  revision of what it calls.

## Done when

- [ ] An operator holding `ConversationClose` can close an assigned conversation from the workspace,
      with a confirmation.
- [ ] An operator without the permission sees no control, proven by a test that fails if it is merely
      disabled.
- [ ] Closing releases capacity in practice, observed end to end rather than inferred from `6-09`'s
      own tests: the operator becomes eligible for a new assignment afterwards.
- [ ] A conversation closed or reassigned underneath produces a specific message, not a generic error.
