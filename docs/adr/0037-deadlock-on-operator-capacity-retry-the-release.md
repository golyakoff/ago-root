# ADR-0037: The capacity release absorbs the assignment engine's deadlock

- **Status**: Accepted
- **Date**: 2026-08-25
- **Stage**: 6 (`6-10`)

## Context

`ago-chat`'s CI went red twice on 2026-08-25 with `40P01: deadlock detected` raised from
`OperatorCapacityStore.ReleaseAsync`, on the close path, inside
`CloseConversationCapacityConcurrencyTests`. It never reproduced on the author's machine, and once it
blocked an unrelated security fix from merging. `6-10`'s backlog item deliberately refused to name a
mechanism until one was measured, because the obvious story — a `conversations`↔`operators` lock-order
inversion between the assignment engine and the close — does not close into a cycle when the
transaction boundaries are read carefully.

It was reproduced deliberately, and the obvious story is wrong. The full graphs are in
`docs/backlog/6-10-close-and-assign-deadlock-on-operator-capacity.md`; the shape is:

- **Every wait, in every captured graph, is on `operators`.** `relation 16396` resolves to `operators`
  against the live container, and it is the only relation oid that appears anywhere in the server log.
  `conversations` is not a participant.
- **Every participating statement is one of the two capacity statements** — `active_chats + 1` (claim)
  or `active_chats - 1` (release). Nothing else.
- The cycle mixes two edge kinds: `ShareLock on transaction N` (an ordinary wait for the row's current
  updater) and **`ExclusiveLock on tuple (x,y)`** — a *tuple lock*, the heavyweight token Postgres
  makes a would-be updater take to hold its place in the queue for one row before it waits on the
  current owner.

That last point is the whole answer. A single-row `UPDATE` in its own implicit transaction owns no row
lock while it waits — but it does own its place in the queue, and an assignment batch that already
holds a *different* `operators` row can queue behind it. The cycle then runs *through* a statement
that has no locks of its own to create it, and Postgres aborts whichever process ran the deadlock
check first, which is repeatedly the innocent release.

The root cycle is therefore not new and not `6-09`'s. It is the one `concurrency.md` and
`SkipLockedAssignmentClaimer` have documented since `4-02` and deliberately accepted: a batch holds
several `operators` row locks at once — one per operator it assigned to, held until the batch commits
— and `FindCandidateOperatorAsync` picks least-loaded-first, so which rows and in what order depends
on who had room at that instant. Two batches invert. That was fine while the only participants were
background ticks: `ConversationAssignmentJob` catches `40P01` per site, logs at `Debug`, and retries
next tick.

What `6-09` changed is **who else is standing in that queue**. Releasing capacity on close put a
user-facing HTTP request onto the same rows, on every close. The engine's accepted cost stopped being
paid only by a background loop.

## Decision

**The close's release absorbs the deadlock; the assignment engine is not changed.**

1. `OperatorCapacityStore.ReleaseAsync` retries its single statement on `40P01`, **bounded at 5
   attempts**, with a growing jittered delay (`Random 4–16 ms × attempt`).
2. It retries **only when it owns no caller transaction** (`db.Database.CurrentTransaction is null`).
   Inside a caller-owned transaction — `OperatorConversationReleaser`'s shape, `4-04` — the deadlock
   has already aborted the whole transaction and the next statement on it could only fail with
   `25P02 in_failed_sql_transaction`. There the retry unit is the caller's transaction, and its caller
   is a broker consumer whose delivery is redelivered.
3. A `40P01` that survives is translated to **`OperatorCapacityContentionException`**, declared in
   `Ago.Chat.Application.Abstractions` next to `IOperatorCapacity` — the same port-boundary
   translation `6-08` gave `ConversationConcurrencyConflictException`. Application never names Npgsql;
   an operator never sees `40P01`.
4. `CloseConversationHandler` catches it and **keeps the close successful**. The conversation *is*
   closed — the save committed before the release was ever attempted. It logs at `Warning` and
   counts `ago.chat.assignment.capacity_release_deadlocks{outcome="abandoned"}`.
5. `TryClaimAsync` gets no retry. Every call to it in production is inside a claimer's batch
   transaction, where 2 applies.

Retrying is correct here rather than merely expedient, and the graph is what establishes it: the
aborted transaction applied nothing, so a re-issued release is the first and only decrement of that
slot. There is no double-decrement to reason about.

### Why the bound is 5

The bound has to answer "how long may an operator's close wait for a slot that a disconnect sweep will
recover anyway?" Each further deadlock needs an *independent* coincidence — the release must again be
queued on a row while two batches are inverting on it — so attempts past the first few buy very little
and cost request latency directly. Five attempts with a growing jittered backoff spans roughly
40–160 ms of extra worst-case latency, and the jitter is there because a detected cycle usually has
several releases queued on the same row: re-issuing them in lockstep is how the next cycle gets built.

