# a concurrency test fails when its own storm does not storm

- **Stage**: 23
- **Status**: done — `ago-chat#265`
- **Verified**: 2026-09-12 — confirmed both the named test and its exact assert message are real in
  `ago-chat/tests/Ago.Chat.Concurrency.Tests/TransferConversationConcurrencyTests.cs:60,194`. The
  "check the neighbours" claim holds wider than stated: `RateLimitingConcurrencyTests.cs` exists as
  named, and the identical assert message (`"the storm produced no Postgres deadlock at all, so it
  proved nothing"`) is also present in `CloseConversationCapacityConcurrencyTests.cs:377` — a second,
  previously-unnamed sibling with the same shape. Both `TransferringRacesTheAssignmentEngine_...` and
  `ClosesStormingAssignmentBatches_...` are currently marked `[SKIP]` in a real local full-suite run
  (`dotnet test Ago.Chat.slnx -c Release`, 2026-09-12), directly corroborating the problem this item
  describes.
- **Depends on**: nothing.
- **Found**: 2026-09-07, on `23-83`'s CI run — an item that touches nothing this test exercises.

## What happened

`TransferConversationConcurrencyTests.TransferringRacesTheAssignmentEngine_NeverCorruptsCapacityOrDropsTheConversation`
failed on a GitHub runner with:

> the storm produced no Postgres deadlock at all, so it proved nothing

and the diagnostic line `assigned=10; closed=21; transferred=0; postgres deadlock reports=0`.

The same test passed locally, 70 of 70, on the identical tree. The pull request it blocked removes
tenant-facing module-provisioning routes and has no path to conversation transfer at all.

## The test is right, and that is the problem

**This is not a flaky assertion — it is a test refusing to report a meaningless pass.** It drives a
storm of concurrent transfers and assignments, and then checks that the storm *actually produced
contention* before drawing any conclusion from the absence of corruption. With `transferred=0` and no
deadlock reports, nothing raced, so a green would have asserted only that the test did nothing.

That design is better than the alternative. A concurrency test that passes when its setup silently
failed is worse than useless: it is a gate reporting safety it never checked, which is the exact shape
`15-21`'s drift check turned out to have in a different corner of this project.

**But a gate that reddens on a loaded runner, for reasons unrelated to the change under review, gets
re-run rather than read.** That is how a real failure eventually merges: not by anyone deciding to
ignore it, but by "re-run the flaky one" becoming the habit, and this test's message being long enough
that nobody reads past the word *failed*. The cost here is not this pull request; it is the next
genuine concurrency regression, which will look exactly like this one.

## Scope

- **Make the storm produce contention reliably, or make its absence a retry rather than a failure.**
  Both are legitimate; they differ in what they promise. A retry says *this run could not test the
  property*; a determinism fix says *this run always tests it*. Say which was chosen and why.
- **The vacuous pass must stay impossible.** Whatever changes, the property that a storm which did not
  storm cannot report success is the thing worth keeping — it is the reason this failure was legible
  at all.
- **Check the neighbours.** `RateLimitingConcurrencyTests` was reported flaking under local machine
  contention on the same day, which suggests this is a family rather than one test.

## Where this is likely to go wrong

- **Do not fix it by loosening the assertion.** Dropping the *did it actually race* check would make
  this test green forever and worthless, which is a worse outcome than an occasional red.
- **A bare retry can hide a real regression** if the retried run also fails to storm and the retry
  budget then exhausts into a pass. If a retry is the answer, exhausting it must fail, not pass.
- **CI runners are slower and more variable than this machine.** Anything tuned against a local run
  will be tuned against the wrong distribution — the local suite passed this test the same evening it
  failed on CI.

## Done when

- [x] A run on a loaded CI runner either tests the property or says it could not, and does not fail the
      build for the second case unless the retries are exhausted.
- [x] A storm that did not storm still cannot report success.
- [x] Whether the neighbouring concurrency tests share this shape is established and written down.

## Outcome

Chose a bounded retry (up to 3 fresh-seeded storm attempts, stopping at the first that actually
produces a Postgres deadlock) over retuning the storm's own parameters — the item's own "Where this is
likely to go wrong" section warns that tuning against this machine risks tuning against the wrong CI
contention distribution, and a retry needs no such assumption. The correctness assertions (no escaped
exception, the exact capacity invariant) run unconditionally on every attempt and fail immediately,
never retried; only "didn't storm" is retried, and exhausting every attempt without ever storming still
fails the test with an explicit message — the vacuous-pass property stays intact. Both
`TransferringRacesTheAssignmentEngine_...` and `ClosesStormingAssignmentBatches_...` are un-skipped.

Proved by breaking it: forcing `deadlockReports=0` drove exactly 3 attempts then failed with the
exhaustion message; injecting a fake escaped exception failed immediately on attempt 1, never retried.

**Neighbours, checked**: `RateLimitingConcurrencyTests` does not share this shape — its two tests
assert exact, deterministic counts, never a "did contention happen" self-check; its one prior CI flake
(a `RetryAfter` timing issue) was already fixed differently, by waiting the exact value Redis returns.

**Verification**: `dotnet format --verify-no-changes` clean; `dotnet build -c Release` 0 warnings;
`dotnet test -c Release`, 6/6 assemblies, 0 failed — Domain 646, Application 1103, Architecture 44,
FakeCrm 21, Concurrency 75 (0 skipped, previously 2), Integration 1104.
