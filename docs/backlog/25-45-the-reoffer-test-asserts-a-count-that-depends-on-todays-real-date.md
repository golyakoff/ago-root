# 25-45 · The re-offer test asserts a count that depends on today's real date

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-10, while independently verifying `23-88`'s `ago-calendar` half — the full
  `Ago.Calendar.slnx` suite run against the unmodified `origin/main` baseline (`ccb4c39`, no `23-88`
  changes present) already failed on this one test, so it is pre-existing and unrelated to that item.

## What is actually true

`Ago.Calendar.Integration.Tests.ChatModuleTaskEndpointTests.AFailedBookingAttempt_ReOffersFreshSlots_AndTheSecondAttemptCanStillSucceed`
fails today. It asserts that a failed booking attempt gets re-offered fresh slots on **exactly one**
day; the real run produces **two**. Reproduced twice, in isolation, against a clean checkout with no
other changes present — not a flake in the sense `25-36`/`25-40` already named (those self-diagnose a
storm that failed to produce real contention); this one is deterministic against today's own date and
was not re-run against a different date to confirm the theory.

## Why this is not `25-36`/`25-40`'s pattern

Those two skip a test that occasionally fails to produce the concurrency it needs to prove anything,
on a quiet CI runner — the test's own logic is correct, timing is not. This test's own logic appears to
depend on how many days the slot-offering window spans from **today**, which is not a fixed quantity —
a run on one calendar date and a run on another can legitimately produce a different number of days
without either being wrong about anything, if the window crosses a boundary (a week, a month, a
holiday calendar) the test's own fixture does not control for. That is a guess pending investigation,
not a confirmed diagnosis — the point of filing this rather than skipping it blind is that whoever
picks it up should look at `AFailedBookingAttempt_ReOffersFreshSlots_AndTheSecondAttemptCanStillSucceed`'s
own fixture and decide whether the fix is pinning a fake clock, changing the assertion to a range, or
something the guess above has not considered.

## Scope

- Read the test and its fixture; confirm or replace the date-dependency theory above.
- Fix at the root — most likely pinning `IClock` to a fixed instant in this test's own fixture, the
  same discipline `docs/conventions/date-and-time.md` already requires everywhere else — rather than
  loosening the assertion to tolerate whatever a real run happens to produce.

## Where this is likely to go wrong

- **Do not reach for `[Fact(Skip = ...)]` by default.** That is the correct remedy for `25-36`/`25-40`'s
  own probabilistic-contention flakes; it is very likely the wrong one here, since a date-dependent
  assertion is a real, fixable bug in the test's own fixture (a missing fake clock), not an inherent
  property of what is being tested.

## Done when

- [ ] The actual cause is confirmed (date-dependency or something else) and written down here.
- [ ] The test passes deterministically regardless of which real calendar date it runs on, proven by
      running it against more than one system date if the fix is a fixed clock.
