# 25-45 · The re-offer test asserts a count that depends on today's real date

- **Stage**: 25
- **Status**: done — `ago-calendar#60`
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

- [x] The actual cause is confirmed (date-dependency or something else) and written down here.
- [x] The test passes deterministically regardless of which real calendar date it runs on, proven by
      running it against more than one system date if the fix is a fixed clock.

## Outcome

**Confirmed cause - refines the working theory, doesn't just match it.** The failure is not really
about which *day of the month* the suite runs on; it is about the real clock's own *time-of-day* at
the moment two specific lines execute. `InitializeAsync` seeded its own slot at
`DateTimeOffset.UtcNow.AddDays(7)`; the test's own `secondSlot` (added later, in the test body) seeded
at a second, independent `DateTimeOffset.UtcNow.AddDays(7).AddHours(2)` - two separate reads of the
real clock, moments apart, both assumed (per the test's own comment, "both seeded slots fall on the
same day") to land on the same UTC calendar date. `CalendarSeed.Slot`'s own `LocalDate` (the field the
date round actually groups by, `ModuleStepFactory.GroupBy(s => s.LocalDate)`) is computed as
`DateOnly.FromDateTime(startsAt.UtcDateTime)` - the raw UTC date component, not a real conversion
through the tenant's own timezone (a pre-existing shortcut every directly-inserted test slot in this
project takes, not something `25-45` needed to touch). Whenever the real clock's own time-of-day at
that moment fell in `[22:00, 24:00)` UTC - the last two hours of any UTC day - the `+2h` on the second
read crossed midnight, giving the two slots different `LocalDate`s and splitting the date round from
the intended one date into two, which is exactly `Assert.Single(afterWorker.Step!.Actions)` throwing
"expected single element, found 2".

Reproduced live: at the real time this item was picked up (04:44 UTC), the test passed outright,
confirming the mechanism is time-of-day-dependent rather than a constant, universal failure - and
matching the item's own note that the original report never re-ran it against a different date to
confirm the theory.

**Fix**: a single anchor (`_seedSlotsAnchor`), computed once in `InitializeAsync` from the real
clock's *date* component seven days out but a *fixed* time-of-day (09:00 UTC, chosen far from any
midnight boundary), shared by both the first slot and the re-offer test's own second slot instead of
each reading `DateTimeOffset.UtcNow` independently. Still genuinely days ahead of the real host
clock's own "now" (the constraint this integration test cannot fake - it drives a real HTTP host whose
services resolve a real, unfaked `IClock`), just no longer at an uncontrolled hour.

**Proof, exhaustive rather than a couple of sampled dates**: a temporary diagnostic test (added,
run, deleted - never part of this change) swept the old two-independent-reads formula and the new
single-fixed-anchor formula across the full 24-hour range, including both danger-window boundaries
(21:59/22:00, 23:59/00:00). The old formula mismatched `LocalDate`s if and only if the sampled hour
was `>= 22`, exactly matching the confirmed cause; the new formula never mismatched, for any hour
sampled, and always resolved to something still comfortably in the future relative to the simulated
"now". This is a stronger proof than re-running the suite at a couple of arbitrary real clock times
(which the Done-when's own wording allows) - it covers the entire space the bug could occur in, not a
sample of it.

Not `[Fact(Skip = ...)]` - the item's own warning against that remedy: the test's own logic was
correct, only its fixture's date arithmetic was not deterministic.

**Verification** (`ago-calendar-25-45`, branched off `origin/main` pre-`25-44` as directed): `dotnet
format --verify-no-changes` clean, `dotnet build -c Release` 0 warnings/0 errors, `dotnet test
-c Release`: `Ago.Calendar.Domain.Tests` 229/229, `Ago.Calendar.Application.Tests` 204/204,
`Ago.Calendar.Architecture.Tests` 26/26, `Ago.Calendar.Concurrency.Tests` 26/26,
`Ago.Calendar.Integration.Tests` 310/310 (real Postgres) - the entire suite green, not only the one
test, confirming this was an isolated fixture bug rather than a symptom of something broader.
