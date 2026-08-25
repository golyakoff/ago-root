# Fix: closing a conversation deadlocks against the assignment engine on `operators`

- **Stage**: 6
- **Status**: done (2026-08-25)
- **Depends on**: nothing. Caused by `6-09-release-operator-capacity-on-close.md`, which is merged;
  `test/deadlock-detail-in-concurrency-fixture` (`ago-chat#64`) is the diagnostic that makes the next
  occurrence readable and should land first, but does not block starting.

## Goal

Closing a conversation stops being able to fail with `40P01: deadlock detected`. Whichever of the two
transactions loses, it loses *predictably* — either the ordering makes the cycle impossible, or the
loser retries and succeeds — rather than surfacing a Postgres deadlock to an operator who pressed
"close".

## How this was found

CI, twice on 2026-08-25, both times inside `OperatorCapacityStore.ReleaseAsync` called from
`CloseConversationHandler.CloseAndSaveAsync`:

- `ago-chat` run `32836321771` on **`main`**, in
  `CloseConversationCapacityConcurrencyTests.ClosesRacingAssignments_NeverCorruptTheCount`.
- `ago-chat` run `32844814076` on the `17-01` branch — which touches none of the code involved. A
  security fix sat blocked behind it, which is worth recording: this defect's first visible cost was
  to something unrelated.
- A third time, `ago-chat` run `32849094527`, this one *after* `ago-chat#64` landed — the first
  occurrence to carry a readable `DETAIL`:
  `Process 99 waits for ExclusiveLock on tuple (0,36) of relation 16396 of database 5; blocked by
  process 91`, with process 99's stack running `OperatorCapacityStore.ReleaseAsync` ←
  `CloseConversationHandler.CloseAndSaveAsync`. `ExclusiveLock on a **tuple**`, not a transaction id,
  is the tell, and it matches the local reproduction below exactly, down to the relation oid.

It does **not** reproduce locally: six consecutive runs of the failing test are green on the author's
machine. It needs the contention of a loaded runner, which is exactly the class of defect a
concurrency suite exists to catch and exactly the class that gets dismissed as a flake.

**It is not a flaky test.** The test asserts a real invariant and the failure is a real Postgres
deadlock in product code. Calling it flaky and retrying until green would be the wrong answer twice
over: it would hide a defect *and* teach the habit of re-running a red concurrency suite.

## Why `6-09` made this appear

Before `6-09`, `IOperatorCapacity.ReleaseAsync` had exactly one caller — `4-04`'s disconnect sweep,
which runs rarely and never concurrently with a close of the same conversation. `6-09` put it on the
ordinary close path, so every conversation close now takes an `operators` row lock while the
assignment engine is doing the same thing on a tick. The defect is in the interaction, not in `6-09`'s
own reasoning, which was reviewed and is sound on its own terms.

## What is known, and what is not

Known:

- The failing statement is `ReleaseAsync`'s single-row
  `UPDATE operators SET active_chats = active_chats - 1 WHERE id = ... AND active_chats > 0`.
- `SkipLockedAssignmentClaimer` runs one transaction that holds a **batch** of `conversations` row
  locks (`WaitingConversationClaimQuery.ClaimBatchAsync`, `SELECT ... FOR UPDATE SKIP LOCKED`) and
  acquires `operators` locks inside that window, one per candidate, before writing the conversations
  back.