The bound is not asserted, it is checked. `ClosesStormingAssignmentBatches_
NeverSurfaceADeadlockAndNeverCorruptTheCount` asserts the exact invariant — `active_chats` equals the
claims actually held — under sustained contention, and an abandoned release breaks that invariant. If
5 turns out to be too few, the storm test goes red rather than the number quietly being wrong. A
representative post-fix run: 607 closes, 0 escaped exceptions, 63 server-side deadlocks of which 3
picked the release as the victim, every operator's count exact.

## Consequences

- **An operator never sees a Postgres error for pressing "close".** That was the item's hard
  requirement and it is met at the port boundary, not by a catch-all in the host.
- **The residual is unchanged from `6-09`, not new.** A release abandoned after 5 attempts leaks
  exactly one slot — the same outcome as a process death in that window, inert afterwards, recovered
  when the operator next goes offline. It is now *visible*: a Warning log naming the conversation and
  the operator, and a counter with an `abandoned` tag. `6-09`'s original bug went unnoticed for a
  stage and a half because nothing counted it.
- **Failing the request instead was considered and is worse.** The close already happened; reporting
  it as failed would be untrue, and the retry it invites is rejected as already-closed without
  recovering the slot either.
- **The assignment engine keeps a known deadlock.** That is a deliberate deferral, recorded here so
  the next person does not think it was missed: batches still take several `operators` locks in
  load-dependent order, still deadlock against each other, and are still retried next tick. This ADR
  makes the close survive that; it does not remove it.
- **`adr/0033` is untouched.** The fork it decided — release after the commit, on the strength of a
  receipt — is not implicated by the graph. What puts the release in the cycle is its position in a
  tuple queue, not its transaction boundary.
- Retry logic now lives in an adapter that had none. Kept to one method, one constant and one guard,
  rather than reaching for a Polly pipeline: `resilience.md` already prescribes "retry only on
  transient errors" for Postgres, and a five-attempt loop around one idempotent statement does not
  need a policy engine to be legible.

## Alternatives considered

**Give both paths a consistent `operators` lock order.** The textbook fix, and the only one that
removes the cycle instead of surviving it. Rejected for this item because the close has no order to
get wrong — it takes exactly one row — so "consistent order" means changing the assignment engine, in
one of two ways, both larger than a defect fix:

- *Pre-lock every online operator of the site, in id order, at the start of each batch.* Correct, and
  it serialises assignment batches across replicas for that site, locking operators the batch never
  uses. That is a throughput claim in the direction of "worse", and this project does not merge
  performance changes without a load run behind them (`CLAUDE.md` rule 7).
- *Decide the whole batch in memory, then apply one grouped `active_chats + n` per operator in id
  order.* A genuinely nicer engine — fewer statements, deterministic order, same atomicity — and a
  redesign of a path proven under load in `4-02`/`4-03`, requiring `IOperatorCapacity` to grow a
  claim-many operation and both claimer implementations plus the disconnect sweep to be re-reasoned.

Either is the right *root* fix. Neither is the right thing to merge into a concurrency path while
`main` is red. Left as a follow-up item, with the measurement it needs.

**Move the release inside the conversation's transaction.** Rejected twice over. `adr/0033`'s original
objection stands untouched: a release ahead of a save that then loses on `xmin` leaves the
conversation assigned with its slot handed back, and the operator over-subscribable for the rest of
that slot's life. The captured graph adds a second and, here, decisive objection: a deadlock aborts a
whole transaction, so a release folded into the conversation's transaction could not be retried at all
— the close would die with it. Today's worst case costs one slot; that version's worst case costs the
operator's action.

**`SELECT ... FOR NO KEY UPDATE NOWAIT` before the decrement, retrying on `55P03`.** Structurally
eliminates the release's participation: with `NOWAIT` it never joins the queue, so it never holds the
tuple-lock token the cycle runs through. Rejected because it converts every *ordinary* contended
release — frequent, harmless, and correctly resolved by waiting — into a spin, and invites starvation
under exactly the load where the release matters most. Blocking is the right primitive; only the rare
cycle is the problem, and only the rare cycle is treated.

**Catch `40P01` in the API host and map it to a 409.** Would stop the raw error reaching an operator
with no adapter change. Rejected: it reports a close that succeeded as a conflict, teaches the host to
know Postgres SQLSTATEs, and leaves the slot leaked with nothing counting it.

**Declare the test flaky and re-run CI.** Explicitly ruled out by `6-10` before the investigation
started, and the evidence confirms the ruling: a real deadlock, in product code, on a path an operator
triggers. Retrying until green would have hidden a defect and taught the habit of re-running a red
concurrency suite.
