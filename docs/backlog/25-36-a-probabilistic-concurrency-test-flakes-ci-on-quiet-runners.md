# 25-36 · A probabilistic concurrency test flakes CI on quiet runners

- **Stage**: 25
- **Status**: done — `ago-chat#246`
- **Depends on**: nothing
- **Found**: 2026-09-09, live — the automatic post-merge `main`-branch CI run for `25-34`
  (`ago-chat#245`) failed on `build-test`, blocking `publish-images` and therefore blocking deployment,
  even though `25-34`'s own PR had passed its required check cleanly moments earlier.

## What is actually true

`TransferConversationConcurrencyTests
.TransferringRacesTheAssignmentEngine_NeverCorruptsCapacityOrDropsTheConversation` is deliberately
self-diagnosing: it asserts `deadlockReports > 0`, on the reasoning that a storm producing no Postgres
deadlock at all "proved nothing" about the behaviour under test. That honesty is also what makes it
flaky — on a quiet CI runner, the storm can genuinely fail to produce a deadlock through timing
variance alone, unrelated to any regression in the commit under test. `gh run rerun <run-id> --failed`
against the same commit succeeded on retry, confirming the failure was the test's own timing
sensitivity and not `25-34`.

**Explicit author instruction**: disable the test's normal local/CI run without deleting it — it
still catches something real when it does fire, and it stays runnable by hand
(`dotnet test --filter`) when actually investigating a concurrency storm on this path.

## Scope

- `[Fact(Skip = "...")]` on the one test, with a reason naming why it is skipped and how to run it
  deliberately. Not a rewrite of the test, not a deletion.

## Done when

- [x] The test no longer runs as part of the normal local or CI suite.
- [x] The skip reason states why (probabilistic, needs real contention) and how to run it by hand.
- [x] The test itself is unchanged and still compiles — it is disabled, not removed.

## Outcome

`[Fact(Skip = "25-36: probabilistic - needs a real Postgres deadlock to occur under contention, and
can spuriously fail on a quiet CI runner with no relation to the commit under test. Run by hand with
--filter when actually investigating this storm.")]` added directly on the test method in
`tests/Ago.Chat.Concurrency.Tests/TransferConversationConcurrencyTests.cs`. Landed alongside `25-34`'s
own fix, in `ago-chat#246`, and confirmed the post-merge CI run went green on retry.
