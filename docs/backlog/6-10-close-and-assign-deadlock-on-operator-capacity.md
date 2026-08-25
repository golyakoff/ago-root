# Fix: closing a conversation deadlocks against the assignment engine on `operators`

- **Stage**: 6
- **Status**: ready
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

## Done when

- [ ] The deadlock is reproduced deliberately, locally or in a controlled run, with the actual
      Postgres `DETAIL` graph captured and written into this item — not inferred.
- [ ] The chosen fix is stated with the alternatives that were rejected and why, per this project's
      standing rule that an architectural decision is never applied silently.
- [ ] `ClosesRacingAssignments_NeverCorruptTheCount` and the rest of
      `Ago.Chat.Concurrency.Tests` pass repeatedly under the contention that produced the failure, not
      once.
- [ ] If the fix is a retry, the retry is bounded and the bound is argued; if it is a lock order, the
      order is written down where both call sites can see it, because an ordering convention nobody
      records is one the next handler breaks.
- [ ] `docs/architecture/concurrency.md` says which lock order the assignment and close paths take,
      whichever way this lands.

## Open questions

**What actually cycles.** That is the whole content of this item, and it is answerable with the
diagnostic already prepared rather than by reasoning from the source.
