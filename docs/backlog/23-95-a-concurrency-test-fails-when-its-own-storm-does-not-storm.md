# a concurrency test fails when its own storm does not storm

- **Stage**: 23
- **Status**: ready
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

- [ ] A run on a loaded CI runner either tests the property or says it could not, and does not fail the
      build for the second case unless the retries are exhausted.
- [ ] A storm that did not storm still cannot report success.
- [ ] Whether the neighbouring concurrency tests share this shape is established and written down.
