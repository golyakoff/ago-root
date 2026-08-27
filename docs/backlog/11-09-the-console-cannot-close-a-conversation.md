# The console cannot close a conversation, and closing is what releases capacity

- **Stage**: 11
- **Status**: done, except the capacity-release observation — which needs a running system and a
  signed-in operator, and is the author's to run. Stated precisely below rather than inferred from
  `6-09`'s own tests.
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

- [x] An operator holding `ConversationClose` can close an assigned conversation from the workspace,
      with a confirmation. `CloseConversationButton` in the conversation header, calling `6-02`'s
      endpoint through a new `closeConversation` in `api/conversationsApi.ts`. The confirmation is
      `11-05`'s `Dialog` — no twelfth component, `adr/0030`'s set stays closed at eleven.
- [x] An operator without the permission sees no control, proven by a test that fails if it is merely
      disabled. `CloseConversationButton.test.tsx`, and the test asserts three things rather than one:
      the button is absent, **no disabled control wears its label**, and the string does not appear in
      the subtree at all. Verified by inverting the component to render a `disabled` button — two
      tests fail.
- [ ] **Closing releases capacity in practice, observed end to end rather than inferred from `6-09`'s
      own tests: the operator becomes eligible for a new assignment afterwards. Not done, and not
      this session's to do.** It needs a running API, Worker and database plus a signed-in operator,
      and the console is behind a Keycloak password form an implementing session may not fill in —
      the same wall `11-06` and `18-05` both recorded. Adding `ago-chat` tests to get around it was
      explicitly out of lane, and would have proved the server again rather than the thing this
      clause asks about.

      The script, in the order it will break:
      1. Two operators signed in, both at `active_chats` below capacity, one conversation waiting.
      2. Operator A closes an assigned conversation from the workspace. The row leaves "Assigned to
         me" without a reload.
      3. `SELECT active_chats FROM operators WHERE id = <A>` — down by one.
      4. Within one assignment tick, the waiting conversation moves to A (or to B, if B was ahead in
         the engine's own ordering — `4-02` decides, and either outcome proves the release).
      5. Repeat with **`6-09`'s known residual**: kill the API between the close's commit and its
         capacity release and confirm exactly one slot leaks, recovered by the disconnect sweep. Not
         required by this item; worth doing once while the harness is set up.
- [x] A conversation closed or reassigned underneath produces a specific message, not a generic error.
      `closeOutcome.ts`, tested branch by branch and again through the component. See below — the
      "reassigned underneath" half is the one place this item had to infer rather than read.

## What this item found: the two `403`s that share one code

`CloseConversationHandler` returns `Conversation.Forbidden` for **two different situations**:

- the operator does not hold `conversation:close`;
- the operator is not assigned to this conversation — which is exactly what a reassignment underneath
  produces, and exactly the case this item's last Done-when names.

`api-design.md` says clients branch on `type` and never on the message, and there is one `type` here.
So **the console cannot read the difference off the wire.** What it does instead is use a fact it
already holds and the server does not send: whether this operator holds the permission at all. The
handler checks the permission *first* and the assignment *second*, so a `403` reaching an operator
who does hold `conversation:close` can only have come from the assignment check.

That inference is sound and it is still an inference, resting on a check order in another repository
that nothing in the console can enforce. **The honest fix is a distinct error code server-side** — an
`ago-chat` change, deliberately not made here, and worth its own small item. `workspace/closeOutcome.ts`
is the one place that would change when it lands.

The four failures and what an operator is told:

| Server | What happened | What the operator reads | Retry offered |
|---|---|---|---|
| `409 Conversation.InvalidState` | already closed | "This conversation has already been closed." | no |
| `409 Conversation.ConcurrencyConflict` | `6-08`'s lost race, after the server's own retry | "…Try closing it again." | **yes** |
| `403 Conversation.Forbidden` (holds the permission) | reassigned underneath | "…no longer assigned to you — someone else has taken it." | no |
| `403 Conversation.Forbidden` (does not) | permission revoked since sign-in | "You do not have permission…" | no |
| `404 Conversation.NotFound` | gone | "This conversation no longer exists." | no |

The two `409`s are the pair a status-code-only implementation merges, and merging them tells an
operator to retry something terminal or refuses to retry something transient.

## What the open thread does afterwards

**The composer goes; the transcript stays.** Navigating back to `/` on success was the obvious
alternative and is wrong for `11-06`'s own reason — the operator decides when to leave. What must not
survive is the reply box, because the server refuses every send to a closed conversation and a
composer that silently cannot work is worse than none.

The page carries a local `closed` flag rather than reading `conversation.state`, and that is forced
rather than chosen: a closed conversation leaves the operator queue entirely
(`GetAssignedToOperatorAsync` filters on `State == Assigned`), so the server's own view can only ever
say "no longer here" — which renders as a thread with no title and a live composer, the two things
the flag exists to prevent.