- `CloseConversationHandler` writes the conversation and its outbox row in one `SaveChangesAsync`
  (EF's implicit transaction, committed), and *then* calls `ReleaseAsync` in a separate statement.

**Not known, and this item must not guess it**: what the second waiter actually is. A single-row
`UPDATE` in its own transaction cannot deadlock unless the transaction holds something else, and
reading the boundaries above does not close a cycle on its own. The obvious inverted-order story is
plausible and unproven, and a plausible-sounding wrong fix merged into a concurrency path is worse
than the defect.

## What it turned out to be — the captured graph

Reproduced deliberately, locally, on 2026-08-25, and the answer is **not** the inverted
`conversations`↔`operators` order the section above refused to assume. Every wait in every captured
graph is on `operators` alone, and every participating statement is one of the two capacity
statements. `conversations` never appears.

**How it was forced.** `ConcurrencyTestFixture`'s Postgres container was given
`-c deadlock_timeout=10ms -c log_lock_waits=on` — which does not create deadlocks, only makes
Postgres look for a cycle sooner — and the round-based test above was replaced, for the
reproduction, by a *sustained* storm: 8 `SkipLockedAssignmentClaimer` loops (batch 120) and 24
close loops running continuously against 3 operators × capacity 5, over 4000 conversations, for 40 s.
Against pre-fix code that produced 92 server-side deadlock reports, of which 5 picked the close's
release as the victim — the CI failure, on demand, in under a minute. Six *round-based* runs stayed
green the whole time, which is exactly why the original report could not be reproduced.

**`relation 16396` is `operators`**, resolved against the live container rather than inferred:
`SELECT relname FROM pg_class WHERE oid = 16396` → `operators`. The oid matches CI's byte for byte
because both are a fresh container built by the same migration sequence. Scanning the whole server
log for `of relation (\d+) of database`, **`16396` is the only oid that ever appears**.

The complete report, from the Postgres server log, verbatim (four participants, one tuple):

```
2026-08-25 12:46:42.517 UTC [108] ERROR:  deadlock detected
2026-08-25 12:46:42.517 UTC [108] DETAIL:  Process 108 waits for ExclusiveLock on tuple (1,87) of relation 16396 of database 5; blocked by process 117.
	Process 117 waits for ShareLock on transaction 1249; blocked by process 101.
	Process 101 waits for ShareLock on transaction 1288; blocked by process 106.
	Process 106 waits for ExclusiveLock on tuple (1,87) of relation 16396 of database 5; blocked by process 108.
	Process 108: UPDATE operators
	SET active_chats = active_chats - 1
	WHERE id = $1 AND active_chats > 0
	Process 117: UPDATE operators
	SET active_chats = active_chats - 1
	WHERE id = $1 AND active_chats > 0
	Process 101: UPDATE operators
	SET active_chats = active_chats + 1
	WHERE id = $1 AND active_chats < capacity
	Process 106: UPDATE operators
	SET active_chats = active_chats + 1
	WHERE id = $1 AND active_chats < capacity
2026-08-25 12:46:42.517 UTC [108] HINT:  See server log for query details.
2026-08-25 12:46:42.517 UTC [108] STATEMENT:  UPDATE operators
	SET active_chats = active_chats - 1
	WHERE id = $1 AND active_chats > 0
```

A second one, where the release is the process the whole cycle hangs off:

```
2026-08-25 12:46:41.442 UTC [91] ERROR:  deadlock detected
2026-08-25 12:46:41.442 UTC [91] DETAIL:  Process 91 waits for ExclusiveLock on tuple (1,24) of relation 16396 of database 5; blocked by process 90.
	Process 90 waits for ShareLock on transaction 1152; blocked by process 99.
	Process 99 waits for ShareLock on transaction 1161; blocked by process 113.
	Process 113 waits for ExclusiveLock on tuple (1,24) of relation 16396 of database 5; blocked by process 91.
	Process 91: UPDATE operators
	SET active_chats = active_chats - 1
	WHERE id = $1 AND active_chats > 0
	Process 90: UPDATE operators
	SET active_chats = active_chats - 1
	WHERE id = $1 AND active_chats > 0
	Process 99: UPDATE operators
	SET active_chats = active_chats + 1
	WHERE id = $1 AND active_chats < capacity
	Process 113: UPDATE operators
	SET active_chats = active_chats + 1
	WHERE id = $1 AND active_chats < capacity
```

And the same shape as raised to the .NET caller, `Include Error Detail` doing the job `ago-chat#64`
added it for — a further local occurrence, three participants, and the closest match to what CI
printed in run `32849094527`:

```
SqlState : 40P01
Message  : deadlock detected
Detail   : Process 90 waits for ShareLock on transaction 762; blocked by process 87.
Process 87 waits for ShareLock on transaction 1051; blocked by process 100.
Process 100 waits for ExclusiveLock on tuple (3,1) of relation 16396 of database 5; blocked by process 90.
Where    : while updating tuple (3,1) in relation "operators"
Routine  : DeadLockReport
```

### What that means, mechanically

The item was right to say a single-row `UPDATE` in its own transaction holds nothing — and it is
still in the cycle, because it holds something that is not a row lock. **Before a statement waits
for the transaction that currently owns a row version, it takes a heavyweight *tuple lock*
(`LockTuple`, ExclusiveMode) on that tuple as its place in the queue** — Postgres's own FIFO for
would-be updaters of one row. While the release holds that place, an assignment batch that already
holds a *different* `operators` row can queue behind it. The cycle then runs *through* a statement
that owns nothing, and Postgres aborts whichever process ran the deadlock check first — which can be,
and repeatedly is, the innocent single-statement release. The `ExclusiveLock on tuple` lines above are
that queue token; the `ShareLock on transaction` lines are ordinary "wait for the current updater".

So the *root* cycle is the one `concurrency.md` and `SkipLockedAssignmentClaimer` have documented
since `4-02` and deliberately accepted: **a batch holds several `operators` row locks at once** (one
per operator it assigned to, held until the batch commits), and two batches taking the same rows in a
different order deadlock. `FindCandidateOperatorAsync` picks least-loaded-first, so which rows, and in
which order, depends on who had room at that instant — the order genuinely varies between batches.

What `6-09` changed is not the cycle. It is **who is standing in the queue when it forms**. Before
`6-09` the only participants were background ticks, and `ConversationAssignmentJob` had caught
`40P01` per site and retried next tick since `4-02` — nobody was waiting on the answer. After `6-09`,
every conversation close queues on the same rows, and the victim Postgres picks may be an operator's
HTTP request.

**This leaves `adr/0033` untouched rather than needing an answer.** The fork it decided — release
*after* the commit, on the strength of a receipt — is not implicated: the release's transaction
boundary is not what puts it in the cycle, its position in a tuple queue is. Moving the release
*inside* the conversation's transaction would make things strictly worse, and the graph is what says
so: a transaction is the retry unit for a deadlock, and a release folded into the conversation's
transaction would take the close down with it instead of costing one slot. See `adr/0037`.

## Scope

- **Get the deadlock graph first.** `ago-chat#64` turns on `Include Error Detail` for the concurrency
  fixture, so the next occurrence prints which two transactions, which relations and which statements
  cycled. Consider also enabling `log_lock_waits` and `deadlock_timeout` logging on the test
  container, and capturing the Postgres log on failure — a CI run that fails and discards the
  server's own explanation costs another full cycle to learn nothing.
- **Reproduce it deliberately** rather than waiting for CI. A loaded runner is not magic: the same
  contention can be forced locally with more concurrent closers, a smaller `deadlock_timeout`, or an
  artificial delay between the close's save and its release. A defect that only appears on someone
  else's machine is one nobody can fix.
- **Then decide the fix on evidence.** Candidates, none pre-selected: a consistent lock order across
  both paths; taking the capacity release inside the same transaction as the conversation write
  (which `6-09` deliberately rejected, and reversing that needs `6-09`'s own argument answered, not
  ignored — an early release that then loses on `xmin` over-subscribes the operator); or retrying the
  release on `40P01`, which is legitimate for a deadlock but is a treatment, and should only be chosen
  knowingly.
- **Whatever is chosen, an operator must never see a raw Postgres error.** `6-08` established the
  shape for a conversation write that loses a concurrency race; a deadlock should reach the caller in
  that same vocabulary or not at all.

## Out of scope

- `6-09`'s design itself — the receipt, and releasing after the commit rather than before. That was
  argued in `adr/0033` and this item does not reopen it unless the evidence forces it, in which case
  the ADR gets a superseding entry rather than a silent change.
- The `FakeCrm` socket test (`Disappears_RefusesTheConnectionAtTheTransportLayer_ViaHttpClient`),
  which failed on the same CI run for an unrelated reason — an exception type that is not an exact
  match on a Linux runner. That is a genuinely separate, genuinely test-only problem and wants its own
  item; do not fold it in here to make one "flaky CI" bucket, because one of the two is a product
  defect and the other is not.

## The fix, and what was rejected

**Chosen: a bounded, jittered retry of the release, inside the adapter, plus a typed failure at the
port.** `OperatorCapacityStore.ReleaseAsync` retries its single statement up to 5 times when — and
only when — it owns no caller transaction, and translates a surviving `40P01` into
`OperatorCapacityContentionException` (`Ago.Chat.Application.Abstractions`, next to the port, the
same shape `6-08` gave `ConversationConcurrencyConflictException`). `CloseConversationHandler`
catches that, keeps the close successful — it committed — logs at Warning, and accepts one leaked
slot: the identical residual `6-09` already documents for a process death in that window, recovered
by `4-04`'s disconnect sweep. Counted as
`ago.chat.assignment.capacity_release_deadlocks{outcome="retried"|"abandoned"}`. `adr/0037` carries
the full argument, including why the bound is 5.

Retrying is legitimate here rather than merely convenient, and the graph is what makes it so: the
aborted transaction applied nothing, so a re-issued release is the first and only decrement of that
slot. It is a treatment for a cause that is *deliberately* accepted upstream, not for one nobody
looked at.

Rejected, with reasons — the long form is in `adr/0037`:

- **A consistent lock order across both paths.** There is no order for the close to get wrong: it
  takes exactly one `operators` row. Imposing one means changing the *assignment engine* — either
  pre-locking every online operator of a site per batch (which serialises assignment across replicas,
  an unmeasured throughput regression this project's own rule 7 forbids asserting without numbers) or
  restructuring `4-02`'s batch to decide in memory and apply one grouped update per operator in id
  order. That is the real root fix and it is a redesign, not a defect fix. Left as a follow-up.
- **Moving the release inside the conversation's transaction.** Worse in both directions, and now
  provably so. `adr/0033`'s original objection stands untouched (a release that then loses on `xmin`
  over-subscribes the operator), and the graph adds a second: a deadlock aborts a whole transaction,
  so the release could no longer be retried at all, and the close would fail with it. Today's cost is
  one slot; that version's cost is the operator's action.
- **`SELECT ... FOR NO KEY UPDATE NOWAIT` before the decrement.** Would make the release structurally
  incapable of joining the cycle — it would never hold a tuple-lock queue token. It also turns every
  *ordinary* contended release, which is frequent and harmless, into a spin. Blocking is the right
  primitive; only the rare cycle is the problem.
- **Calling it a flaky test and retrying CI.** The item already ruled this out and the evidence
  confirms it: the failure is a real Postgres deadlock in product code, on a path an operator
  triggers.

## Done when

- [x] The deadlock is reproduced deliberately, locally or in a controlled run, with the actual
      Postgres `DETAIL` graph captured and written into this item — not inferred. Above, verbatim,
      including the four-participant server-side report and the resolved `relation 16396 → operators`.
- [x] The chosen fix is stated with the alternatives that were rejected and why, per this project's
      standing rule that an architectural decision is never applied silently. Above, and `adr/0037`.
- [x] `ClosesRacingAssignments_NeverCorruptTheCount` and the rest of
      `Ago.Chat.Concurrency.Tests` pass repeatedly under the contention that produced the failure, not
      once. The contention is now *in* the suite: `ConcurrencyTestFixture` runs its Postgres with
      `deadlock_timeout=10ms` and `log_lock_waits=on` permanently, and
      `ClosesStormingAssignmentBatches_NeverSurfaceADeadlockAndNeverCorruptTheCount` is a 15 s
      sustained storm that asserts three things — no close escapes with an exception, the exact
      claim/assignment invariant still holds, and **Postgres really did detect deadlocks during the
      run**, read back out of the container's own log, so a quiet run cannot pass vacuously.
- [x] If the fix is a retry, the retry is bounded and the bound is argued; if it is a lock order, the
      order is written down where both call sites can see it. Bounded at 5, argued in `adr/0037`; the
      bound being too small would show up as a broken invariant in the storm test, not as silence.
- [x] `docs/architecture/concurrency.md` says which lock order the assignment and close paths take.

## Verified

Three levels, because the three claims are provable at three different levels:

- **Deterministic, Application** — `CloseConversationHandlerTests
  .HandleAsync_WhenTheCapacityReleaseLosesToContention_StillReportsTheCloseAsSuccessful`: the policy,
  with no database involved. A contended release does not turn a committed close into a failed request.
- **Deterministic, real Postgres** — `OperatorCapacityStoreTests
  .ReleaseAsync_WhenADeadlockAbortsACallerOwnedTransaction_SurfacesTheContentionType_NeverANpgsqlError`:
  a genuine `40P01`, arranged rather than waited for. Two transactions take two `operators` rows in
  opposite order; the victim is *pinned* by giving the releasing session `deadlock_timeout=10ms` and
  the other `30s`, so the process that checks first — and therefore aborts — is always the release.
  Asserts the caller gets `OperatorCapacityContentionException` and never a `PostgresException`, with
  `Attempts == 1` because inside a caller-owned transaction there is no retry to make.
- **Under real contention** — the storm test above, run repeatedly rather than once, which is what
  the Done-when asks for. Four consecutive full runs of `Ago.Chat.Concurrency.Tests` (29/29 each):

  | run | closes | escaped exceptions | server-side deadlocks | of those, victim = the release |
  |---|---|---|---|---|
  | 1 | 607 | 0 | 63 | 3 |
  | 2 | 622 | 0 | 96 | 4 |
  | 3 | 627 | 0 | 66 | 7 |
  | 4 | 690 | 0 | 72 | 4 |

  Every run's exact invariant held for every operator. The middle column is the defect; the right-hand
  column is the proof the contention that caused it was present and absorbed rather than avoided.

Full suite after the change: `Ago.Chat.Domain.Tests` 99, `Ago.Chat.Architecture.Tests` 17,
`Ago.Chat.Application.Tests` 195, `Ago.Chat.FakeCrm.Tests` 21, `Ago.Chat.Concurrency.Tests` 29,
`Ago.Chat.Integration.Tests` 198 — 559, from 556, the three added being the three levels above.
`dotnet format --verify-no-changes` clean, Release build 0 warnings.

## Found in passing, deliberately not folded in

Two closes of the *same* conversation, concurrently, fail with
`23505 duplicate key value violates unique constraint "PK_outbox"` rather than a clean `409`:
`ConversationClosedMapper` uses the conversation's own id as the envelope's `MessageId`
(correct — close happens once per conversation), so the loser of the race collides on the outbox
primary key inside the same `SaveChangesAsync` that would otherwise have lost on `xmin`, and the
`23505` reaches `6-08`'s retry wrapper as a `DbUpdateException` it does not recognise. Reproduced
incidentally while building the storm harness, which is why the harness now gives each conversation
to at most one closer. Pre-existing, unrelated to capacity, and its own item — exactly like the
`FakeCrm` socket test this one already refused to bundle.

## Open questions

~~**What actually cycles.**~~ — answered above, with the graph.

**Whether the assignment engine should stop taking several `operators` locks per batch at all.** That
is the root fix this item deliberately did not take, and it needs load numbers rather than an
argument. Its own item.
