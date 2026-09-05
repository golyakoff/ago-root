# ADR-0105: Capacity gates the auto-assigner only; a deliberate take charges it uncompared

- **Status**: Accepted — supersedes ADR-0033's "manual assignment stays capacity-blind" consequence
- **Date**: 2026-09-05
- **Stage**: 23 (`23-04`)

## Context

ADR-0033 gave `Conversation.HoldsCapacityClaim` its reasoning and, in its own Consequences, recorded a
known asymmetry as deliberate and out of scope: the automatic assignment engine claims a real
`operators.active_chats` slot before assigning (`TryClaimAsync`, `WHERE active_chats < capacity`), and
an operator picking up a `Waiting` conversation by hand through `AssignConversationHandler` — behind
`OperatorHub.JoinConversationAsync` — claimed nothing at all. That ADR filed the asymmetry's reversal
as follow-up rather than deciding it, on the ground that "making manual assignment claim is a product
decision... and it needs a transaction boundary the Application layer does not currently have."

Two things changed since. `18-02` gave the Application layer exactly that transaction boundary
(`IUnitOfWork`, for `TransferConversationHandler`'s own two-row capacity move) — the missing
prerequisite ADR-0033 named is no longer missing. And `23-04`'s own Goal made the product question
unavoidable rather than optional: `OperatorHub.JoinConversationAsync` already called
`AssignConversationHandler` on every join, including of a `Waiting` conversation, with
`holdsCapacityClaim: false` — the by-hand claim existed in code and had simply never been reachable,
because nothing in `ago-console` linked to it. The moment a link is added (this item's own Scope: the
rail, `/admin`, `/search`), the dormant path becomes the product's first read-write channel a person
can drive without going through capacity at all, and the author had to decide, for real, what a
deliberate take should cost.

The author's own answer (`decisions.md` §2, decided 2026-09-04): **capacity's meaning is now exactly
"how many the system will hand you without asking."** An operator who explicitly reaches into the
waiting list and takes one is not the case that model constrains. Left uncharged, that operator would
also keep looking least-loaded to `SkipLockedAssignmentClaimer`'s own least-active-first ordering, so
they would receive automatic assignments on top of what they took by choice — double-loaded by their
own initiative, the opposite of what a capacity ceiling is supposed to prevent.

## Decision

**A deliberate take charges capacity, unconditionally, and never compares it.**

1. `IOperatorCapacity` gains `ClaimAsync(operatorId, ct)` beside the existing `TryClaimAsync` —
   `UPDATE operators SET active_chats = active_chats + 1 WHERE id = @id`, no `capacity` comparison at
   all. Two methods, not a boolean parameter: one can fail (a normal, expected outcome every caller of
   `TryClaimAsync` already handles) and the other cannot, and a shared method keyed by a flag would let
   a caller pass the wrong one and silently receive the wrong guarantee.
2. `AssignConversationHandler` calls `ClaimAsync` for every real transition (`Conversation.AssignTo`
   actually raising `ConversationAssigned` — never for the same-operator reconnect no-op `3-03`
   established), inside its own explicit `IUnitOfWork` transaction alongside the interval open and the
   conversation's own save. `active_chats` may end above `capacity` after this call, and that is the
   intended state — not the leak ADR-0033's release-after-commit residual names, and not a bug for a
   future reader to "fix" back into `TryClaimAsync`'s shape.
3. Every real transition through `AssignConversationHandler` now opens its interval with
   `ConversationAssignmentSource.Taken` (`23-03`'s own placeholder, given its first real writer),
   never `Assigned` — the value it wrote for the whole window in which the path existed but had no
   reachable UI.
4. A reachable act now exists on both entry points that were previously undiscoverable or absent:
   `OperatorHub.JoinConversationAsync` (now linked from the console rail) and a new
   `POST /api/v1/conversations/{conversationId}/claim`, for `/admin` and `/search`, which do not hold a
   hub connection. Both dispatch the identical handler, so both get the identical guarantee.

This directly reverses ADR-0033's second Consequence bullet ("Manual assignment stays capacity-blind,
deliberately and now consistently... it is not this one's to fix"). It does **not** reverse
ADR-0033's actual Decision — the receipt (`HoldsCapacityClaim`), the release-after-commit ordering, the
`xmin`-arbitrated idempotency — all of which this item leaves untouched and depends on.

## Consequences

- **`active_chats` is no longer bounded by `capacity`.** Every existing reader of that pair —
  `SkipLockedAssignmentClaimer`'s candidate selection, any future report — was written when it could
  not be exceeded. None of them break (the engine's own `WHERE active_chats < capacity` still excludes
  an over-subscribed operator from new automatic work, which is the entire point), but a reader that
  silently assumed the bound could be wrong to assume it from here on.
- **A third writer of `operators` is now a caller-owned-transaction participant in `adr/0037`'s
  accepted, data-dependent deadlock cycle.** `AssignConversationHandler` follows the same rule
  `TransferConversationHandler` already established: own the retry at the transaction level (5
  attempts, the identical jittered backoff), rather than push it into the store. The bound is reused,
  not re-measured for this caller — no fresh load-test run backs "5 is enough" for this specific
  handler's own contention shape; see the item's commit-prep report.
- **The race between two operators taking the same conversation resolves through either of two real
  Postgres guards, not `xmin` alone** — found live, not anticipated. The two claims land on two
  different `operators` rows (nothing for them to contend with each other over there), but the two
  staged interval-open rows both target the *same* `conversation_id`, and `23-03`'s own partial unique
  index (`ix_conversation_assignments_open`) can reject the loser before its `SaveAsync` ever reaches
  the conversation row's own `xmin` check — EF executes an Added entity (the new interval) before a
  Modified one (the conversation) within one `SaveChangesAsync`. `ConversationRepository.SaveAsync`
  originally translated only the `xmin` shape (`DbUpdateConcurrencyException`); the unique-index shape
  reached the handler's retry loop as a raw, untranslated `DbUpdateException` and escaped as an
  unhandled exception rather than `Conversation.InvalidState`. Fixed with a second, narrowly-scoped
  catch on the one named constraint, translated identically. Either way the loser's whole transaction —
  claim included — rolls back with it.
- **A schema gap this item found, reported, then closed itself once unblocked.** `23-03`'s own
  migration constrained `conversation_assignments.source` with a Postgres `CHECK (source IN
  ('Assigned', 'Transferred'))`, deliberately not widened in advance. This item's first pass gave
  `Taken` its first real C# writer with the wave's one EF-migration slot held elsewhere, so it stopped
  and reported rather than adding a second migration — every write of a `Taken` interval failed with
  `23514` until the concurrent item merged and freed the slot. Migration
  `Stage23WidenConversationAssignmentSourceCheckConstraint` then widened the one constraint to `CHECK
  (source IN ('Assigned', 'Transferred', 'Taken'))` and nothing else — a one-line model-snapshot diff,
  touching no column or constraint the concurrent migration created. `data-model.md`'s
  `conversation_assignments` bullet and `concurrency.md`'s own "Shipped in `23-04`" section carry the
  full account of both this gap and the unique-index race the previous bullet describes, which the
  `CHECK` constraint had been masking until it was widened.

## Alternatives considered

**Leave the asymmetry exactly as ADR-0033 recorded it, and gate the new reachable act behind the same
`TryClaimAsync` the engine uses — refuse a take when the operator is already at capacity.** The
cleanest read of "capacity" as a hard ceiling. Rejected because it is not the product the author
described in `decisions.md` §2: an operator who sees a waiting customer and chooses to take them
anyway is exactly the case a ceiling should not stop, and refusing it would make the rail's own new
link lie about what clicking it does. `23-04`'s Goal is explicit that this reachable act increments
*without checking* — a refusal is the one outcome the item rules out by name.

**Charge capacity only past the penalty period (`23-05`'s `Additional` source), leaving an ordinary
deliberate take uncharged like today.** Keeps the counter meaning simpler — "assigned by the system,
one way or another" — at the cost of resurrecting exactly the double-loading ADR-0033's own follow-up
note warned about: an operator who takes conversations by hand still reads as idle to the
least-active-first engine. Rejected on the same "product counts, and the counter has to mean the
tenant's actual load" reasoning `decisions.md` §2 gives in full.

**Fold the new `ClaimAsync` into `TryClaimAsync` via a `bool checkCapacity` parameter**, avoiding a
second method on `IOperatorCapacity`. Rejected: the two calls have genuinely different failure
contracts — one returns whether it succeeded, the other cannot fail short of a real error — and a
shared method keyed by a boolean is exactly the shape that lets a caller pass the wrong flag and
silently get the wrong guarantee, the failure mode `IOperatorCapacity`'s own remarks already warn
against for the existing pair.

**Add the migration widening `ck_conversation_assignments_source` in the same change this item's own
handler code shipped in.** Rejected for the wave this item actually ran in: `23-04` had exactly one
EF-migration slot in `ago-chat` and a concurrent item (`23-02`) already held it, so two migrations
racing to be "the next one" in the same wave was the exact failure CLAUDE.md's multi-worker rules
exist to prevent. Reported as a blocking follow-up instead of worked around — and that is what
happened: once `23-02` merged, the same session added
`Stage23WidenConversationAssignmentSourceCheckConstraint` as its own, later, uncontended migration,
which is a correct sequencing this alternative's own rejection reasoning predicted rather than a
reversal of it.
