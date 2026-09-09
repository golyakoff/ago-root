# 25-40 · A second probabilistic concurrency test flakes CI

- **Stage**: 25
- **Status**: done — `ago-chat#250`
- **Depends on**: nothing
- **Found**: 2026-09-09, live — `ago-chat`'s PR #249 (`23-89`, unrelated changes) failed CI on
  `CloseConversationCapacityConcurrencyTests.ClosesStormingAssignmentBatches_NeverSurfaceADeadlockAndNeverCorruptTheCount`.
  A rerun of the identical job passed.

## What is actually true

Same class of flake `25-36` already named and fixed for a different test
(`TransferConversationConcurrencyTests.TransferringRacesTheAssignmentEngine_NeverCorruptsCapacityOrDropsTheConversation`).
This one self-diagnoses the identical way: it asserts real Postgres deadlock reports occurred during
its own storm (`Assert.True(deadlockReports > 0, "the storm produced no Postgres deadlock at all, so
it proved nothing")`), and a quiet CI runner can fail to produce contention through timing variance
alone, unrelated to any regression in the commit under test — exactly what happened here.

## Scope

- `[Fact(Skip = "...")]` on the one test, with a reason naming why and how to run it deliberately —
  the identical shape `25-36` already used. Not a rewrite, not a deletion.

## Done when

- [x] The test no longer runs as part of the normal local or CI suite.
- [x] The skip reason states why (probabilistic, needs real contention) and how to run it by hand.
- [x] The test itself is unchanged and still compiles — it is disabled, not removed.

## Outcome

`[Fact(Skip = "25-40: probabilistic, the same class of flake 25-36 already named...")]` added
directly on the test method in `tests/Ago.Chat.Concurrency.Tests/CloseConversationCapacityConcurrencyTests.cs`.
Landed in `ago-chat#250`, per the author's own instruction to repeat `25-36`'s handling rather than
decide anew.

**Worth naming rather than fixing here**: two of this codebase's own self-diagnosing concurrency
storm tests have now flaked on a real CI runner within the same session — worth a look, if this
recurs a third time, at whether the storm's own parameters (batch size, thread count, timeout) need
tuning for the CI runner's weaker contention characteristics, rather than continuing to add one-off
skips.
